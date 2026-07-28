import Cocoa

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
