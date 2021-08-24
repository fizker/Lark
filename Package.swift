// swift-tools-version:5.4

import PackageDescription

let package = Package(
    name: "Lark",
    platforms: [
        .macOS(.v10_12),
    ],
    products: [
        .library(name: "Lark", targets: ["Lark"]),
        .executable(name: "lark-generate-client", targets: ["lark-generate-client"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.4.3")
    ],
    targets: [
        .target(name: "Lark", dependencies: ["Alamofire"]),
        .target(name: "CodeGenerator", dependencies: ["Lark", "SchemaParser"]),
        .target(name: "SchemaParser", dependencies: ["Lark"]),
        .executableTarget(name: "lark-generate-client", dependencies: ["SchemaParser", "CodeGenerator"]),
        .testTarget(
            name: "CodeGeneratorTests",
            dependencies: ["CodeGenerator"],
            resources: [ .copy("Inputs") ]
        ),
        .testTarget(name: "LarkTests", dependencies: ["Lark"]),
        .testTarget(
            name: "SchemaParserTests",
            dependencies: ["SchemaParser"],
            resources: [ .copy("Inputs") ]
        )
    ]
)
