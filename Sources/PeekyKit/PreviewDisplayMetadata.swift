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
        max(44, CGFloat(maxLabelLength) * 8 + 24)
    }
}

struct PreviewRecordAnnotation {
    let characterLocation: Int
    let text: String
    let isWarning: Bool
}

struct PreviewTextOverlayConfiguration {
    let showsIndentGuides: Bool
    let recordSeparatorLocations: [Int]
    let recordAnnotations: [PreviewRecordAnnotation]

    static let hidden = PreviewTextOverlayConfiguration(
        showsIndentGuides: false,
        recordSeparatorLocations: [],
        recordAnnotations: []
    )
}

struct PreviewDisplayMetadata {
    let gutter: PreviewGutterConfiguration
    let textOverlay: PreviewTextOverlayConfiguration
    let targetLocationsByOriginalLine: [Int: Int]

    static let plain = PreviewDisplayMetadata(
        gutter: .hidden,
        textOverlay: .hidden,
        targetLocationsByOriginalLine: [:]
    )

    static func lineNumbers(for text: String, showsIndentGuides: Bool) -> PreviewDisplayMetadata {
        PreviewDisplayMetadata(
            gutter: .lineNumbers(for: text),
            textOverlay: PreviewTextOverlayConfiguration(
                showsIndentGuides: showsIndentGuides,
                recordSeparatorLocations: [],
                recordAnnotations: []
            ),
            targetLocationsByOriginalLine: [:]
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

        let annotations = records.map {
            PreviewRecordAnnotation(
                characterLocation: $0.range.location,
                text: $0.summary,
                isWarning: $0.isInvalid
            )
        }

        let targets = Dictionary(uniqueKeysWithValues: records.map { ($0.originalLine, $0.range.location) })

        return PreviewDisplayMetadata(
            gutter: .markers(markers),
            textOverlay: PreviewTextOverlayConfiguration(
                showsIndentGuides: true,
                recordSeparatorLocations: records.dropFirst().map { $0.range.location },
                recordAnnotations: annotations
            ),
            targetLocationsByOriginalLine: targets
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
