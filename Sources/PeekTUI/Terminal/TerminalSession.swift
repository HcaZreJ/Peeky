import Darwin
import Foundation

/// 运行时与终端之间的接口；测试里可以换成内存实现。
package protocol TerminalIO: AnyObject {
    var size: TerminalSize { get }
    func write(_ text: String)
    func enter()
    func restore()
}

/// 真实终端：raw 模式、alternate screen、鼠标 / 粘贴 / 焦点 / 明暗上报的开关与还原。
///
/// 进入与退出的顺序固定（退出是进入的逆序），任何退出路径都要还原：正常退出、
/// SIGTERM / SIGHUP、以及 `atexit` 兜底。
package final class TerminalSession: TerminalIO {
    /// alternate screen → 隐藏光标 → 鼠标点击 / 拖动 / SGR 编码 → 括号粘贴 → 焦点事件 → 明暗通知 → kitty 键盘协议（消歧）
    static let enterSequence = "\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h\u{1B}[?2004h\u{1B}[?1004h\u{1B}[?2031h\u{1B}[>1u"
    static let exitSequence = "\u{1B}[<u\u{1B}[?2031l\u{1B}[?1004l\u{1B}[?2004l\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l"

    package init?() {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { return nil }
    }

    package var size: TerminalSize {
        var window = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &window) == 0, window.ws_col > 0, window.ws_row > 0 else {
            return TerminalSize(columns: 80, rows: 24)
        }
        return TerminalSize(columns: Int(window.ws_col), rows: Int(window.ws_row))
    }

    package func enter() {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return }
        if TerminalRestore.saved == nil {
            TerminalRestore.saved = original
            atexit { TerminalRestore.restoreIfNeeded() }
        }
        var raw = original
        cfmakeraw(&raw)
        withUnsafeMutableBytes(of: &raw.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        TerminalRestore.redirectStandardError()
        TerminalRestore.isActive = true
        write(Self.enterSequence)
    }

    package func restore() {
        TerminalRestore.restoreIfNeeded()
    }

    package func write(_ text: String) {
        TerminalRestore.writeAll(text)
    }
}

/// 还原所需的全局状态：`atexit` 与信号处理只能调用不捕获上下文的函数。
enum TerminalRestore {
    nonisolated(unsafe) static var saved: termios?
    nonisolated(unsafe) static var isActive = false
    nonisolated(unsafe) static var savedStandardError: Int32 = -1

    /// 界面运行期间的 stderr 日志：库函数往 stderr 写的任何字都会打在画面上、把整屏顶上去一行，
    /// 所以运行期间 stderr 改写到这个文件，退出时还原。
    static var logPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("peek-tui.log")
    }

    static func redirectStandardError() {
        guard savedStandardError < 0 else { return }
        let log = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard log >= 0 else { return }
        savedStandardError = dup(STDERR_FILENO)
        dup2(log, STDERR_FILENO)
        close(log)
    }

    static func restoreIfNeeded() {
        guard isActive else { return }
        isActive = false
        writeAll(TerminalSession.exitSequence)
        if var original = saved {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        }
        if savedStandardError >= 0 {
            dup2(savedStandardError, STDERR_FILENO)
            close(savedStandardError)
            savedStandardError = -1
        }
    }

    static func writeAll(_ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { buffer in
                Darwin.write(STDOUT_FILENO, buffer.baseAddress, buffer.count)
            }
            if written > 0 {
                offset += written
            } else if errno != EINTR && errno != EAGAIN {
                return
            }
        }
    }
}
