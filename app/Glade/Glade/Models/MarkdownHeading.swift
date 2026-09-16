import Foundation

struct MarkdownHeading: Identifiable {
    let id = UUID()
    let level: Int
    let title: String
    let lineIndex: Int
    var children: [MarkdownHeading]

    var anchorID: String {
        "heading-\(lineIndex)"
    }
}
