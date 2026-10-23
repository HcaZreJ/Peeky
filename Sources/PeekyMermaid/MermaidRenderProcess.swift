import AppKit
import PeekyCore
import WebKit

/// 辅助程序 `peeky-mermaid` 的入口：解析命令行，画完退出。
public enum PeekyMermaidMain {
    @MainActor
    public static func run() -> Never {
        switch MermaidRenderJob.parse(CommandLine.arguments) {
        case let .success(job):
            MermaidRenderProcess.run(job)
        case let .failure(error):
            FileHandle.standardError.write(Data("peeky-mermaid: \(error.message) [\(error.code)]\n".utf8))
            exit(64)
        }
    }
}

/// 不开窗口、不出 Dock 图标，在不上屏的窗口里用 WKWebView 逐张画 Mermaid 图，按窗口的 backing scale
/// （Retina 上 2 倍）截成透明底 PNG 写到输出路径，全部画完退出。
///
/// 它是单独的辅助程序，打包在 `Peeky.app/Contents/Helpers/`：放在 `Contents/MacOS/` 里时系统把它当成
/// 正在运行的 Peeky，`peek --app`（`open -a Peeky.app`）的打开请求会送到它这里丢掉。
///
/// 退出码：0 全部画出；1 有图画不出来（它的 PNG 不写，原因写进 stderr）；2 找不到 mermaid.js；3 超时；
/// 64 命令行不对。
@MainActor
final class MermaidRenderProcess: NSObject, WKNavigationDelegate {
    /// 画图的栏宽（CSS 像素），同 app Markdown 正文栏（980 减左右各 24 的内边距）：
    /// 宽图缩到这个宽度，与 app 里看到的一样。
    static let columnWidth: CGFloat = 932
    /// 图高超过这么多（CSS 像素）时按比例缩小截图，免得出几万像素高的 PNG。
    static let maximumHeight: CGFloat = 4096
    static let timeout: DispatchTimeInterval = .seconds(20)

    private static let pageHTML = """
        <!doctype html><html><head><meta charset="utf-8">\
        <style>html,body{margin:0;background:transparent}#host{width:\(Int(columnWidth))px}</style>\
        </head><body><div id="host"></div></body></html>
        """

    /// 清掉上一张留下的临时节点，画一张图放进 #host，返回 SVG 的包围盒（CSS 像素）。
    private static let renderScript = """
        document.querySelectorAll('body > :not(#host)').forEach(function(e){e.remove();});
        mermaid.initialize(JSON.parse(options));
        const host=document.getElementById('host');
        host.innerHTML='';
        const result=await mermaid.render(id,source);
        host.innerHTML=result.svg;
        const box=host.querySelector('svg').getBoundingClientRect();
        return [box.x,box.y,box.width,box.height];
        """

    private struct RenderFailure: Error {
        let code: String
        let message: String
    }

    private let job: MermaidRenderJob
    private let window: NSWindow
    private let webView: WKWebView

    /// 跑完任务后退出进程，不返回。
    static func run(_ job: MermaidRenderJob) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let library = MermaidDiagram.loadLibrary() else {
            writeError("找不到 mermaid.js 资源 [library_missing]")
            exit(2)
        }
        let process = MermaidRenderProcess(job: job, library: library)
        process.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            writeError("超过 20 秒没画完 [timeout]")
            exit(3)
        }
        app.run()
        exit(0)
    }

    private init(job: MermaidRenderJob, library: String) {
        self.job = job
        let configuration = WKWebViewConfiguration()
        // 库走注入脚本，不内联进 HTML（库里的 `<!--` 之类会干扰 HTML 解析）
        configuration.userContentController.addUserScript(
            WKUserScript(source: library, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let frame = NSRect(x: 0, y: 0, width: Self.columnWidth, height: 600)
        webView = WKWebView(frame: frame, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    private func start() {
        webView.loadHTMLString(Self.pageHTML, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            startRendering()
        }
    }

    private func startRendering() {
        Task { await renderAll() }
    }

    private func renderAll() async {
        var failed = false
        for (index, diagram) in job.diagrams.enumerated() {
            do {
                let png = try await render(diagram, id: "peeky-diagram-\(index)")
                try png.write(to: diagram.output)
            } catch {
                failed = true
                try? FileManager.default.removeItem(at: diagram.output)
                let failure = error as? RenderFailure ?? RenderFailure(code: "render_failed", message: Self.describe(error))
                Self.writeError("\(diagram.source.path): \(failure.message) [\(failure.code)]")
            }
        }
        exit(failed ? 1 : 0)
    }

    private func render(_ diagram: MermaidRenderJob.Diagram, id: String) async throws -> Data {
        guard let source = try? String(contentsOf: diagram.source, encoding: .utf8) else {
            throw RenderFailure(code: "source_unreadable", message: "读不了源码文件")
        }
        let options = MermaidDiagram.initializeOptionsJSON(appearance: job.appearance)
        let value = try await webView.callAsyncJavaScript(
            Self.renderScript,
            arguments: ["source": source, "options": options, "id": id],
            contentWorld: .page
        )
        guard let numbers = value as? [NSNumber], numbers.count == 4 else {
            throw RenderFailure(code: "no_svg", message: "mermaid 没有画出 SVG")
        }
        let box = numbers.map { CGFloat($0.doubleValue) }
        let width = ceil(box[2])
        let height = ceil(box[3])
        guard width > 0, height > 0 else {
            throw RenderFailure(code: "empty_svg", message: "画出的图是空的")
        }
        // 窗口撑到整张图都在视口里，截图才不被裁掉
        window.setContentSize(NSSize(width: max(Self.columnWidth, box[0] + width), height: box[1] + height))
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: box[0], y: box[1], width: width, height: height)
        configuration.snapshotWidth = NSNumber(value: Double(width * min(1, Self.maximumHeight / height)))
        configuration.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: configuration)
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else {
            throw RenderFailure(code: "encode_failed", message: "截图编不成 PNG")
        }
        return png
    }

    /// JS 抛错时 WebKit 只给一句「A JavaScript exception occurred」，mermaid 的原因在 userInfo 里。
    private static func describe(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        guard let message = info["WKJavaScriptExceptionMessage"] as? String else { return error.localizedDescription }
        return message.split(separator: "\n").joined(separator: " ")
    }

    private static func writeError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
