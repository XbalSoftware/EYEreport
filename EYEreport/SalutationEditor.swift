import SwiftUI

struct SalutationEditor: View {
    @Binding var content: SalutationContent
    var focus: BlockFocusChain? = nil
    /// The recipient block's doctor name (first provider+fax recipient in the
    /// document), threaded down from ReportEditorView. nil = no such
    /// recipient exists (or no chain, e.g. previews) — mirroring then leaves
    /// the stored name alone.
    var recipientName: String? = nil

    private enum Kind: String, CaseIterable, Identifiable {
        case dearDoctor, toWhom, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .dearDoctor: return "Dear …"
            case .toWhom:     return "To Whom It May Concern"
            case .custom:     return "Custom"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch content {
                case .dearDoctor: return .dearDoctor
                case .toWhomItMayConcern: return .toWhom
                case .custom: return .custom
                }
            },
            set: { newKind in
                switch newKind {
                case .dearDoctor:
                    if case .dearDoctor = content { return }
                    // Mirroring is the default; seed from the recipient at once.
                    content = .dearDoctor(name: recipientName ?? "", mirrorsRecipient: true)
                case .toWhom:
                    content = .toWhomItMayConcern
                case .custom:
                    if case .custom = content { return }
                    content = .custom("")
                }
            }
        )
    }

    private var doctorName: Binding<String> {
        Binding(
            get: {
                if case .dearDoctor(let n, _) = content { return n }
                return ""
            },
            set: { newValue in
                let mirrors: Bool
                if case .dearDoctor(_, let m) = content { mirrors = m } else { mirrors = true }
                content = .dearDoctor(name: newValue, mirrorsRecipient: mirrors)
            }
        )
    }

    private var mirrorsRecipient: Binding<Bool> {
        Binding(
            get: {
                if case .dearDoctor(_, let m) = content { return m }
                return false
            },
            set: { on in
                guard case .dearDoctor(let name, _) = content else { return }
                // Toggling ON adopts the recipient's name immediately;
                // toggling OFF keeps the current name for hand-editing.
                content = .dearDoctor(name: on ? (recipientName ?? name) : name,
                                      mirrorsRecipient: on)
            }
        )
    }

    private var customText: Binding<String> {
        Binding(
            get: {
                if case .custom(let s) = content { return s }
                return ""
            },
            set: { content = .custom($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Salutation", selection: kind) {
                ForEach(Kind.allCases) { k in Text(k.label).tag(k) }
            }
            .pickerStyle(.segmented)

            if case .dearDoctor(let name, let mirrors) = content {
                Toggle("Use recipient's name", isOn: mirrorsRecipient)
                    .toggleStyle(.switch)
                    .font(.subheadline)
                if mirrors {
                    // Grayed echo of the rendered line (ClosingEditor convention).
                    // The name carries its own title (mirrored from the
                    // recipient, e.g. "Dr. Simon Reid") — "Dear" is all the
                    // salutation adds.
                    Text(name.isEmpty ? "Dear," : "Dear \(name),")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    SelectAllTextField(placeholder: "Recipient name (e.g. Dr. Smith)", text: doctorName,
                                       focusKey: focus.key(FocusFields.salutationName),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.salutationName))
                        .frame(height: standardFieldHeight)
                }
            } else if case .custom = content {
                SelectAllTextField(placeholder: "Custom salutation", text: customText,
                                   focusKey: focus.key(FocusFields.salutationCustom),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.salutationCustom))
                    .frame(height: standardFieldHeight)
            }
        }
        .onAppear { syncMirroredName() }
        .onChange(of: recipientName) { syncMirroredName() }
    }

    /// While mirroring, keep the stored name equal to the recipient's — the
    /// stored copy is what the renderer prints and what a template saves, so
    /// nothing downstream needs to know about mirroring.
    private func syncMirroredName() {
        guard case .dearDoctor(let name, true) = content,
              let recipientName, recipientName != name else { return }
        content = .dearDoctor(name: recipientName, mirrorsRecipient: true)
    }
}

#Preview {
    struct Demo: View {
        @State private var content: SalutationContent =
            .dearDoctor(name: "Smith", mirrorsRecipient: false)
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SalutationEditor(content: $content, recipientName: "Jones")
                Text("Bound value: \(String(describing: content))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
