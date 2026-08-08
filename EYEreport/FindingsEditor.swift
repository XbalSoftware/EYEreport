import SwiftUI

struct FindingsEditor: View {
    @Binding var content: FindingsContent
    var focus: BlockFocusChain? = nil

    @State private var isEditingFields = false

    private let labelWidth: CGFloat = 170
    private let toggleWidth: CGFloat = 44
    private let columnWidth: CGFloat = 180
    private let columnSpacing: CGFloat = 12
    private let affordanceFieldWidth: CGFloat = 70
    private let gripWidth: CGFloat = 20

    /// Width available to a spanning row (both columns + the gap between them).
    private var spanningWidth: CGFloat {
        columnWidth * 2 + columnSpacing
    }

    /// True when the row has non-empty prefix or suffix text.
    private func hasAffordanceText(_ row: FindingRow) -> Bool {
        guard let a = row.affordance else { return false }
        return (a.prefix != nil) || (a.suffix != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Edit fields", isOn: $isEditingFields)
                .toggleStyle(.switch)

            if isEditingFields {
                SelectAllTextField(placeholder: "Findings header (optional)", text: headerText)
                    .frame(maxWidth: 320)
            } else if let header = content.header, !header.isEmpty {
                Text(header)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: columnSpacing) {
                    Text("")
                        .frame(width: gripWidth)
                    Text("")
                        .frame(width: toggleWidth, alignment: .center)
                    Text("")
                        .frame(width: labelWidth, alignment: .leading)
                        .padding(.leading, 8)
                    Text("OD")
                        .frame(width: columnWidth, alignment: .leading)
                    Text("OS")
                        .frame(width: columnWidth, alignment: .leading)
                }
                .fieldLabelStyle()
                Divider()
            }

            ForEach($content.rows) { $row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: columnSpacing) {
                        // Leading spacer — keeps grid alignment. Drag removed;
                        // row reorder is the up/down buttons in edit-fields mode.
                        Color.clear
                            .frame(width: gripWidth, height: 20)

                        Toggle("", isOn: includedBinding(row.id))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .frame(width: toggleWidth, alignment: .center)

                        if isEditingFields {
                            SelectAllTextField(placeholder: "Label", text: labelBinding(row.id))
                                .frame(width: labelWidth, alignment: .leading)
                                .padding(.leading, 8)
                        } else {
                            Text(row.label)
                                .frame(width: labelWidth, alignment: .leading)
                                .padding(.leading, 8)
                        }

                        switch row.value {
                        case .paired:
                            pairedValueCell(text: odText(row.id),
                                            row: $row,
                                            cellWidth: columnWidth,
                                            field: FocusFields.findingsCell(row.id, "od"))
                                .disabled(!row.included)
                            pairedValueCell(text: osText(row.id),
                                            row: $row,
                                            cellWidth: columnWidth,
                                            field: FocusFields.findingsCell(row.id, "os"))
                                .disabled(!row.included)
                        case .spanning:
                            spanningValueCell(text: spanningText(row.id),
                                              cellWidth: spanningWidth,
                                              field: FocusFields.findingsCell(row.id, "span"))
                                .disabled(!row.included)
                        }

                        if isEditingFields {
                            rowStructuralControls(row)
                        }
                    }

                    // Prefix / suffix editor — units rows only (affordance != nil),
                    // and only while editing fields.
                    if isEditingFields, case .paired = row.value, row.affordance != nil {
                        affordanceRow(rowID: row.id)
                    }
                }
                .foregroundStyle(row.included ? .primary : .secondary)
                .opacity(row.included ? 1 : 0.5)
            }

            if isEditingFields {
                HStack(spacing: columnSpacing) {
                    Button("+ Paired row") { addRow(kind: .paired) }
                    Button("+ Spanning row") { addRow(kind: .spanning) }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Row structural controls (duplicate / delete)

    @ViewBuilder
    private func rowStructuralControls(_ row: FindingRow) -> some View {
        HStack(spacing: 8) {
            Button {
                moveRow(row, up: true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirstRow(row))

            Button {
                moveRow(row, up: false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLastRow(row))

            Button {
                duplicateRow(row)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)

            Button {
                deleteRow(row)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    /// Moves a row one position up or down by swapping with its neighbour.
    private func moveRow(_ row: FindingRow, up: Bool) {
        guard let index = content.rows.firstIndex(where: { $0.id == row.id }) else { return }
        let target = up ? index - 1 : index + 1
        guard content.rows.indices.contains(target) else { return }
        withAnimation { content.rows.swapAt(index, target) }
    }

    private func isFirstRow(_ row: FindingRow) -> Bool {
        content.rows.first?.id == row.id
    }

    private func isLastRow(_ row: FindingRow) -> Bool {
        content.rows.last?.id == row.id
    }

    /// Inserts a copy of `row` immediately below its current position. The
    /// copy carries label, value kind, affordance, defaultValue, and
    /// carryForward, but its value is reset to defaultValue (blank) — no
    /// clinical values copy across.
    private func duplicateRow(_ row: FindingRow) {
        guard let index = content.rows.firstIndex(where: { $0.id == row.id }) else { return }
        var copy = FindingRow(label: row.label,
                               value: row.defaultValue,
                               defaultValue: row.defaultValue,
                               affordance: row.affordance,
                               carryForward: row.carryForward,
                               included: row.included)
        copy.resetToDefault()
        content.rows.insert(copy, at: index + 1)
    }

    private func deleteRow(_ row: FindingRow) {
        content.rows.removeAll { $0.id == row.id }
    }

    private enum NewRowKind {
        case paired, spanning
    }

    private func addRow(kind: NewRowKind) {
        let value: FindingValue = kind == .paired ? .paired(od: "", os: "") : .spanning("")
        let newRow = FindingRow(label: "",
                                 value: value,
                                 defaultValue: value,
                                 affordance: nil,
                                 included: true)
        content.rows.append(newRow)
    }

    // MARK: - Index-safe row bindings

    /// Look a row up by id (never by a stored index) so a control briefly
    /// updated after its row was removed reads a safe default instead of
    /// subscripting content.rows out of range. Prevents the last-row-delete crash.
    private func includedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { content.rows.first(where: { $0.id == id })?.included ?? false },
            set: { v in
                if let i = content.rows.firstIndex(where: { $0.id == id }) {
                    content.rows[i].included = v
                }
            }
        )
    }

    private func labelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { content.rows.first(where: { $0.id == id })?.label ?? "" },
            set: { v in
                if let i = content.rows.firstIndex(where: { $0.id == id }) {
                    content.rows[i].label = v
                }
            }
        )
    }

    // MARK: - Affordance bindings

    /// Convention: `affordance == nil` means the row is not a units row — no
    /// prefix/suffix controls are ever shown for it. `affordance != nil` means
    /// it IS a units row; prefix/suffix are then editable and independently
    /// clearable, but clearing one (or both) to empty does NOT collapse the
    /// affordance back to nil — the row keeps its controls.
    ///
    /// Maps `FieldAffordance.prefix` (String?) ↔ a non-optional String for the
    /// text field. Empty string writes back as nil.
    /// Maps `FindingsContent.header` (String?) ↔ a non-optional String.
    private var headerText: Binding<String> {
        Binding(
            get: { content.header ?? "" },
            set: { content.header = $0.isEmpty ? nil : $0 }
        )
    }

    private func prefixBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { content.rows.first(where: { $0.id == id })?.affordance?.prefix ?? "" },
            set: { newValue in
                if let i = content.rows.firstIndex(where: { $0.id == id }) {
                    content.rows[i].affordance?.prefix = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    /// Maps `FieldAffordance.suffix` (String?) ↔ a non-optional String.
    private func suffixBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { content.rows.first(where: { $0.id == id })?.affordance?.suffix ?? "" },
            set: { newValue in
                if let i = content.rows.firstIndex(where: { $0.id == id }) {
                    content.rows[i].affordance?.suffix = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    // MARK: - Affordance editor sub-row (paired rows only)

    /// A compact row showing editable prefix and suffix fields, indented to
    /// align under the value columns.
    @ViewBuilder
    private func affordanceRow(rowID: UUID) -> some View {
        HStack(spacing: columnSpacing) {
            Color.clear
                .frame(width: gripWidth, height: 1)
            Color.clear
                .frame(width: toggleWidth, height: 1)
            Color.clear
                .frame(width: labelWidth, height: 1)
                .padding(.leading, 8)

            HStack(spacing: 4) {
                Text("pre")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                SelectAllTextField(placeholder: "", text: prefixBinding(rowID))
                    .frame(width: affordanceFieldWidth)
            }

            HStack(spacing: 4) {
                Text("suf")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                SelectAllTextField(placeholder: "", text: suffixBinding(rowID))
                    .frame(width: affordanceFieldWidth)
            }
        }
    }

    // MARK: - Value cells
    //
    // Tab order comes from the DOCUMENT-wide chain (FocusOrder in
    // FocusChain.swift), not a private per-block chain — Tab walks out of the
    // block at either edge instead of trapping inside it. FocusOrder lists
    // every included row's value cell(s) in row order; keep it in step if the
    // cells here change.

    /// Value cell for a paired (OD or OS) column. Renders prefix/suffix text
    /// from the row's affordance when present. Uses single-line
    /// `SelectAllTextField` when an affordance provides framing; wraps via
    /// `SelectAllTextView` otherwise (free-text segments).
    @ViewBuilder
    private func pairedValueCell(text: Binding<String>,
                                 row: Binding<FindingRow>,
                                 cellWidth: CGFloat,
                                 field: String) -> some View {
        let aff = row.wrappedValue.affordance
        let wraps = !hasAffordanceText(row.wrappedValue)
        HStack(alignment: wraps ? .top : .firstTextBaseline, spacing: 2) {
            if let prefix = aff?.prefix {
                Text(prefix).fixedSize().lineLimit(1)
            }
            if wraps {
                // Multi-line: in the tab chain via the same focus contract.
                SelectAllTextView(text: text,
                    focusKey: focus.key(field), focusBinding: focus.binding,
                    onTab: focus.tab(field))
            } else {
                // Single-line: in the tab chain.
                SelectAllTextField(placeholder: "", text: text,
                    focusKey: focus.key(field), focusBinding: focus.binding,
                    onTab: focus.tab(field))
            }
            if let suffix = aff?.suffix {
                Text(suffix).fixedSize().lineLimit(1)
            }
        }
        .frame(width: cellWidth, alignment: .leading)
    }

    /// Value cell for a spanning row. Always wraps, never shows affordance
    /// framing (renderer ignores affordance on spanning rows), but is in the
    /// tab chain like any other value cell.
    @ViewBuilder
    private func spanningValueCell(text: Binding<String>,
                                   cellWidth: CGFloat,
                                   field: String) -> some View {
        SelectAllTextView(text: text,
            focusKey: focus.key(field), focusBinding: focus.binding,
            onTab: focus.tab(field))
            .frame(width: cellWidth, alignment: .leading)
    }

    private func odText(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let r = content.rows.first(where: { $0.id == id }),
                      case .paired(let od, _) = r.value else { return "" }
                return od
            },
            set: { newValue in
                guard let i = content.rows.firstIndex(where: { $0.id == id }),
                      case .paired(_, let os) = content.rows[i].value else { return }
                content.rows[i].value = .paired(od: newValue, os: os)
            }
        )
    }

    private func osText(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let r = content.rows.first(where: { $0.id == id }),
                      case .paired(_, let os) = r.value else { return "" }
                return os
            },
            set: { newValue in
                guard let i = content.rows.firstIndex(where: { $0.id == id }),
                      case .paired(let od, _) = content.rows[i].value else { return }
                content.rows[i].value = .paired(od: od, os: newValue)
            }
        )
    }

    private func spanningText(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let r = content.rows.first(where: { $0.id == id }),
                      case .spanning(let s) = r.value else { return "" }
                return s
            },
            set: { newValue in
                guard let i = content.rows.firstIndex(where: { $0.id == id }) else { return }
                content.rows[i].value = .spanning(newValue)
            }
        )
    }
}

