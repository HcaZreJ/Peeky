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
        .target(
            name: "PeekyKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/PeekyKit",
            resources: [.copy("Resources/shiki-bundle.js")],
            // `PeekyTests` needs `@testable import PeekyKit` in every build
            // configuration: `swift build -c release` (no --product filter)
            // builds every target in the package, including PeekyTests, so
            // PeekyKit must stay testable even in release configuration.
            swiftSettings: [.unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "Peeky",
            dependencies: ["PeekyKit"],
            path: "Sources/Peeky"
        ),
        .executableTarget(
            name: "PeekyTests",
            dependencies: ["PeekyKit"],
            path: "Tests",
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        )
    ]
)
