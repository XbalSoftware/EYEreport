//
//  PatientImport.swift
//  EYEreport
//
//  Where parsed IRIS values LAND in a report. Two halves:
//
//  • Identity → the patient block's typed properties. A direct mapping;
//    nothing to guess.
//  • Exam findings → findings-grid ROWS, which carry no type — only a
//    free-text label. So a row is matched by keyword ("refract", a bare "VA"
//    token, "IOP", "kerat"), which survives the user renaming "VA (cc)" to
//    "VA cc" and works across templates with different labels. A value with
//    no matching row is reported, not silently dropped — the review sheet
//    shows it before anything is applied.
//
//  Affordances matter here: the renderer PREPENDS a row's prefix, so "20/15"
//  must be stored as "15" in a row whose prefix is already "20/" (otherwise
//  it prints "20/20/15"). `storedValue` is the single place that reconciles
//  a parsed value with its row's affordance.
//
//  Pure logic, no UI — deliberately testable on its own.
//

import Foundation

// MARK: - The findings an IRIS PDF can supply

nonisolated enum ExamFinding: String, CaseIterable, Identifiable, Hashable {
    /// SYNTHESIZED: a refraction and its acuity in one cell, for the
    /// "Refraction / VA" row a post-cataract follow-up wants. Declared FIRST
    /// so it claims a fused row before the plain refraction can take it —
    /// `allCases` order is match order.
    case refractionWithVisualAcuity
    case refraction
    /// With correction — from the subjective refraction.
    case visualAcuity
    /// Without correction — from its own exam section.
    case uncorrectedVisualAcuity
    case keratometry
    case intraocularPressure

    var id: String { rawValue }

    /// Review-sheet wording (the eye is appended: "Refraction OD"). cc/sc
    /// rather than spelled out: it matches how the rows are labelled.
    var label: String {
        switch self {
        case .refractionWithVisualAcuity: return "Refraction / VA"
        case .refraction:                 return "Refraction"
        case .visualAcuity:               return "VA (cc)"
        case .uncorrectedVisualAcuity:    return "VA (sc)"
        case .keratometry:                return "Keratometry"
        case .intraocularPressure:        return "IOP"
        }
    }

    /// Where the value lives on `PatientDemographics` — nil for a synthesized
    /// finding, which is composed on read from the values it combines.
    var storage: (od: WritableKeyPath<PatientDemographics, String?>,
                  os: WritableKeyPath<PatientDemographics, String?>)? {
        switch self {
        case .refractionWithVisualAcuity: return nil
        case .refraction:                 return (\.refractionOD, \.refractionOS)
        case .visualAcuity:               return (\.visualAcuityOD, \.visualAcuityOS)
        case .uncorrectedVisualAcuity:    return (\.uncorrectedVisualAcuityOD, \.uncorrectedVisualAcuityOS)
        case .keratometry:                return (\.keratometryOD, \.keratometryOS)
        case .intraocularPressure:        return (\.intraocularPressureOD, \.intraocularPressureOS)
        }
    }

    /// A synthesized finding is a convenience, not a measurement: it is never
    /// reported as "unmatched", because having no fused row is the normal case.
    var isSynthesized: Bool { storage == nil }

    /// The findings this one delivers when it lands — so they aren't reported
    /// missing just because the report fuses them into a single row.
    var components: [ExamFinding] {
        self == .refractionWithVisualAcuity ? [.refraction, .visualAcuity] : []
    }

    // MARK: - Row matching

    /// How well a findings row's label suits this finding: nil = not at all,
    /// 1 = plausible, 2 = explicit. The caller takes the best available row,
    /// so an explicitly-marked row wins over a generic one — which is what
    /// separates "VA (cc)" from "VA (sc)" when a report carries both.
    func matchQuality(rowLabel label: String) -> Int? {
        let l = Labelling(label)
        switch self {
        case .refractionWithVisualAcuity:
            // Both halves must be named, or it isn't a fused row.
            return (l.isRefraction && l.isVisualAcuity) ? 2 : nil

        case .refraction:
            guard l.isRefraction else { return nil }
            // A fused row is a weaker fit than a refraction-only row; it only
            // wins when nothing else is free (e.g. no VA was parsed, so the
            // fused finding never ran).
            return l.isVisualAcuity ? 1 : 2

        case .visualAcuity:
            guard l.isVisualAcuity, !l.isRefraction else { return nil }
            if l.isUncorrected { return nil }        // "VA (sc)" is not this
            return l.isCorrected ? 2 : 1             // bare "VA" defaults to cc

        case .uncorrectedVisualAcuity:
            guard l.isVisualAcuity, !l.isRefraction else { return nil }
            // Requires an explicit sc marker: a bare "VA" row means corrected
            // by convention, and guessing here would print the wrong acuity.
            return l.isUncorrected ? 2 : nil

        case .keratometry:
            return l.isKeratometry ? 2 : nil

        case .intraocularPressure:
            return l.isPressure ? 2 : nil
        }
    }

    /// What a row label says about itself. Phrases match anywhere in the
    /// label; abbreviations must be WHOLE words so they can't hit inside
    /// another one. "visual" alone is deliberately not a VA phrase — the
    /// standard "Visual field (FDT)" row would swallow visual acuity.
    private struct Labelling {
        let isRefraction: Bool
        let isVisualAcuity: Bool
        let isKeratometry: Bool
        let isPressure: Bool
        let isUncorrected: Bool
        let isCorrected: Bool

        init(_ label: String) {
            let lowered = label.lowercased()
            let tokens = Set(lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            func has(_ phrases: [String]) -> Bool { phrases.contains { lowered.contains($0) } }
            func word(_ words: [String]) -> Bool { words.contains { tokens.contains($0) } }

            isRefraction = has(["refract"]) || word(["rx"])
            isVisualAcuity = has(["acuity"]) || word(["va", "bcva", "vas"])
            isKeratometry = has(["kerat"]) || word(["k", "ks"])
            // "tonomet" is the stem shared by tonometry and tonometER (the
            // "tonometr" spelling misses the latter); "nct" (non-contact
            // tonometry) only ever labels a pressure row.
            isPressure = has(["pressure", "tension", "tonomet"]) || word(["iop", "iops", "nct"])

            // Order matters: "uncorrected" contains "corrected", and
            // "unaided" contains "aided", so uncorrected is decided first and
            // excluded from corrected.
            isUncorrected = has(["uncorrect", "unaided", "without correction", "no correction"])
                || word(["sc"])
            isCorrected = !isUncorrected
                && (has(["corrected", "with correction"]) || word(["cc", "bcva"]))
        }
    }
}

// MARK: - Outcome

/// What an import did (or, dry-run, would do). Drives the review sheet's
/// "these have nowhere to go" note.
nonisolated struct PatientImportOutcome: Equatable {
    /// The report has a patient block to receive identity values.
    var hasPatientBlock: Bool = false
    /// Findings that found a row.
    var applied: [ExamFinding] = []
    /// Findings that were parsed but have no matching row in this report.
    var unmatched: [ExamFinding] = []
}

// MARK: - Applying

/// Deliberately NOT `nonisolated`: it works on `ReportDocument`, which (like
/// the rest of the model graph) is main-actor isolated under the target's
/// default-isolation setting, and every caller is UI.
enum PatientImport {

    /// Dry run: what applying these details to this document would do.
    /// Used by the review sheet so the clinician sees, BEFORE applying, that
    /// (say) keratometry has no row waiting for it.
    static func outcome(applying details: PatientDemographics,
                        to document: ReportDocument) -> PatientImportOutcome {
        var copy = document
        return copy.applyPatientDetails(details)
    }

    /// Reconciles a parsed value with its destination row's affordance: the
    /// renderer draws prefix + value + suffix, so a value that already
    /// carries them would print them twice. "20/15" into a "20/"-prefixed row
    /// becomes "15"; "19 mmHg" into an "mmHg"-suffixed row becomes "19".
    /// Spanning rows ignore affordances at render, so they get the raw value.
    static func storedValue(_ parsed: String, for affordance: FieldAffordance?) -> String {
        var value = parsed.trimmingCharacters(in: .whitespaces)

        if let prefix = affordance?.prefix, !prefix.isEmpty {
            // Compare with spaces removed so "20 / 15" also sheds its "20/".
            let compactPrefix = prefix.replacingOccurrences(of: " ", with: "")
            let compactValue = value.replacingOccurrences(of: " ", with: "")
            if compactValue.lowercased().hasPrefix(compactPrefix.lowercased()) {
                value = String(compactValue.dropFirst(compactPrefix.count))
            }
        }

        if let suffix = affordance?.suffix, !suffix.isEmpty,
           value.lowercased().hasSuffix(suffix.lowercased()) {
            value = String(value.dropLast(suffix.count))
        }

        return value.trimmingCharacters(in: .whitespaces)
    }
}

extension ReportDocument {

    /// Writes confirmed patient details into this document: identity into the
    /// first patient block, exam values into the first matching findings row
    /// (searched across every findings block, in document order). Only values
    /// the import actually carries are written — everything else, including
    /// each row's include toggle, label, and affordance, is left alone.
    @discardableResult
    mutating func applyPatientDetails(_ details: PatientDemographics) -> PatientImportOutcome {
        var outcome = PatientImportOutcome()

        // --- Identity → the first patient block -------------------------
        if let index = blocks.firstIndex(where: {
            if case .patient = $0.content { return true }
            return false
        }), case .patient(var patient) = blocks[index].content {
            outcome.hasPatientBlock = true
            assign(details.lastName, to: &patient.lastName)
            assign(details.firstName, to: &patient.firstName)
            assign(details.ahc, to: &patient.ahc)
            assign(details.phone, to: &patient.phone)
            assign(details.address, to: &patient.address)
            if let dob = details.dob { patient.dob = dob }
            blocks[index] = Block(id: blocks[index].id, .patient(patient))
        }

        // --- Exam findings → matching rows ------------------------------
        // Each finding claims the first unclaimed row that matches it, so two
        // findings can never land in the same row.
        var claimed: Set<UUID> = []
        for finding in ExamFinding.allCases {
            guard let values = details.values(for: finding) else { continue }
            guard let target = bestMatchingRow(for: finding, excluding: claimed) else {
                // A missing fused row is normal, not something to report.
                if !finding.isSynthesized { outcome.unmatched.append(finding) }
                continue
            }
            claimed.insert(target.rowID)
            write(values, for: finding, at: target)
            outcome.applied.append(finding)
        }

        // A fused row already carries its components — don't then report them
        // as having nowhere to go. (Synthesized findings sort first, so
        // anything fused is already in `applied` by now.)
        let deliveredByFusedRow = Set(outcome.applied.flatMap(\.components))
        outcome.unmatched.removeAll { deliveredByFusedRow.contains($0) }

        return outcome
    }

    // MARK: - Row location

    private struct RowLocation {
        let blockIndex: Int
        let rowIndex: Int
        let rowID: UUID
    }

    /// The best unclaimed row for a finding across every findings block: the
    /// highest match quality wins, ties go to the first in document order. So
    /// an explicit "VA (cc)" beats a bare "VA" wherever each sits.
    private func bestMatchingRow(for finding: ExamFinding,
                                 excluding claimed: Set<UUID>) -> RowLocation? {
        var best: (location: RowLocation, quality: Int)?
        for (blockIndex, block) in blocks.enumerated() {
            guard case .findings(let content) = block.content else { continue }
            for (rowIndex, row) in content.rows.enumerated() where !claimed.contains(row.id) {
                guard let quality = finding.matchQuality(rowLabel: row.label) else { continue }
                guard quality > (best?.quality ?? 0) else { continue }   // first of equals wins
                best = (RowLocation(blockIndex: blockIndex, rowIndex: rowIndex, rowID: row.id), quality)
            }
        }
        return best?.location
    }

    private mutating func write(_ values: (od: String?, os: String?),
                                for finding: ExamFinding,
                                at location: RowLocation) {
        guard case .findings(var content) = blocks[location.blockIndex].content,
              content.rows.indices.contains(location.rowIndex) else { return }

        var row = content.rows[location.rowIndex]
        switch row.value {
        case .paired(let currentOD, let currentOS):
            let od = values.od.map { PatientImport.storedValue($0, for: row.affordance) } ?? currentOD
            let os = values.os.map { PatientImport.storedValue($0, for: row.affordance) } ?? currentOS
            row.value = .paired(od: od, os: os)
        case .spanning(let current):
            // Spanning cells are drawn WITHOUT the affordance, so the raw
            // parsed values go in, labelled by eye.
            let parts = [values.od.map { "OD \($0)" }, values.os.map { "OS \($0)" }].compactMap { $0 }
            row.value = .spanning(parts.isEmpty ? current : parts.joined(separator: ", "))
        }
        content.rows[location.rowIndex] = row
        blocks[location.blockIndex] = Block(id: blocks[location.blockIndex].id, .findings(content))
    }

    /// Overwrites only when the import actually carries a value — a blank
    /// import never wipes something already typed.
    private func assign(_ parsed: String?, to target: inout String) {
        guard let parsed else { return }
        let trimmed = parsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        target = trimmed
    }
}
