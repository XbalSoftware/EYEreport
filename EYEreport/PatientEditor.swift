import SwiftUI

struct PatientEditor: View {
    @Binding var content: PatientContent
    var focus: BlockFocusChain? = nil

    @State private var isEditingFields = false

    /// What the DOB month FIELD shows (the model keeps the numeric month):
    /// digits while typing, snapped to the ALL-CAPS abbreviation ("AUG") on
    /// blur — same convention as DateEditor.
    @State private var monthDisplay: String

    init(content: Binding<PatientContent>, focus: BlockFocusChain? = nil) {
        self._content = content
        self.focus = focus
        self._monthDisplay = State(initialValue:
            MonthFormat.abbreviation(for: content.wrappedValue.dob?.month) ?? "")
    }

    /// `.reducedBox` ("Box — no labels") is RETIRED from the picker — the
    /// user judged it useless once it worked. The model case and renderer
    /// path stay (legacy JSON must decode); `normalizeRenderStyle` folds any
    /// legacy value into `.fullBox` so the picker and the print agree.
    private let styles: [(PatientRenderStyle, String)] = [
        (.fullBox, "Full box"),
        (.inlineLabels, "Inline labels")
    ]

    private let labelColumnWidth: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Edit fields", isOn: $isEditingFields)
                .toggleStyle(.switch)

            Picker("Layout", selection: $content.renderStyle) {
                ForEach(styles, id: \.0) { style, label in
                    Text(label).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            // Rows follow the model's field order; a field deleted from the
            // order simply isn't here. Rows bind to typed properties (not
            // array elements), so reorder/delete can't hit a stale index.
            ForEach(content.resolvedFieldOrder, id: \.self) { field in
                fieldRow(field)
            }

            if isEditingFields, !missingFields.isEmpty {
                Menu {
                    ForEach(missingFields, id: \.self) { field in
                        Button(defaultEditorLabel(field)) {
                            withAnimation {
                                content.fieldOrder = content.resolvedFieldOrder + [field]
                            }
                        }
                    }
                } label: {
                    Label("Add field", systemImage: "plus")
                }
            }
        }
        .onAppear(perform: normalizeRenderStyle)
        // The month FIELD is backed by @State, so a write to the model from
        // OUTSIDE this editor — a patient-detail import landing in an open
        // report — updates DD and YYYY (they read the model directly) but
        // would leave MM blank until the editor was rebuilt. DateEditor's
        // "Today" button hand-syncs for the same reason.
        .onChange(of: content.dob?.month) { _, _ in adoptExternalMonth() }
    }

    /// Re-reads the month from the model, but ONLY when the field's own text
    /// doesn't already mean that month — so this can't fire mid-typing and
    /// snap "8" to "AUG" before blur (or reformat text the user is still
    /// entering, including unparseable text, which must stay as typed).
    private func adoptExternalMonth() {
        guard MonthFormat.parse(monthDisplay) != content.dob?.month else { return }
        monthDisplay = MonthFormat.abbreviation(for: content.dob?.month) ?? ""
    }

