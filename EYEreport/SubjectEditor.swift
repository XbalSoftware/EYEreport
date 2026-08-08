import SwiftUI

struct SubjectEditor: View {
    @Binding var content: SubjectContent
    var focus: BlockFocusChain? = nil

    var body: some View {
        // SelectAllTextField (the app-standard input) rather than a SwiftUI
        // TextField, so the subject participates in the tab chain.
        SelectAllTextField(placeholder: "Subject (e.g. Re: …)", text: $content.text,
                           focusKey: focus.key(FocusFields.subject),
                           focusBinding: focus.binding,
                           onTab: focus.tab(FocusFields.subject),
                           spellCheck: true)
            .frame(height: standardFieldHeight)
    }
}

#Preview {
    struct Demo: View {
        @State private var content = SubjectContent(text: "Re: Removal of Condition A")
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SubjectEditor(content: $content)
                Text("Bound value: \(content.text)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
