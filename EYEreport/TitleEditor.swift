import SwiftUI

struct TitleEditor: View {
    @Binding var content: TitleContent
    var focus: BlockFocusChain? = nil

    var body: some View {
        SelectAllTextField(placeholder: "Title (e.g. OCULAR HEALTH AND VISION REPORT)", text: $content.text,
                           focusKey: focus.key(FocusFields.title),
                           focusBinding: focus.binding,
                           onTab: focus.tab(FocusFields.title),
                           spellCheck: true)
    }
}

#Preview {
    struct Demo: View {
        @State private var content = TitleContent(text: "OCULAR HEALTH AND VISION REPORT")
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                TitleEditor(content: $content)
                Text("Bound value: \(content.text)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