    /// Folds the retired `.reducedBox` into `.fullBox` when a legacy
    /// template/draft still carries it, so the two-option picker always
    /// shows what will actually print.
    private func normalizeRenderStyle() {
        if content.renderStyle == .reducedBox {
            content.renderStyle = .fullBox
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func fieldRow(_ field: PatientField) -> some View {
        labeled(field) {
            switch field {
            case .name:
                HStack(spacing: 6) {
                    SelectAllTextField(placeholder: "Last name", text: $content.lastName,
                                       focusKey: focus.key(FocusFields.patientLastName),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.patientLastName))
                    SelectAllTextField(placeholder: "First name", text: $content.firstName,
                                       focusKey: focus.key(FocusFields.patientFirstName),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.patientFirstName))
                }
            case .dob:
                HStack(spacing: 6) {
                    SelectAllTextField(placeholder: "DD", text: dayText,
                                       focusKey: focus.key(FocusFields.patientDOBDay),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.patientDOBDay))
                        .frame(width: 52)
                    SelectAllTextField(placeholder: "MM", text: monthText,
                                       focusKey: focus.key(FocusFields.patientDOBMonth),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.patientDOBMonth),
                                       onEndEditing: snapMonthDisplay)
                        .frame(width: 52)
                    SelectAllTextField(placeholder: "YYYY", text: yearText,
                                       focusKey: focus.key(FocusFields.patientDOBYear),
                                       focusBinding: focus.binding,
                                       onTab: focus.tab(FocusFields.patientDOBYear))
                        .frame(width: 80)
                }
            case .ahc:
                SelectAllTextField(placeholder: displayLabel(.ahc), text: $content.ahc,
                                   focusKey: focus.key(FocusFields.patientAHC),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.patientAHC),
                                   onEndEditing: snapAHCFormat)
            case .phone:
                SelectAllTextField(placeholder: displayLabel(.phone), text: $content.phone,
                                   focusKey: focus.key(FocusFields.patientPhone),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.patientPhone),
                                   onEndEditing: snapPhoneFormat)
            case .address:
                SelectAllTextField(placeholder: displayLabel(.address), text: $content.address,
                                   focusKey: focus.key(FocusFields.patientAddress),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.patientAddress))
            }
        }
    }

    /// Row chrome: include toggle, label (read-only normally; a rename field
    /// while "Edit fields" is on), the value field(s), and — in edit-fields
    /// mode — up/down/delete structural controls (Findings convention).
    @ViewBuilder
    private func labeled<Content: View>(_ field: PatientField,
                                        @ViewBuilder value: () -> Content) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: includedBinding(field)) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            if isEditingFields {
                SelectAllTextField(placeholder: defaultEditorLabel(field),
                                   text: labelBinding(field))
                    .frame(width: labelColumnWidth, height: standardFieldHeight)
            } else {
                Text(displayLabel(field))
                    .font(.title2)
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: labelColumnWidth, alignment: .leading)
            }
            value()
                .opacity(includedBinding(field).wrappedValue ? 1.0 : 0.5)
            if isEditingFields {
                structuralControls(field)
            }
        }
    }

    // MARK: - Field structure (order / presence / labels)

    private func structuralControls(_ field: PatientField) -> some View {
        HStack(spacing: 8) {
            Button {
                move(field, up: true)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(content.resolvedFieldOrder.first == field)

            Button {
                move(field, up: false)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(content.resolvedFieldOrder.last == field)

            Button(role: .destructive) {
                withAnimation {
                    content.fieldOrder = content.resolvedFieldOrder.filter { $0 != field }
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func move(_ field: PatientField, up: Bool) {
        var order = content.resolvedFieldOrder
        guard let index = order.firstIndex(of: field) else { return }
        let target = up ? index - 1 : index + 1
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        withAnimation { content.fieldOrder = order }
    }

    /// Standard fields deleted from this block — offered back by "Add field".
    private var missingFields: [PatientField] {
        PatientField.allCases.filter { !content.resolvedFieldOrder.contains($0) }
    }

    /// Editor-side default row labels (print labels are the renderer's).
    private func defaultEditorLabel(_ field: PatientField) -> String {
        switch field {
        // "Patient" (not "Name") so the editor label matches the rendered
        // label exactly — the renderer's default for this field is "Patient:".
        case .name:    return "Patient"
        case .dob:     return "Date of birth"
        case .ahc:     return "AHC"
        case .phone:   return "Phone"
        case .address: return "Address"
        }
    }

    private func displayLabel(_ field: PatientField) -> String {
        content.customLabel(for: field) ?? defaultEditorLabel(field)
    }

    /// Custom label ↔ text field; empty clears back to the default
    /// (empty-string ↔ nil convention lives in the binding).
    private func labelBinding(_ field: PatientField) -> Binding<String> {
        Binding(
            get: { content.fieldLabels?[field.rawValue] ?? "" },
            set: { newValue in
                var labels = content.fieldLabels ?? [:]
                if newValue.isEmpty {
                    labels.removeValue(forKey: field.rawValue)
                } else {
                    labels[field.rawValue] = newValue
                }
                content.fieldLabels = labels.isEmpty ? nil : labels
            }
        )
    }

    private func includedBinding(_ field: PatientField) -> Binding<Bool> {
        Binding(
            get: { content.includedFields.contains(field) },
            set: { on in
                if on { content.includedFields.insert(field) }
                else { content.includedFields.remove(field) }
            }
        )
    }

    // MARK: - DOB bindings

    private var dayText: Binding<String> {
        Binding(
            get: { content.dob?.day.map(String.init) ?? "" },
            set: { v in
                var comps = content.dob ?? DateComponents()
                comps.day = Int(v)
                content.dob = allNil(comps) ? nil : comps
            }
        )
    }

    private var monthText: Binding<String> {
        Binding(
            get: { monthDisplay },
            set: { v in
                monthDisplay = v
                var comps = content.dob ?? DateComponents()
                comps.month = MonthFormat.parse(v)
                content.dob = allNil(comps) ? nil : comps
            }
        )
    }

    /// Blur: show "AUG" when a valid month is stored; unparseable text stays
    /// visible as typed (never reformat garbage).
    private func snapMonthDisplay() {
        if let abbrev = MonthFormat.abbreviation(for: content.dob?.month) {
            monthDisplay = abbrev
        }
    }

    private var yearText: Binding<String> {
        Binding(
            get: { content.dob?.year.map(String.init) ?? "" },
            set: { v in
                var comps = content.dob ?? DateComponents()
                comps.year = Int(v)
                content.dob = allNil(comps) ? nil : comps
            }
        )
    }

    private func snapPhoneFormat() {
        guard content.phone.count == 10, content.phone.allSatisfy(\.isNumber) else { return }
        let a = content.phone.prefix(3)
        let b = content.phone.dropFirst(3).prefix(3)
        let c = content.phone.dropFirst(6)
        content.phone = "(\(a)) \(b)-\(c)"
    }

    private func snapAHCFormat() {
        guard content.ahc.count == 9, content.ahc.allSatisfy(\.isNumber) else { return }
        let a = content.ahc.prefix(5)
        let b = content.ahc.dropFirst(5)
        content.ahc = "\(a)-\(b)"
    }

    private func allNil(_ comps: DateComponents) -> Bool {
        comps.day == nil && comps.month == nil && comps.year == nil
    }

}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var content = PatientContent(
            lastName: "Doe", firstName: "Jane",
            dob: DateComponents(year: 1985, month: 6, day: 7),
            ahc: "", phone: "", address: ""
        )
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                PatientEditor(content: $content)
                Text("Stored DOB: \(content.dob.map(String.init(describing:)) ?? "nil")")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Field order: \(content.resolvedFieldOrder.map(\.rawValue).joined(separator: ", "))")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Included fields: \(content.includedFields.map(\.rawValue).sorted().joined(separator: ", "))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