#Preview {
    struct Demo: View {
        @State private var content = FindingsContent(
            header: "My findings today include:",
            rows: [
                FindingRow(label: "VA (cc)", value: .paired(od: "40", os: "30"),
                           defaultValue: .paired(od: "", os: ""),
                           affordance: FieldAffordance(prefix: "20/")),
                FindingRow(label: "IOP (NCT)", value: .paired(od: "14", os: "15"),
                           defaultValue: .paired(od: "", os: ""),
                           affordance: FieldAffordance(suffix: "mmHg")),
                FindingRow(label: "Anterior Segment",
                           value: .paired(od: "Unremarkable", os: "Unremarkable"),
                           defaultValue: .paired(od: "", os: "")),
                FindingRow(label: "Posterior Segment",
                           value: .paired(od: "C/D 0.3, healthy rim, macula flat", os: "C/D 0.35, healthy rim, macula flat, peripheral retina unremarkable"),
                           defaultValue: .paired(od: "", os: "")),
                FindingRow(label: "Pupils",
                           value: .spanning("Equal, Round, React to Light, no RAPD"),
                           defaultValue: .spanning("")),
                FindingRow(label: "Visual field (FDT)",
                           value: .paired(od: "full", os: "full"),
                           defaultValue: .paired(od: "", os: ""),
                           included: false),
            ]
        )
        var body: some View {
            ScrollView { FindingsEditor(content: $content).padding() }
        }
    }
    return Demo()
}
