import Foundation

struct JSONLLine: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let rawJSON: String
    let parsed: JSONValue?
    let parseError: String?
    let preview: String

    init(lineNumber: Int, rawJSON: String) {
        self.lineNumber = lineNumber
        self.rawJSON = rawJSON

        let trimmed = rawJSON.trimmingCharacters(in: .whitespaces)
        self.preview = trimmed.count <= 80 ? trimmed : String(trimmed.prefix(80)) + "\u{2026}"

        // Parse the JSON
        let data = rawJSON.data(using: .utf8) ?? Data()
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            self.parsed = JSONValue.from(obj)
            self.parseError = nil
        } catch {
            self.parsed = nil
            self.parseError = error.localizedDescription
        }
    }
}
