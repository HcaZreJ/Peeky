import Foundation
import JavaScriptCore
import os

/// 单个高亮 token：文本片段 + 前景色（#rrggbb，小写十六进制）。
struct HighlightedToken: Equatable {
    var text: String
    var colorHex: String
}

/// 一行的 token 序列（token.text 依序拼接 == 该行原文，不含换行符）。
typealias HighlightedLine = [HighlightedToken]

/// 分块产出的连续行区间。
struct HighlightChunk: Equatable {
    /// 0-based 起始行号
    var firstLine: Int
    var lines: [HighlightedLine]
}

/// JSC+Shiki 高亮服务：JSContext 单例 + 后台串行队列。
/// 引擎故障/超预算/未知语言一律返回 nil（调用方纯文本回退），不抛错不崩溃。
final class HighlightService: @unchecked Sendable {
    static let shared = HighlightService()

    /// 高亮预算（UTF-16 code unit 数），超限返回 nil
    static let maxUTF16Length = 1_500_000

    /// 扩展名（小写、不含点）→ shiki language id；不支持返回 nil
    static func language(forExtension ext: String) -> String? {
        extensionToLanguage[ext.lowercased()]
    }

    /// 启动预热（eval bundle + 引擎 init + 空 tokenize），幂等，后台执行。
    func warmUp() {
        queue.async { [self] in
            guard !hasWarmedUp else { return }
            hasWarmedUp = true

            guard ensureContextReady() else { return }
            _ = tokenizeFull(text: "", language: Self.warmupLanguage)
        }
    }

