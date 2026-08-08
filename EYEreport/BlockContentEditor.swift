import SwiftUI

struct BlockContentEditor: View {
    @Binding var content: BlockContent
    var focus: BlockFocusChain? = nil
    /// Document-level context for the salutation's mirror-recipient feature.
    var recipientName: String? = nil

    var body: some View {
        switch content {
        case .subject:
            SubjectEditor(content: Binding(
                get: {
                    if case .subject(let s) = content { return s }
                    return SubjectContent(text: "")
                },
                set: { content = .subject($0) }
            ), focus: focus)
        case .recipient:
            RecipientEditor(content: Binding(
                get: {
                    if case .recipient(let r) = content { return r }
                    return .none
                },
                set: { content = .recipient($0) }
            ), focus: focus)
        case .title:
            TitleEditor(content: Binding(
                get: {
                    if case .title(let t) = content { return t }
                    return TitleContent(text: "")
                },
                set: { content = .title($0) }
            ), focus: focus)
        case .date:
            DateEditor(content: Binding(
                get: {
                    if case .date(let d) = content { return d }
                    return DateContent(label: "", date: nil)
                },
                set: { content = .date($0) }
            ), focus: focus)
        case .patient:
            PatientEditor(content: Binding(
                get: {
                    if case .patient(let p) = content { return p }
                    return PatientContent()
                },
                set: { content = .patient($0) }
            ), focus: focus)
        case .salutation:
            SalutationEditor(content: Binding(
                get: {
                    if case .salutation(let s) = content { return s }
                    return .toWhomItMayConcern
                },
                set: { content = .salutation($0) }
            ), focus: focus, recipientName: recipientName)
        case .prose:
            ProseEditor(content: Binding(
                get: {
                    if case .prose(let p) = content { return p }
                    return ProseContent()
                },
                set: { content = .prose($0) }
            ), focus: focus)
        case .findings:
            FindingsEditor(content: Binding(
                get: {
                    if case .findings(let f) = content { return f }
                    return FindingsContent()
                },
                set: { content = .findings($0) }
            ), focus: focus)
        case .impressionsPlan:
            ImpressionsPlanEditor(content: Binding(
                get: {
                    if case .impressionsPlan(let ip) = content { return ip }
                    return ImpressionsPlanContent(sections: [])
                },
                set: { content = .impressionsPlan($0) }
            ), focus: focus)
        case .closing:
            ClosingEditor(content: Binding(
                get: {
                    if case .closing(let c) = content { return c }
                    return .sharingInCare
                },
                set: { content = .closing($0) }
            ), focus: focus)
        case .signature:
            SignatureEditor(content: Binding(
                get: {
                    if case .signature(let s) = content { return s }
                    return SignatureContent()
                },
                set: { content = .signature($0) }
            ), focus: focus)
        case .spacer:
            SpacerEditor(content: Binding(
                get: {
                    if case .spacer(let s) = content { return s }
                    return SpacerContent()
                },
                set: { content = .spacer($0) }
            ))
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var content: BlockContent =
            .subject(SubjectContent(text: "Re: Removal of Condition A"))
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                BlockContentEditor(content: $content)
                if case .subject(let s) = content {
                    Text("Bound value: \(s.text)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    return Demo()
}
