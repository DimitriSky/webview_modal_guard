// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "WebViewModalGuardCore",
  platforms: [.macOS(.v10_15)],
  products: [.library(name: "WebViewModalGuardCore", targets: ["WebViewModalGuardCore"])],
  targets: [
    .target(name: "WebViewModalGuardCore", path: "macos/webview_modal_guard/Sources/webview_modal_guard/Core"),
    .testTarget(name: "WebViewModalGuardCoreTests", dependencies: ["WebViewModalGuardCore"], path: "macos/Tests"),
  ]
)
