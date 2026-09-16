import SwiftUI

struct JumpToLineView: View {
    @Bindable var viewModel: GladeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var inputText: String = ""
    @State private var showError: Bool = false
    @FocusState private var isFocused: Bool

    private var lineCount: Int { viewModel.lineCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jump to Line")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Line number (1–\(lineCount))", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .frame(width: 240)
                    .onChange(of: inputText) { _, _ in
                        showError = false
                    }

                if showError {
                    Text("Enter a number between 1 and \(lineCount)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Go") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
        .onAppear { isFocused = true }
    }

    private func commit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard let number = Int(trimmed), number >= 1, number <= lineCount else {
            showError = true
            return
        }
        viewModel.jumpToLine(number)
        dismiss()
    }
}
