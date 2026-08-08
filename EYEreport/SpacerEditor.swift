import SwiftUI

/// Editor for a blank spacer block: a stepper choosing how many blank body
/// lines of vertical space it renders. No text, so it isn't in the tab chain
/// or the deletion-warning fingerprint.
struct SpacerEditor: View {
    @Binding var content: SpacerContent

    private let range = 1...20

    var body: some View {
        HStack(spacing: 12) {
            Stepper(value: $content.lines, in: range) {
                Text(content.lines == 1 ? "1 blank line" : "\(content.lines) blank lines")
                    .font(.title2)
                    .foregroundStyle(.primary.opacity(0.75))
            }
            .fixedSize()
            Spacer()
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var content = SpacerContent(lines: 2)
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SpacerEditor(content: $content)
                Text("Lines: \(content.lines)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
