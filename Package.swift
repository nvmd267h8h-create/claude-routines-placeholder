// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReEdit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReEditCore", targets: ["ReEditCore"]),
        .library(name: "ReEditXML", targets: ["ReEditXML"]),
        .executable(name: "reedit", targets: ["reedit-cli"]),
    ],
    targets: [
        .target(
            name: "ReEditCore",
            path: "Packages/ReEditCore/Sources"
        ),
        .target(
            name: "ReEditXML",
            dependencies: ["ReEditCore"],
            path: "Packages/ReEditXML/Sources"
        ),
        .executableTarget(
            name: "reedit-cli",
            dependencies: ["ReEditCore", "ReEditXML"],
            path: "Tools/reedit-cli/Sources"
        ),
        .testTarget(
            name: "ReEditCoreTests",
            dependencies: ["ReEditCore"],
            path: "Packages/ReEditCore/Tests"
        ),
        .testTarget(
            name: "ReEditXMLTests",
            dependencies: ["ReEditXML"],
            path: "Packages/ReEditXML/Tests"
        ),
        .testTarget(
            name: "ReEditCLITests",
            dependencies: ["reedit-cli"],
            path: "Tools/reedit-cli/Tests"
        ),
    ]
)
