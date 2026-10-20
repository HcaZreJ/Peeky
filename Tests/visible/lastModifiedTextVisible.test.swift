import Testing
import Foundation
@testable import PeekyKit

@Suite("Visible_lastModifiedText")
struct Visible_lastModifiedText {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func instant(_ iso8601: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso8601))
    }

    @Test("年月日与时分秒按 24 小时制写出，精确到秒")
    func formatsDateAndTimeToTheSecond() throws {
        let modifiedAt = try instant("2026-10-20T14:32:05+08:00")

        #expect(LastModifiedText.format(modifiedAt, timeZone: shanghai) == "最后更改于：2026 年 10 月 20 日 14:32:05")
    }

    @Test("个位数的月、日、时、分、秒补零，整段宽度不随日期变化")
    func padsSingleDigitFields() throws {
        let modifiedAt = try instant("2026-03-05T09:07:03+08:00")

        #expect(LastModifiedText.format(modifiedAt, timeZone: shanghai) == "最后更改于：2026 年 03 月 05 日 09:07:03")
    }

    @Test("按传入的时区换算：UTC 深夜在上海已是次日早上")
    func convertsIntoGivenTimeZone() throws {
        let modifiedAt = try instant("2026-10-20T23:30:00Z")

        #expect(LastModifiedText.format(modifiedAt, timeZone: shanghai) == "最后更改于：2026 年 10 月 21 日 07:30:00")
        #expect(LastModifiedText.format(modifiedAt, timeZone: TimeZone(identifier: "UTC")!) == "最后更改于：2026 年 10 月 20 日 23:30:00")
    }
}
