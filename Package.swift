// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "ToolsmithPackage",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(
      name: "Toolsmith",
      targets: ["Toolsmith"]
    ),
    .library(
      name: "SandboxRunner",
      targets: ["SandboxRunner"]
    ),
    .library(
      name: "ToolsmithAPI",
      targets: ["ToolsmithAPI"]
    ),
    .library(
      name: "ToolsmithSupport",
      targets: ["ToolsmithSupport"]
    ),
    .executable(
      name: "toolsmith-cli",
      targets: ["toolsmith-cli"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
  ],
  targets: [
    .target(
      name: "SandboxRunner",
      dependencies: ["ToolsmithSupport"],
      resources: [
        .process("Profiles")
      ]
    ),
    .target(
      name: "ToolsmithSupport",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto")
      ]
    ),
    .target(
      name: "Toolsmith",
      dependencies: ["ToolsmithSupport", "SandboxRunner"]
    ),
    .target(
      name: "ToolsmithAPI",
      dependencies: ["ToolsmithSupport"]
    ),
    .executableTarget(
      name: "toolsmith-cli",
      dependencies: ["ToolsmithAPI", "ToolsmithSupport"]
    ),
    .testTarget(
      name: "ToolsmithSupportTests",
      dependencies: ["ToolsmithSupport"]
    ),
    .testTarget(
      name: "ToolsmithTests",
      dependencies: ["Toolsmith"]
    ),
    .testTarget(
      name: "SandboxRunnerTests",
      dependencies: ["SandboxRunner"]
    ),
    .testTarget(
      name: "ToolsmithAPITests",
      dependencies: ["ToolsmithAPI"]
    ),
  ]
)
