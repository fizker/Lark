import Alamofire
import Foundation

/// Client instances are the gateway to access services.
///
/// Usually you wouldn't instantiate the `Client` class directly, but one
/// of the classes inheriting from `Client`. Such inheriting classes are
/// generated by Lark from WSDL provided by the service. These generated
/// classes contain typed operations as defined in the WSDL.
///
/// However advised against, you could also use a `Client` instance directly
/// to pass messages to a service. Be aware that the API of `Client` might
/// change without further warning.
open class Client {

    /// URL of the service to send the HTTP messages.
    public let endpoint: URL

    /// `Alamofire.Session` that manages the the underlying `URLSession`.
    public let session: Session

    /// SOAP headers that will be added on every outgoing `Envelope` (message).
    open var headers: [HeaderSerializable] = []

    /// Optional delegate for this client instance.
    open weak var delegate: ClientDelegate?

    /// Instantiates a `Client`.
    ///
    /// - Parameters:
    ///   - endpoint: URL of the service to send the HTTP messages.
    ///   - session: an `Alamofire.Session` that manages the
    ///     the underlying `URLSession`.
    public init(
        endpoint: URL,
        session: Session = .init())
    {
        self.endpoint = endpoint
        self.session = session
    }

    /// Synchronously call a method on the service.
    ///
    /// - Parameters:
    ///   - action: name of the action to call.
    ///   - serialize: closure that will be called to serialize the request parameters.
    ///   - deserialize: closure that will be called to deserialize the reponse message.
    /// - Returns: the service's response.
    /// - Throws: errors that might occur when serializing, deserializing or in
    ///   the communication with the service. Also it might throw a `Fault` if the
    ///   service was unable to process the request.
    open func call<T>(
        action: URL,
        serialize: @escaping (Envelope) throws -> Envelope,
        deserialize: @escaping (Envelope) throws -> T)
        throws -> DataResponse<T, Error>
    {
        let semaphore = DispatchSemaphore(value: 0)
        var response: DataResponse<T, Error>!
        let request = self.request(action: action, serialize: serialize)
        delegate?.client(self, didSend: request)
        request.responseSOAP(queue: DispatchQueue.global(qos: .default)) {
            response = $0.tryMap { try deserialize($0) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .distantFuture)
        return response
    }

    open func call<T, Decoder: XMLDeserializable>(
		action: URL,
		serialize: (`prefix`: String, localName: String, uri: String, serializer: (() -> XMLSerializable)),
		deserialize: (localName: String, uri: String, resultPath: KeyPath<Decoder, T>)
    ) throws -> DataResponse<T, Error> {
        return try call(
            action: action,
            serialize: { envelope in
                let node = XMLElement(prefix: serialize.prefix, localName: serialize.localName, uri: serialize.uri)
                node.addNamespace(XMLNode.namespace(withName: serialize.prefix, stringValue: serialize.uri) as! XMLNode)
                try serialize.serializer().serialize(node)
                envelope.body.addChild(node)
                return envelope
            },
            deserialize: { envelope -> T in
                guard let node = envelope.body.elements(forLocalName: deserialize.localName, uri: deserialize.uri).first else {
                    throw XMLDeserializationError.noElementWithName(QualifiedName(uri: deserialize.uri, localName: deserialize.localName))
                }
                let decoder = try Decoder(deserialize: node)
                return decoder[keyPath: deserialize.resultPath]
            })
	}

    /// Asynchronously call a method on the service.
    ///
    /// - Parameters:
    ///   - action: name of the action to call.
    ///   - serialize: closure that will be called to serialize the request parameters.
    ///   - deserialize: closure that will be called to deserialize the reponse message.
    ///   - completionHandler: closure that will be called when a response has
    ///     been received and deserialized. If an error occurs, the closure will
    ///     be called with a `Result.failure(Error)` value.
    /// - Returns: an `Alamofire.DataRequest` instance for chaining additional
    ///   response handlers and to facilitate logging.
    open func call<T>(
        action: URL,
        serialize: @escaping (Envelope) throws -> Envelope,
        deserialize: @escaping (Envelope) throws -> T,
        completionHandler: @escaping (Result<T, Error>) -> Void)
        -> DataRequest
    {
        let request = self.request(action: action, serialize: serialize)
        delegate?.client(self, didSend: request)
        return request.responseSOAP {
            do {
                completionHandler(.success(try deserialize($0.result.get())))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    open func call<T, Decoder: XMLDeserializable>(
        action: URL,
		serialize: (`prefix`: String, localName: String, uri: String, serializer: (() -> XMLSerializable)),
		deserialize: (localName: String, uri: String, resultPath: KeyPath<Decoder, T>),
        completionHandler: @escaping (Result<T, Error>) -> Void)
        -> DataRequest
    {
        let request = self.request(action: action, serialize: { envelope in
			let node = XMLElement(prefix: serialize.prefix, localName: serialize.localName, uri: serialize.uri)
			node.addNamespace(XMLNode.namespace(withName: serialize.prefix, stringValue: serialize.uri) as! XMLNode)
			try serialize.serializer().serialize(node)
			envelope.body.addChild(node)
			return envelope
		})
        delegate?.client(self, didSend: request)
        return request.responseSOAP {
            do {
                let envelope = try $0.result.get()
                guard let node = envelope.body.elements(forLocalName: deserialize.localName, uri: deserialize.uri).first else {
                    throw XMLDeserializationError.noElementWithName(QualifiedName(uri: deserialize.uri, localName: deserialize.localName))
                }
                let decoder = try Decoder(deserialize: node)
                let result = decoder[keyPath: deserialize.resultPath]
                completionHandler(.success(result))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    /// Perform the request and validate the response.
    ///
    /// - Parameters:
    ///   - action: name of the action to call.
    ///   - serialize: closure that will be called to serialize the request parameters.
    /// - Returns: an `Alamofire.DataRequest` instance on which a deserializer 
    ///   can be chained.
    func request(
        action: URL,
        serialize: @escaping (Envelope) throws -> Envelope)
        -> DataRequest
    {
        let call = Call(
            endpoint: endpoint,
            action: action,
            serialize: serialize,
            headers: headers)
        return session.request(call)
            .validate(contentType: ["text/xml"])
            .validate(statusCode: [200, 500])
            .deserializeFault()
    }
}

/// Client delegate protocol. Can be used to inspect incoming and outgoing messages.
///
/// For example the following example shows how to print incoming and outgoing messages to
/// standard output. You can adapt this code to log full message bodies to your logging 
/// facility. The response completion handler must be scheduled on the global queue if there
/// is no runloop (e.g. CLI applications).
///
/// ```swift
/// class Logger: Lark.ClientDelegate {
///     func client(_ client: Lark.Client, didSend request: Alamofire.DataRequest) {
///         guard let httpRequest = request.request, let identifier = request.task?.taskIdentifier else {
///             return
///         }
///         print("[\(identifier)] > \(httpRequest) \(httpRequest.httpBody)")
///         request.response(queue: DispatchQueue.global(qos: .default)) {
///             guard let httpResponse = $0.response else {
///                 return
///             }
///             print("[\(identifier)] < \(httpResponse.statusCode) \($0.data)")
///         }
///     }
/// }
/// ```
public protocol ClientDelegate: AnyObject {

    /// Will be called when a request has been sent. To see the response to the message,
    /// append a response handler; e.g. `request.response { ... }`.
    func client(_: Client, didSend request: DataRequest)
}

struct Call: URLRequestConvertible {
    let endpoint: URL
    let action: URL
    let serialize: (Envelope) throws -> Envelope
    let headers: [HeaderSerializable]

    func asURLRequest() throws -> URLRequest {
        let envelope = try serialize(Envelope())

        for header in headers {
            envelope.header.addChild(try header.serialize())
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue(action.absoluteString, forHTTPHeaderField: "SOAPAction")
        request.addValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body = envelope.document.xmlData
        request.httpBody = body
        request.addValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        return request
    }
}

extension DataRequest {
    @discardableResult
    func responseSOAP(
        queue: DispatchQueue? = nil,
        completionHandler: @escaping (_ response: AFDataResponse<Envelope>) -> Void)
        -> Self {
        if let queue = queue {
            return response(queue: queue, responseSerializer: EnvelopeDeserializer(), completionHandler: completionHandler)
        } else {
            return response(responseSerializer: EnvelopeDeserializer(), completionHandler: completionHandler)
		}
    }
}
