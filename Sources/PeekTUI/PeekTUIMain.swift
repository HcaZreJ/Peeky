import Darwin
import Foundation
import PeekyCore

/// 终端版入口：解析参数、启动运行时，返回进程退出码。
///
/// 在终端里运行时进入全屏界面，直到用户按 q 退出（进程在运行时里退出，不返回）；
/// 标准输出不是终端（管道、重定向）时直接输出文件文本。
public enum PeekTUIMain {
    static let usage = """
    用法：peek-tui <文件>[:行[:列]] | <目录>
      在当前终端里打开文件（左侧是所在仓库的文件树）或目录；按 q 退出。
    """

    public static func run(arguments: [String]) -> Int32 {
        let options = Array(arguments.dropFirst())
        if options.contains("--help") || options.contains("-h") {
            print(usage)
            return 0
        }
        guard let argument = options.first(where: { !$0.hasPrefix("-") }) else {
            printError(usage)
            return 2
        }
        guard let request = OpenRequest.commandLineArgument(argument) else {
            printError("peek：找不到 \(argument)")
            return 1
        }
        guard let terminal = TerminalSession() else {
            return printPlain(request.url)
        }
        MainActor.assumeIsolated {
            let runtime = TUIRuntime(terminal: terminal, request: request)
            runtime.start()
            keepAlive = runtime
        }
        runMainLoop()
    }

    /// 让主线程一直跑 RunLoop，主队列（MainActor）的任务都在主线程上执行。
    /// 不用 `dispatchMain()`：它会让主线程退出，主队列改由其他线程执行，
    /// Swift 6 的主线程隔离检查会因此中止进程。RunLoop 没有输入源时会立刻返回，
    /// 所以挂一个不会触发的定时器让它一直运行；进程在用户按 q 时由运行时退出。
    private static func runMainLoop() -> Never {
        let keepRunning = Timer(timeInterval: .greatestFiniteMagnitude, repeats: false) { _ in }
        RunLoop.main.add(keepRunning, forMode: .default)
        while true {
            RunLoop.main.run()
        }
    }

    @MainActor private static var keepAlive: TUIRuntime?

    private static func printPlain(_ url: URL) -> Int32 {
        do {
            let loaded = try TextFileLoader.load(url: url)
            FileHandle.standardOutput.write(Data(PlainOutput.text(for: loaded).utf8))
            return 0
        } catch {
            printError("peek：读不了 \(url.path)：\(error.localizedDescription)")
            return 1
        }
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
