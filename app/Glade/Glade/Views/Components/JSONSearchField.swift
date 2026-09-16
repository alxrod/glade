import SwiftUI

/// Draft keystrokes stay inside this small view; only Return changes the query.
struct JSONSearchField: View {
    let placeholder: LocalizedStringKey
    let accessibilityName: LocalizedStringKey
    let clearLabel: LocalizedStringKey
    @Binding var submittedText: String
    var isSearching = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .accessibilityLabel(Text(accessibilityName))
                .help("Press Return to search")
                .onSubmit { submittedText = draft }
                .onExitCommand { clear() }
            if isSearching {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Searching")
            } else if draft != submittedText {
                Image(systemName: "return")
                    .foregroundStyle(.secondary)
                    .help("Press Return to search")
                    .accessibilityLabel("Press Return to search")
            }
            if !draft.isEmpty || !submittedText.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(clearLabel))
            }
        }
        .onAppear { draft = submittedText }
        .onChange(of: submittedText) { _, text in draft = text }
    }

    private func clear() {
        draft = ""
        submittedText = ""
    }
}
