import SwiftUI

struct RecipientEditor: View {
    @Binding var content: RecipientContent
    var focus: BlockFocusChain? = nil
    @EnvironmentObject private var providerStore: ProviderStore
    /// Index into `visibleSuggestions` steered by ↓/↑ from the NAME field;
    /// Return fills the highlighted provider. nil = nothing highlighted
    /// (Return falls through to normal behavior). Reset on every keystroke
    /// in the name field and on any fill.
    @State private var highlightedSuggestion: Int?

    private enum Kind: String, CaseIterable, Identifiable {
        case providerFax, freeform, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .providerFax: return "Provider + fax"
            case .freeform:    return "Freeform"
            case .none:        return "None"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                switch content {
                case .providerFax: return .providerFax
                case .freeform: return .freeform
                case .none: return .none
                }
            },
            set: { newKind in
                switch newKind {
                case .providerFax:
                    if case .providerFax = content { return }
                    content = .providerFax(name: "", fax: "")
                case .freeform:
                    if case .freeform = content { return }
                    content = .freeform("")
                case .none:
                    content = .none
                }
            }
        )
    }

    private var providerName: Binding<String> {
        Binding(
            get: {
                if case .providerFax(let n, _) = content { return n }
                return ""
            },
            set: { newValue in
                let existingFax: String
                if case .providerFax(_, let f) = content { existingFax = f } else { existingFax = "" }
                content = .providerFax(name: newValue, fax: existingFax)
                // Typing changes the suggestion list — stale highlight dies.
                highlightedSuggestion = nil
            }
        )
    }

    private var providerFax: Binding<String> {
        Binding(
            get: {
                if case .providerFax(_, let f) = content { return f }
                return ""
            },
            set: { newValue in
                let existingName: String
                if case .providerFax(let n, _) = content { existingName = n } else { existingName = "" }
                content = .providerFax(name: existingName, fax: newValue)
            }
        )
    }

    private func snapFaxFormat() {
        guard case .providerFax(let name, let fax) = content else { return }
        guard fax.count == 10, fax.allSatisfy(\.isNumber) else { return }
        let a = fax.prefix(3)
        let b = fax.dropFirst(3).prefix(3)
        let c = fax.dropFirst(6)
        content = .providerFax(name: name, fax: "(\(a)) \(b)-\(c)")
    }

    private var freeformText: Binding<String> {
        Binding(
            get: {
                if case .freeform(let s) = content { return s }
                return ""
            },
            set: { content = .freeform($0) }
        )
    }

    // MARK: - Provider directory (type-ahead + save)

    /// True while the NAME field holds document focus — the gate for showing
    /// suggestions. Without a chain (previews), suggestions show whenever the
    /// typed text matches.
    private var nameFieldFocused: Bool {
        guard let focus else { return true }
        return focus.binding.wrappedValue == focus.key(FocusFields.recipientName)
    }

    private var suggestions: [Provider] {
        guard case .providerFax(let name, let fax) = content else { return [] }
        // Exact current entry offers nothing to fill — drop it.
        return providerStore.suggestions(for: name)
            .filter { !($0.name == name && $0.fax == fax) }
    }

    /// The rows actually on screen — arrow-key navigation and rendering
    /// must index the SAME list.
    private var visibleSuggestions: [Provider] {
        Array(suggestions.prefix(4))
    }

    private func fill(_ provider: Provider) {
        content = .providerFax(name: provider.name, fax: provider.fax)
        highlightedSuggestion = nil
    }

    /// ↓/↑ from the name field. Consumes the key only while suggestions are
    /// showing; ↑ with nothing highlighted stays a caret move.
    private func moveHighlight(down: Bool) -> Bool {
        let list = visibleSuggestions
        guard nameFieldFocused, !list.isEmpty else { return false }
        switch (highlightedSuggestion, down) {
        case (nil, true):
            highlightedSuggestion = 0
        case (nil, false):
            return false
        case (let i?, true):
            highlightedSuggestion = min(i + 1, list.count - 1)
        case (let i?, false):
            highlightedSuggestion = max(i - 1, 0)
        }
        return true
    }

    /// Return from the name field: fill the highlighted suggestion, if any.
    private func acceptHighlight() -> Bool {
        guard let index = highlightedSuggestion,
              visibleSuggestions.indices.contains(index) else { return false }
        fill(visibleSuggestions[index])
        return true
    }

    @ViewBuilder
    private var suggestionRows: some View {
        if nameFieldFocused, !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleSuggestions.enumerated()), id: \.element.id) { index, provider in
                    Button {
                        fill(provider)
                    } label: {
                        HStack {
                            Text(provider.name)
                            Spacer()
                            Text(provider.fax)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(index == highlightedSuggestion
                                ? Color.accentColor.opacity(0.25) : Color.clear)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Add-or-update affordance for the provider directory: hidden when the
    /// name is empty or the exact entry is already saved; "update fax" when
    /// the name is saved with a different fax.
    @ViewBuilder
    private var saveProviderButton: some View {
        if case .providerFax(let name, let fax) = content {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if !trimmedName.isEmpty {
                if let existing = providerStore.provider(named: trimmedName) {
                    if existing.fax != fax {
                        Button {
                            providerStore.update(id: existing.id, name: trimmedName, fax: fax)
                        } label: {
                            Label("Update fax for “\(trimmedName)” in providers",
                                  systemImage: "person.badge.clock")
                                .font(.footnote)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        providerStore.add(Provider(name: trimmedName, fax: fax))
                    } label: {
                        Label("Add “\(trimmedName)” to providers",
                              systemImage: "person.badge.plus")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Recipient", selection: kind) {
                ForEach(Kind.allCases) { k in Text(k.label).tag(k) }
            }
            .pickerStyle(.segmented)

            switch content {
            case .providerFax:
                SelectAllTextField(placeholder: "Recipient name (e.g. Dr. Smith)", text: providerName,
                                   focusKey: focus.key(FocusFields.recipientName),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.recipientName),
                                   onArrowKey: { moveHighlight(down: $0) },
                                   onReturnKey: { acceptHighlight() })
                    .frame(height: standardFieldHeight)
                suggestionRows
                SelectAllTextField(placeholder: "Fax number", text: providerFax,
                                   focusKey: focus.key(FocusFields.recipientFax),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.recipientFax),
                                   onEndEditing: snapFaxFormat)
                    .frame(height: standardFieldHeight)
                saveProviderButton
            case .freeform:
                SelectAllTextField(placeholder: "Recipient (e.g. Alberta Motor Vehicle Registry)",
                                   text: freeformText,
                                   focusKey: focus.key(FocusFields.recipientFreeform),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.recipientFreeform))
                    .frame(height: standardFieldHeight)
            case .none:
                EmptyView()
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var content: RecipientContent =
            .providerFax(name: "Smith", fax: "(403) 555-0000")
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                RecipientEditor(content: $content)
                Text("Bound value: \(String(describing: content))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
        .environmentObject(ProviderStore())
}
