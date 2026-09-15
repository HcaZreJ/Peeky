import Foundation

/// 一棵目录子树的磁盘变化监听（FSEvents）。
///
/// FSEvents 在目录粒度上报「这个目录的内容变了」，系统按 latency 合并后从后台队列送达，
/// 本类再转回主线程交给 `onChange`。「这一轮该刷新什么」不在这里判断，由
/// `FileTreeRefresh.scope` 按已展开目录与最前 tab 的文件收窄范围。
///
/// `@unchecked Sendable` 的依据：`stream` 只在主线程读写（`watch` / `stop` 都由窗口控制器
/// 在主线程调用），C 回调只读不可变的 `onChange`。
final class DirectoryWatcher: @unchecked Sendable {
    /// 系统把这段时间内的事件合并成一次回调。0.4s 让 `npm install` 级别的密集写入收敛成
    /// 个位数次刷新，同时手感上仍然是「刚存完就出现」。
    private static let latency: CFTimeInterval = 0.4

    private let onChange: @Sendable ([String], Bool) -> Void
    private let queue = DispatchQueue(label: "com.peeky.directory-watcher")
    private var stream: FSEventStreamRef?

    init(onChange: @escaping @Sendable ([String], Bool) -> Void) {
        self.onChange = onChange
    }

    deinit {
        teardown()
    }

    /// 监听 root 及其子树；重复调用先停掉上一个 stream，一个 watcher 同时只盯一棵树。
    func watch(root: URL) {
        teardown()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()

            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            var mustScanSubDirectories = false
            for index in 0..<count
            where eventFlags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                mustScanSubDirectories = true
            }

            watcher.deliver(paths: paths, mustScanSubDirectories: mustScanSubDirectories)
        }

        // useCFTypes：eventPaths 以 CFArray 送达。
        // noDefer：距上一次事件已超过 latency 时立即送达首个事件，紧随其后的密集事件才走合并——
        // 单次保存立刻可见，批量写入不会打成一串刷新。
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func deliver(paths: [String], mustScanSubDirectories: Bool) {
        let handler = onChange
        DispatchQueue.main.async {
            handler(paths, mustScanSubDirectories)
        }
    }
}
