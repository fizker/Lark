import Foundation
import SchemaParser
import CodeGenerator

var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}

func exit(reason: String) -> Never {
	print(reason, to: &standardError)
	printUsage()
	exit(1)
}

func printUsage() {
    print("usage: lark-generate-client WSDL", to: &standardError)
}

if CommandLine.arguments.contains("-h") || CommandLine.arguments.contains("--help") {
    print("Generate code for types and client from WSDL", to: &standardError)
    printUsage()
    exit(1)
}

var options = [GeneratorOption]()

var args = CommandLine.arguments
while true {
	guard let index = args.firstIndex(where: { $0.hasPrefix("-") })
	else { break }

	switch args[index] {
	case "--access-level", "-a":
		guard args.count > index + 1, let accessLevel = AccessLevel(rawValue: args.remove(at: index + 1))
		else { exit(reason: "--access-level must be followed by one of the following: \(AccessLevel.allCases.map(\.rawValue).joined(separator: ", "))") }

		args.remove(at: index)

		options.append(.accessLevel(accessLevel))
	default:
		print("Unknown option: \(args[index])", to: &standardError)
		printUsage()
		exit(1)
	}
}

if args.count != 2 {
    print("error: need the location of the WSDL as a single argument", to: &standardError)
    printUsage()
    exit(1)
}

let webService: WebServiceDescription
do {
    let webServiceURL = args[1].hasPrefix("http") ? URL(string: args[1])! : URL(fileURLWithPath: args[1])
    webService = try parseWebServiceDescription(contentsOf: webServiceURL)
} catch {
    print("error when parsing WSDL: \(error)", to: &standardError)
    exit(1)
}

guard let service = webService.services.first else {
    print("error: could not find service in WSDL", to: &standardError)
    exit(1)
}

do {
    try print(generate(webService: webService, service: service, options: options))
} catch {
    print("error when generating code: \(error)", to: &standardError)
    exit(1)
}
