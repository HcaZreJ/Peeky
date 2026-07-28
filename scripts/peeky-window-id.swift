import Cocoa

if CommandLine.arguments.contains("--preflight") {
    if #available(macOS 11.0, *) {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            FileHandle.standardError.write(Data("Screen Recording permission missing for this terminal. Enable it in System Settings → Privacy & Security → Screen Recording, then quit and reopen the terminal before rerunning.\n".utf8))
            exit(2)
        }
    }
    exit(0)
}

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for entry in list {
    guard
        entry["kCGWindowOwnerName"] as? String == "Peeky",
        (entry["kCGWindowLayer"] as? Int) == 0,
        let bounds = entry["kCGWindowBounds"] as? [String: Any],
        let width = bounds["Width"] as? Double,
        let height = bounds["Height"] as? Double,
        width > 200, height > 200,
        let number = entry["kCGWindowNumber"] as? Int
    else { continue }
    print(number)
    exit(0)
}
exit(1)
