import Foundation

/// `PEEK_TUI_TRACE=1` 时把各阶段耗时写到 stderr（界面运行期间 stderr 已重定向到 `$TMPDIR/peek-tui.log`），
/// 不写屏幕。未开启时什么也不做。
package struct PhaseTrace: Sendable {
    package static let isEnabled = ProcessInfo.processInfo.environment["PEEK_TUI_TRACE"] == "1"

    private let label: String
    private let start = ContinuousClock.now
    private var last = ContinuousClock.now

    package init(_ label: String) {
        self.label = label
    }

    package mutating func mark(_ phase: String) {
        guard Self.isEnabled else { return }
        let now = ContinuousClock.now
        let phaseMilliseconds = Self.milliseconds(now - last)
        let totalMilliseconds = Self.milliseconds(now - start)
        last = now
        FileHandle.standardError.write(Data("[peek-tui] \(label) \(phase): \(phaseMilliseconds) ms (累计 \(totalMilliseconds) ms)\n".utf8))
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
