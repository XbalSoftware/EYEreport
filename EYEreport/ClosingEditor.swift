import SwiftUI

struct ClosingEditor: View {
    @Binding var content: ClosingContent
    var focus: BlockFocusChain? = nil

    private enum Kind: String, CaseIterable, Identifiable {
        case sharingInCare, contactOffice, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sharingInCare: return "Sharing in care"
            case .contactOffice: return "Contact office"
            case .custom:        return "Custom"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch content {
                case .sharingInCare: return .sharingInCare
                case .contactOffice: return .contactOffice
                case .custom:        return .custom
                }
            },
            set: { chosen in
                switch chosen {
                case .sharingInCare: content = .sharingInCare
                case .contactOffice: content = .contactOffice
                case .custom:
                    if case .custom = content { } else { content = .custom("") }
                }
            }
        )
    }

    private var customText: Binding<String> {
        Binding(
            get: { if case .custom(let s) = content { return s } else { return "" } },
            set: { content = .custom($0) }
        )
    }

    /// The exact sentence ReportRenderer.drawClosing will print for the current
    /// selection — kept in sync with those literal strings by hand, since the
    /// renderer doesn't expose a shared lookup.
    private var previewText: String {
        switch content {
        case .sharingInCare: return "Thank you for sharing in the care of this patient."
        case .contactOffice: return "Please contact my office if further information is required."
        case .custom(let s): return s
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Closing", selection: kind) {
                ForEach(Kind.allCases) { k in Text(k.label).tag(k) }
            }
            .pickerStyle(.segmented)

            if case .custom = content {
                SelectAllTextField(placeholder: "Custom closing text", text: customText,
                                   focusKey: focus.key(FocusFields.closingCustom),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.closingCustom))
                    .frame(height: standardFieldHeight)
            } else if !previewText.isEmpty {
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var content: ClosingContent = .sharingInCare
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                ClosingEditor(content: $content)
                Text("Bound value: \(String(describing: content))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
