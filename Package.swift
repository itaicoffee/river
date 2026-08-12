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
      exclude: ["Info.plist"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreLocation"),
        .linkedFramework("CoreServices"),
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/River/Info.plist",
        ]),
      ]
    ),
    .testTarget(name: "RiverTests", dependencies: ["River"], path: "Tests/RiverTests"),
  ]
)
