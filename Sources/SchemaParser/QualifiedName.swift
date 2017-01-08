import Foundation

public struct QualifiedName {
    public let uri: String
    public let localName: String

    public init(uri: String, localName: String) {
        self.uri = uri
        self.localName = localName
    }

    public init(type: String, inTree tree: XMLElement) throws {
        if type.contains(":") {
            guard let namespace = tree.resolveNamespace(forName: type) else {
                throw ParseError.invalidNamespacePrefix
            }
            uri = namespace.stringValue!
        } else {
            uri = try targetNamespace(ofNode: tree)
        }
        localName = XMLElement(name: type).localName!
    }

    public static func name(ofElement node: XMLElement) throws -> QualifiedName? {
        guard let localName = node.attribute(forLocalName: "name", uri: nil)?.stringValue else {
            return nil
        }
        return try QualifiedName(uri: targetNamespace(ofNode: node), localName: localName)
    }
}

extension QualifiedName: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "(\(uri))\(localName)"
    }
}

extension QualifiedName: Equatable {
    public static func ==(lhs: QualifiedName, rhs: QualifiedName) -> Bool {
        return lhs.uri == rhs.uri && lhs.localName == rhs.localName
    }
}

extension QualifiedName: Hashable {
    public var hashValue: Int {
        return uri.hashValue % 17 + localName.hashValue
    }
}
