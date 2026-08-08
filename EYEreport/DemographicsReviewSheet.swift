//
//  DemographicsReviewSheet.swift
//  EYEreport
//
//  Shows the patient details parsed from an imported PDF so the clinician can
//  verify (and correct) every value BEFORE it touches the report. This
//  confirmation step is deliberate and non-negotiable: the parser is tuned to
//  one EMR's layout, so a human check is what makes auto-fill safe for
//  patient data.
//
//  Only rows that were actually PARSED appear, and the row set is fixed when
//  the sheet is presented — so clearing a value while editing can't make its
//  row vanish mid-review. Values with no destination in this report (an exam
//  finding with no matching findings row) are called out here rather than
//  being silently dropped on apply.
//

import SwiftUI

struct DemographicsReviewSheet: View {
    @State private var draft: PatientDemographics
    /// The DOB month FIELD shows digits while typing and the ALL-CAPS
    /// abbreviation on blur — same convention as PatientEditor/DateEditor.
    @State private var monthDisplay: String
    @State private var focused: String?

    private let identityRows: [IdentityRow]
    private let examRows: [ExamFinding]
    private let outcome: PatientImportOutcome
    private let onApply: (PatientDemographics) -> Void
    private let onCancel: () -> Void

    init(demographics: PatientDemographics,
         outcome: PatientImportOutcome,
         onApply: @escaping (PatientDemographics) -> Void,
         onCancel: @escaping () -> Void) {
        _draft = State(initialValue: demographics)
        _monthDisplay = State(initialValue: MonthFormat.abbreviation(for: demographics.dob?.month) ?? "")
        identityRows = IdentityRow.allCases.filter { $0.isPresent(in: demographics) }
        // Synthesized findings (the fused Refraction / VA) are composed from
        // rows already listed here, so showing them would be a duplicate that
        // couldn't be edited independently anyway.
        examRows = ExamFinding.allCases.filter {
            !$0.isSynthesized && demographics.values(for: $0) != nil
        }
        self.outcome = outcome
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                if !identityRows.isEmpty {
                    Section {
                        ForEach(identityRows, id: \.self) { identityRow($0) }
                    } header: {
                        Text("Patient")
                    } footer: {
                        Text(identityFooter)
                    }
                }

                if !examRows.isEmpty {
                    Section {
                        ForEach(examRows) { examRow($0) }
                    } header: {
                        Text("Exam Findings")
                    } footer: {
                        if !outcome.unmatched.isEmpty {
                            Text(unmatchedFooter)
                        }
                    }
                }
            }
            .navigationTitle("Patient Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to Report") { onApply(draft) }
                }
            }
        }
    }

    // MARK: - Footers

    private var identityFooter: String {
        outcome.hasPatientBlock
            ? "Check these against the source before applying. They fill the patient block of this report only — nothing is stored separately, and the report itself is the only place they live."
            : "This report has no patient block, so these values have nowhere to go. Add a Patient block first (the ＋ menu), then import again."
    }

    private var unmatchedFooter: String {
        let names = outcome.unmatched.map(\.label).joined(separator: ", ")
        return "No findings row matches: \(names). Add a row with that name to this report (or its template) and import again — the other values still apply."
    }

    // MARK: - Rows

    @ViewBuilder
    private func identityRow(_ row: IdentityRow) -> some View {
        labeled(row.label) {
            switch row {
            case .dob:
                HStack(spacing: 6) {
                    field("DD", key: FocusKeys.dobDay, text: dayText).frame(width: 52)
                    field("MM", key: FocusKeys.dobMonth, text: monthText, onEndEditing: snapMonthDisplay)
                        .frame(width: 52)
                    field("YYYY", key: FocusKeys.dobYear, text: yearText).frame(width: 80)
                    Spacer(minLength: 0)
                }
            default:
                field(row.label, key: row.focusKey, text: text(row.keyPath))
            }
        }
    }

    @ViewBuilder
    private func examRow(_ finding: ExamFinding) -> some View {
        // Always non-nil here: synthesized findings are filtered out of
        // `examRows`, and they're the only ones without storage.
        if let storage = finding.storage {
            labeled(finding.label) {
                HStack(spacing: 8) {
                    eyeField("OD", key: "\(finding.rawValue).od", text: text(storage.od))
                    eyeField("OS", key: "\(finding.rawValue).os", text: text(storage.os))
                }
            }
        }
    }

    private func eyeField(_ eye: String, key: String, text: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(eye)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            field(eye, key: key, text: text)
        }
    }

    private func field(_ placeholder: String,
                       key: String,
                       text: Binding<String>,
                       onEndEditing: (() -> Void)? = nil) -> some View {
        SelectAllTextField(placeholder: placeholder,
                           text: text,
                           focusKey: key,
                           focusBinding: $focused,
                           onTab: { move(from: key, backward: $0) },
                           onEndEditing: onEndEditing)
            .frame(height: standardFieldHeight)
    }

    private func labeled(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fieldLabelStyle()
            control()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Focus chain (local to the sheet)

    private enum FocusKeys {
        static let dobDay = "dob.day"
        static let dobMonth = "dob.month"
        static let dobYear = "dob.year"
    }

    /// Tab order, derived from the visible rows in display order.
    private var orderedKeys: [String] {
        var keys: [String] = []
        for row in identityRows {
            if row == .dob {
                keys += [FocusKeys.dobDay, FocusKeys.dobMonth, FocusKeys.dobYear]
            } else {
                keys.append(row.focusKey)
            }
        }
        for finding in examRows {
            keys += ["\(finding.rawValue).od", "\(finding.rawValue).os"]
        }
        return keys
    }

    private func move(from key: String, backward: Bool) {
        let keys = orderedKeys
        guard let index = keys.firstIndex(of: key) else { return }
        let target = backward ? index - 1 : index + 1
        guard keys.indices.contains(target) else { return }   // swallow at the ends
        focused = keys[target]
    }

    // MARK: - Bindings

    /// Bridges an optional stored value to a plain-text field binding (empty
    /// text clears it back to nil, so a cleared row applies nothing).
    private func text(_ keyPath: WritableKeyPath<PatientDemographics, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var dayText: Binding<String> {
        Binding(
            get: { draft.dob?.day.map(String.init) ?? "" },
            set: { value in
                var comps = draft.dob ?? DateComponents()
                comps.day = Int(value)
                draft.dob = allNil(comps) ? nil : comps
            }
        )
    }

    private var monthText: Binding<String> {
        Binding(
            get: { monthDisplay },
            set: { value in
                monthDisplay = value
                var comps = draft.dob ?? DateComponents()
                comps.month = MonthFormat.parse(value)
                draft.dob = allNil(comps) ? nil : comps
            }
        )
    }

    private var yearText: Binding<String> {
        Binding(
            get: { draft.dob?.year.map(String.init) ?? "" },
            set: { value in
                var comps = draft.dob ?? DateComponents()
                comps.year = Int(value)
                draft.dob = allNil(comps) ? nil : comps
            }
        )
    }

    /// Blur: show "AUG" when a valid month is stored; unparseable text stays
    /// visible as typed (never reformat garbage).
    private func snapMonthDisplay() {
        if let abbreviation = MonthFormat.abbreviation(for: draft.dob?.month) {
            monthDisplay = abbreviation
        }
    }

    private func allNil(_ comps: DateComponents) -> Bool {
        comps.day == nil && comps.month == nil && comps.year == nil
    }

    // MARK: - Identity rows

    private enum IdentityRow: String, CaseIterable, Hashable {
        case lastName, firstName, dob, ahc, phone, address

        var label: String {
            switch self {
            case .lastName:  return "Last name"
            case .firstName: return "First name"
            case .dob:       return "Date of birth"
            case .ahc:       return "AHC"
            case .phone:     return "Phone"
            case .address:   return "Address"
            }
        }

        var focusKey: String { "identity.\(rawValue)" }

        /// The DOB row is driven by its own three fields, so it has no
        /// String keyPath; `identityRow` special-cases it before this is read.
        var keyPath: WritableKeyPath<PatientDemographics, String?> {
            switch self {
            case .lastName:  return \.lastName
            case .firstName: return \.firstName
            case .ahc:       return \.ahc
            case .phone:     return \.phone
            case .address:   return \.address
            case .dob:       return \.phone     // unreachable; see identityRow
            }
        }

        func isPresent(in demographics: PatientDemographics) -> Bool {
            self == .dob ? demographics.dob != nil : demographics[keyPath: keyPath] != nil
        }
    }
}

// MARK: - Preview

#Preview {
    DemographicsReviewSheet(
        demographics: PatientDemographics(
            lastName: "Sample", firstName: "Jane Q.",
            dob: DateComponents(year: 1975, month: 12, day: 25),
            ahc: "12345-6789",
            address: "55 Imaginary Ave NW, Testville, AB, T2T 2T2",
            refractionOD: "-2.00 -1.00 × 130°", refractionOS: "-2.25 -0.50 × 70°",
            visualAcuityOD: "20/15", visualAcuityOS: "20/15-1",
            keratometryOD: "39.25@163/40.25", keratometryOS: "39.25@017/39.75"
        ),
        outcome: PatientImportOutcome(hasPatientBlock: true,
                                      applied: [.refraction, .visualAcuity],
                                      unmatched: [.keratometry]),
        onApply: { _ in },
        onCancel: { }
    )
}