    /// 全量高亮。返回行数与输入行数一致（text 按 \n 切分）。
    func highlight(text: String, language: String) async -> [HighlightedLine]? {
        guard text.utf16.count <= Self.maxUTF16Length else { return nil }
        guard Self.supportedLanguages.contains(language) else { return nil }

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard ensureContextReady() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: tokenizeFull(text: text, language: language))
            }
        }
    }

    /// 分块高亮流：按文档顺序产出（首块小而快，利于首屏上色），
    /// 直至覆盖全文后结束。nil 语义同 highlight。
    func highlightStream(text: String, language: String) -> AsyncStream<HighlightChunk>? {
        guard text.utf16.count <= Self.maxUTF16Length else { return nil }
        guard Self.supportedLanguages.contains(language) else { return nil }

        return AsyncStream { continuation in
            queue.async { [self] in
                guard ensureContextReady() else {
                    continuation.finish()
                    return
                }

                let sourceLines = text.components(separatedBy: "\n")
                var startIndex = 0
                var currentLine = 0
                var stateId: Int?
                var isFirstChunk = true

                while startIndex < sourceLines.count {
                    let chunkLineCount = isFirstChunk
                        ? Self.firstStreamChunkLineCount
                        : Self.subsequentStreamChunkLineCount
                    let endIndex = min(startIndex + chunkLineCount, sourceLines.count)
                    let chunkText = sourceLines[startIndex..<endIndex].joined(separator: "\n")

                    guard let (lines, nextStateId) = tokenizeChunk(
                        text: chunkText,
                        language: language,
                        stateId: stateId
                    ) else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(HighlightChunk(firstLine: currentLine, lines: lines))

                    stateId = nextStateId
                    currentLine = endIndex
                    startIndex = endIndex
                    isFirstChunk = false
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Configuration

    private static let extensionToLanguage: [String: String] = [
        "py": "python",
        "ts": "typescript",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "json": "json",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "swift": "swift",
        "ini": "ini",
        "conf": "ini",
        "config": "ini"
    ]

    private static let supportedLanguages: Set<String> = Set(extensionToLanguage.values)

    /// 首块行数（首屏快速上色），后续块行数（吞吐优先）。
    private static let firstStreamChunkLineCount = 200
    private static let subsequentStreamChunkLineCount = 1000

    /// warmUp() 的空 tokenize 使用的语言，任取已打包语言即可。
    private static let warmupLanguage = "javascript"

    // MARK: - State（只在 queue 上读写）

    private let queue = DispatchQueue(label: "local.peeky.HighlightService", qos: .userInitiated)
    private let logger = Logger(subsystem: "local.peeky", category: "HighlightService")

    private var context: JSContext?
    private var isDegraded = false
    private var hasLoggedDegradation = false
    private var hasWarmedUp = false

    private init() {}

    // MARK: - JSContext 生命周期（只在 queue 上调用）

    private func ensureContextReady() -> Bool {
        if isDegraded { return false }
        if context != nil { return true }

        guard let source = loadBundleSource() else {
            markDegraded(reason: "shiki-bundle.js resource not found or unreadable")
            return false
        }

        guard let newContext = JSContext() else {
            markDegraded(reason: "failed to create JSContext")
            return false
        }

        newContext.exceptionHandler = { [weak self] _, exception in
            self?.markDegraded(reason: "uncaught JS exception: \(exception?.toString() ?? "unknown")")
        }

        newContext.evaluateScript(source)
        if isDegraded { return false }

        context = newContext

        guard runInit(on: newContext) else {
            markDegraded(reason: "peekyInit() failed")
            return false
        }

        return true
    }

    private func loadBundleSource() -> String? {
        guard let url = Bundle.module.url(forResource: "shiki-bundle", withExtension: "js") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func runInit(on context: JSContext) -> Bool {
        let script = """
        (function() {
          var __r = { done: false };
          peekyInit().then(function() {
            __r.done = true;
          }, function(e) {
            __r.done = true;
            __r.error = String(e && e.message || e);
          });
          return __r;
        })();
        """

        guard let result = context.evaluateScript(script) else { return false }
        if isDegraded { return false }

        if result.objectForKeyedSubscript("error")?.isUndefined == false {
            return false
        }

        return result.objectForKeyedSubscript("done")?.toBool() ?? false
    }

    // MARK: - Tokenize（只在 queue 上调用）

    private func tokenizeFull(text: String, language: String) -> [HighlightedLine]? {
        guard let context else { return nil }

        context.setObject(text, forKeyedSubscript: "__peekyText" as NSString)
        context.setObject(language, forKeyedSubscript: "__peekyLang" as NSString)

        let script = """
        (function() {
          var __r = { done: false };
          peekyTokenize(__peekyText, __peekyLang).then(function(v) {
            __r.done = true;
            __r.lines = v.lines;
          }, function(e) {
            __r.done = true;
            __r.error = String(e && e.message || e);
          });
          return __r;
        })();
        """

        guard let result = context.evaluateScript(script) else {
            markDegraded(reason: "evaluateScript returned nil for peekyTokenize")
            return nil
        }
        if isDegraded { return nil }

        let errorValue = result.objectForKeyedSubscript("error")
        if errorValue?.isUndefined == false {
            markDegraded(reason: "peekyTokenize error: \(errorValue?.toString() ?? "unknown")")
            return nil
        }

        guard let lines = decodeLines(result.objectForKeyedSubscript("lines")) else {
            markDegraded(reason: "malformed peekyTokenize result")
            return nil
        }

        return lines
    }

    private func tokenizeChunk(
        text: String,
        language: String,
        stateId: Int?
    ) -> (lines: [HighlightedLine], stateId: Int)? {
        guard let context else { return nil }

        context.setObject(text, forKeyedSubscript: "__peekyText" as NSString)
        context.setObject(language, forKeyedSubscript: "__peekyLang" as NSString)
        let stateLiteral = stateId.map(String.init) ?? "null"

        let script = """
        (function() {
          var __r = { done: false };
          peekyTokenizeChunk(__peekyText, __peekyLang, \(stateLiteral)).then(function(v) {
            __r.done = true;
            __r.lines = v.lines;
            __r.stateId = v.stateId;
          }, function(e) {
            __r.done = true;
            __r.error = String(e && e.message || e);
          });
          return __r;
        })();
        """

        guard let result = context.evaluateScript(script) else {
            markDegraded(reason: "evaluateScript returned nil for peekyTokenizeChunk")
            return nil
        }
        if isDegraded { return nil }

        let errorValue = result.objectForKeyedSubscript("error")
        if errorValue?.isUndefined == false {
            markDegraded(reason: "peekyTokenizeChunk error: \(errorValue?.toString() ?? "unknown")")
            return nil
        }

        guard let lines = decodeLines(result.objectForKeyedSubscript("lines")) else {
            markDegraded(reason: "malformed peekyTokenizeChunk result")
            return nil
        }

        let stateValue = result.objectForKeyedSubscript("stateId")
        guard let stateValue, !stateValue.isUndefined else {
            markDegraded(reason: "missing stateId in peekyTokenizeChunk result")
            return nil
        }

        return (lines, Int(stateValue.toInt32()))
    }

    private func decodeLines(_ value: JSValue?) -> [HighlightedLine]? {
        guard let rawLines = value?.toArray() else { return nil }

        var lines: [HighlightedLine] = []
        lines.reserveCapacity(rawLines.count)

        for rawLine in rawLines {
            guard let tokenArray = rawLine as? [Any] else { return nil }

            var line: HighlightedLine = []
            line.reserveCapacity(tokenArray.count)

            for tokenAny in tokenArray {
                guard
                    let tokenDict = tokenAny as? [String: Any],
                    let text = tokenDict["t"] as? String,
                    let color = tokenDict["c"] as? String
                else {
                    return nil
                }
                line.append(HighlightedToken(text: text, colorHex: color.lowercased()))
            }

            lines.append(line)
        }

        return lines
    }

    // MARK: - 降级

    private func markDegraded(reason: String) {
        isDegraded = true
        context = nil

        if !hasLoggedDegradation {
            hasLoggedDegradation = true
            logger.error("HighlightService degraded: \(reason, privacy: .public)")
        }
    }
}
