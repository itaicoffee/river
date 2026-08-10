// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "River",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "river", targets: ["River"])
  ],
  targets: [
    .executableTarget(
      name: "River",
      path: "Sources/River",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreServices"),
      ]
    ),
    .testTarget(name: "RiverTests", dependencies: ["River"], path: "Tests/RiverTests"),
  ]
)
