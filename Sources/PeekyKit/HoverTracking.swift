import AppKit

/// 悬停跟踪区的安装工具。
///
/// `NSView.toolTip` 的浮出由 `NSToolTipManager` 承载，它把一块 tracking area 挂在
/// view 上，和自建的悬停区并列在同一个 `trackingAreas` 数组里。所以重建悬停区时只摘掉
/// 自己上一次装的那一块——系统那块留在原位，tooltip 才照常浮出。
///
/// `previous` 由调用方持有：`updateTrackingAreas()` 每轮布局都会被调用，靠它认出上一轮
/// 装的是哪一块，悬停区始终只有一块。
enum HoverTracking {
    /// 悬停区覆盖 view 当前可见区域，鼠标进出时回调 view 自身。
    @MainActor
    static func reinstall(on view: NSView, previous: inout NSTrackingArea?) {
        if let previous {
            view.removeTrackingArea(previous)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: view,
            userInfo: nil
        )
        view.addTrackingArea(area)
        previous = area
    }
}
