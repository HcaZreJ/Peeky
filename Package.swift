// swift-tools-version: 6.0

import Foundation
import PackageDescription

// Command Line Tools-only installs (no full Xcode.app) ship swift-testing as
// `Testing.framework` under the active developer directory, but SwiftPM's
// default test-target search paths do not add the required `-F` framework
// search path in that configuration, causing `import Testing` to fail with
// "no such module 'Testing'". Resolve the developer directory dynamically
// (works for both Command Line Tools and full Xcode installs) and add the
// framework search path explicitly.
func testingFrameworkSearchPath() -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    task.arguments = ["-p"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    do {
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let developerDir = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !developerDir.isEmpty
        else {
            return nil
        }
        return developerDir + "/Library/Developer/Frameworks"
    } catch {
        return nil
    }
}

var testSwiftSettings: [SwiftSetting] = []
var testLinkerSettings: [LinkerSetting] = []
if let searchPath = testingFrameworkSearchPath() {
    let interopLibPath = searchPath.replacingOccurrences(
        of: "/Library/Developer/Frameworks",
        with: "/Library/Developer/usr/lib"
    )
    testSwiftSettings.append(.unsafeFlags(["-F", searchPath]))
    // Command Line Tools 6.4 keeps the swift-testing macro plugin in a
    // `testing/` subdirectory that the swiftbuild build system does not load,
    // failing every `@Test` / `#expect` with "plugin for module
    // 'TestingMacros' not found". Point the compiler at that directory.
    let testingPluginPath = searchPath.replacingOccurrences(
        of: "/Library/Developer/Frameworks",
        with: "/usr/lib/swift/host/plugins/testing"
    )
    if FileManager.default.fileExists(atPath: testingPluginPath) {
        testSwiftSettings.append(.unsafeFlags(["-plugin-path", testingPluginPath]))
    }
    testLinkerSettings.append(.unsafeFlags([
        "-F", searchPath,
        "-framework", "Testing",
        "-Xlinker", "-rpath", "-Xlinker", searchPath,
        "-Xlinker", "-rpath", "-Xlinker", interopLibPath
    ]))
}

let package = Package(
    name: "Peeky",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Peeky", targets: ["Peeky"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        // Formatting, parsing, highlighting and file-tree logic with no AppKit
        // or WebKit: shared by the Peeky app (PeekyKit) and the terminal UI.
        .target(
            name: "PeekyCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/PeekyCore",
            resources: [.copy("Resources/shiki-bundle.js"), .copy("Resources/github-markdown.css")],
            // `PeekyTests` needs `@testable import` in every build
            // configuration: `swift build -c release` (no --product filter)
            // builds every target in the package, including PeekyTests.
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .target(
            name: "PeekyKit",
            dependencies: ["PeekyCore"],
            path: "Sources/PeekyKit",
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "Peeky",
            dependencies: ["PeekyKit"],
            path: "Sources/Peeky"
        ),
        .executableTarget(
            name: "PeekyTests",
            dependencies: ["PeekyKit", "PeekyCore"],
            path: "Tests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ]
)
