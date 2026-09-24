// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let rustLibrary =
  "\(packageRoot)/Rust/PurrrSpeechBridge/target/aarch64-apple-darwin/release/libpurrr_speech_bridge.a"

let package = Package(
  name: "Purrr",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "Purrr", targets: ["Purrr"])
  ],
  targets: [
    .target(
      name: "CPurrrSpeechBridge",
      path: "Sources/CPurrrSpeechBridge",
      publicHeadersPath: "include",
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-force_load", "-Xlinker", rustLibrary]),
        .linkedFramework("Security"),
        .linkedFramework("SystemConfiguration"),
        .linkedLibrary("iconv"),
        .linkedLibrary("resolv"),
      ]
    ),
    .executableTarget(
      name: "Purrr",
      dependencies: ["CPurrrSpeechBridge"],
      path: "Sources/Purrr",
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    ),
  ]
)
