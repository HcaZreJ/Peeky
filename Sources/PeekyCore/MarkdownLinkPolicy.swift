import Foundation

/// markdown WebView 链接点击的导航决策：用户点的链接交系统默认程序打开，
/// WebView 永远停留在当前文档；文档内锚点跳转与程序性加载放行。
public enum MarkdownLinkPolicy {

    /// decidePolicyFor 的三种去向。
    public enum Decision: Equatable {
        /// 在 WebView 内继续导航（程序性加载 / 文档内锚点跳转）。
        case allow
        /// 静默取消（无法解析的目标，如 baseURL 为 nil 时的相对链接）。
        case cancel
        /// 取消页内导航，改用系统默认程序（浏览器 / 邮件…）打开。
        case openExternally(URL)
    }

    /// 纯决策核心。`isLinkActivated == false`（loadHTMLString 等程序性加载）一律
    /// 放行；用户点击的链接按 URL 分流：文档经 `loadHTMLString(_:baseURL: nil)`
    /// 载入后自身地址是 `about:blank`，因此 `about:blank#…` 是文档内锚点、留在
    /// 页内滚动，其余 `about:` 目标（相对路径对 about:blank 解析的产物）无处可去、
    /// 静默取消；其余合法 URL（http / https / mailto / file…）交系统默认程序打开。
    public static func decision(for url: URL?, isLinkActivated: Bool) -> Decision {
        guard isLinkActivated else { return .allow }
        guard let url else { return .cancel }
        if url.scheme?.lowercased() == "about" {
            return url.absoluteString.lowercased().hasPrefix("about:blank#") ? .allow : .cancel
        }
        return .openExternally(url)
    }
}
