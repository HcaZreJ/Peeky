import Foundation

package struct PreviewGutterMarker {
    package let characterLocation: Int
    package let label: String
    package let isWarning: Bool

    package init(characterLocation: Int, label: String, isWarning: Bool) {
        self.characterLocation = characterLocation
        self.label = label
        self.isWarning = isWarning
    }
}

package enum PreviewGutterMode {
    case hidden
    case lineNumbers(lineStartLocations: [Int])
    case markers([PreviewGutterMarker])
}

package struct PreviewGutterConfiguration {
    package let mode: PreviewGutterMode
    package let width: CGFloat

    package var isVisible: Bool {
        switch mode {
        case .hidden:
            false
        case .lineNumbers, .markers:
            true
        }
    }

    package static let hidden = PreviewGutterConfiguration(mode: .hidden, width: 0)

    package static func lineNumbers(for text: String) -> PreviewGutterConfiguration {
        let starts = PreviewDisplayMetadata.lineStartLocations(in: text)
        return PreviewGutterConfiguration(
            mode: .lineNumbers(lineStartLocations: starts),
            width: gutterWidth(maxLabelLength: max(2, String(max(starts.count, 1)).count))
        )
    }

    package static func markers(_ markers: [PreviewGutterMarker]) -> PreviewGutterConfiguration {
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

package struct PreviewTextOverlayConfiguration {
    package let recordSeparatorLocations: [Int]

    package init(recordSeparatorLocations: [Int]) {
        self.recordSeparatorLocations = recordSeparatorLocations
    }

    package static let hidden = PreviewTextOverlayConfiguration(
        recordSeparatorLocations: []
    )
}

package struct PreviewDisplayMetadata {
    package let gutter: PreviewGutterConfiguration
    package let textOverlay: PreviewTextOverlayConfiguration
    package let targetLocationsByOriginalLine: [Int: Int]
    /// JSONL 坏行在输出文本中的 UTF-16 区间；PreviewWindowController 据此用
    /// `PeekyTheme.invalidLine*`（跟随系统外观）给坏行正文上红。非 JSONL 为空。
    package let invalidRecordRanges: [NSRange]

    package static let plain = PreviewDisplayMetadata(
        gutter: .hidden,
        textOverlay: .hidden,
        targetLocationsByOriginalLine: [:],
        invalidRecordRanges: []
    )

    package static func lineNumbers(for text: String) -> PreviewDisplayMetadata {
        PreviewDisplayMetadata(
            gutter: .lineNumbers(for: text),
            textOverlay: PreviewTextOverlayConfiguration(
                recordSeparatorLocations: []
            ),
            targetLocationsByOriginalLine: [:],
            invalidRecordRanges: []
        )
    }

    package static func jsonLines(text: String, records: [JSONLineRecord]) -> PreviewDisplayMetadata {
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

    package static func lineStartLocations(in text: String) -> [Int] {
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
