import AppKit
import Foundation

struct PreviewGutterMarker {
    let characterLocation: Int
    let label: String
    let isWarning: Bool
}

enum PreviewGutterMode {
    case hidden
    case lineNumbers(lineStartLocations: [Int])
    case markers([PreviewGutterMarker])
}

struct PreviewGutterConfiguration {
    let mode: PreviewGutterMode
    let width: CGFloat

    var isVisible: Bool {
        switch mode {
        case .hidden:
            false
        case .lineNumbers, .markers:
            true
        }
    }

    static let hidden = PreviewGutterConfiguration(mode: .hidden, width: 0)

    static func lineNumbers(for text: String) -> PreviewGutterConfiguration {
        let starts = PreviewDisplayMetadata.lineStartLocations(in: text)
        return PreviewGutterConfiguration(
            mode: .lineNumbers(lineStartLocations: starts),
            width: gutterWidth(maxLabelLength: max(2, String(max(starts.count, 1)).count))
        )
    }

    static func markers(_ markers: [PreviewGutterMarker]) -> PreviewGutterConfiguration {
        guard !markers.isEmpty else { return .hidden }
        let maxLabelLength = markers.map(\.label.count).max() ?? 2
        return PreviewGutterConfiguration(
            mode: .markers(markers),
            width: gutterWidth(maxLabelLength: max(2, maxLabelLength))
        )
    }

    private static func gutterWidth(maxLabelLength: Int) -> CGFloat {
        max(30, CGFloat(maxLabelLength) * 7 + 12)
    }
}

struct PreviewTextOverlayConfiguration {
    let recordSeparatorLocations: [Int]

    static let hidden = PreviewTextOverlayConfiguration(
        recordSeparatorLocations: []
    )
}

struct PreviewDisplayMetadata {
    let gutter: PreviewGutterConfiguration
    let textOverlay: PreviewTextOverlayConfiguration
    let targetLocationsByOriginalLine: [Int: Int]
    /// JSONL 坏行在输出文本中的 UTF-16 区间；PreviewWindowController 据此用
    /// `PeekyTheme.invalidLine*`（跟随系统外观）给坏行正文上红。非 JSONL 为空。
    let invalidRecordRanges: [NSRange]

    static let plain = PreviewDisplayMetadata(
        gutter: .hidden,
        textOverlay: .hidden,
        targetLocationsByOriginalLine: [:],
        invalidRecordRanges: []
    )

    static func lineNumbers(for text: String) -> PreviewDisplayMetadata {
        PreviewDisplayMetadata(
            gutter: .lineNumbers(for: text),
            textOverlay: PreviewTextOverlayConfiguration(
                recordSeparatorLocations: []
            ),
            targetLocationsByOriginalLine: [:],
            invalidRecordRanges: []
        )
    }

    static func jsonLines(text: String, records: [JSONLineRecord]) -> PreviewDisplayMetadata {
        let markers = records.map {
            PreviewGutterMarker(
                characterLocation: $0.range.location,
                label: String($0.originalLine),
                isWarning: $0.isInvalid
            )
        }

        let targets = Dictionary(uniqueKeysWithValues: records.map { ($0.originalLine, $0.range.location) })

        return PreviewDisplayMetadata(
            gutter: .markers(markers),
            textOverlay: PreviewTextOverlayConfiguration(
                recordSeparatorLocations: records.dropFirst().map { $0.range.location }
            ),
            targetLocationsByOriginalLine: targets,
            invalidRecordRanges: records.filter { $0.isInvalid }.map { $0.range }
        )
    }

    static func lineStartLocations(in text: String) -> [Int] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [0] }

        var starts = [0]
        var location = 0

        while location < nsText.length {
            let range = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: location, length: nsText.length - location)
            )
            guard range.location != NSNotFound else { break }

            let next = range.location + range.length
            if next < nsText.length {
                starts.append(next)
            }
            location = next
        }

        return starts
    }
}
