import Foundation

/// 顶栏副标题里的「最后更改于」一段：文件在磁盘上的修改时间，按本地时区精确到秒，
/// 用来对上这份文件是哪一次会话里生成或改写的。
enum LastModifiedText {
    static func format(_ modifiedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        // 固定 POSIX locale：用户在系统里选了 12 小时制时，HH 也照样输出 24 小时制。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy 年 MM 月 dd 日 HH:mm:ss"
        return "最后更改于：\(formatter.string(from: modifiedAt))"
    }
}
