//
//  PatientDemographics.swift
//  EYEreport
//
//  Patient details parsed from an IRIS EMR PDF — identity plus the exam
//  findings (refraction, VA, keratometry, IOP) a referral usually quotes.
//
//  This is PHI, and it is deliberately transient: the parsed struct lives in
//  memory only (see PatientImportInbox), is shown to the clinician for
//  confirmation (DemographicsReviewSheet), and reaches disk only once it has
//  been applied INTO the working report — i.e. through the encrypted draft,
//  exactly like hand-typed data. It is never persisted on its own.
//
//  Ported from the same-named type in Form Filler, adapted to EYEreport's
//  model: the name arrives split (the renderer upper-cases the surname
//  itself) and the birth date arrives as DateComponents (PatientContent.dob),
//  so no string date formatting happens here.
//

import Foundation

nonisolated struct PatientDemographics: Equatable {

    // MARK: Identity — maps onto PatientContent

    /// Surname in its natural case; `ReportRenderer` upper-cases at print.
    var lastName: String?
    /// Given name(s), middle names included.
    var firstName: String?
    /// year/month/day only, matching `PatientContent.dob`. nil when absent or
    /// impossible (e.g. a garbled "2020-13-45" — dropped rather than guessed).
    var dob: DateComponents?
    /// Alberta PHN, reformatted "#####-####" to match the editor's own
    /// on-blur formatting.
    var ahc: String?
    /// Never present in IRIS PDFs — kept so the review sheet and the mapping
    /// have somewhere to put a hand-typed number.
    var phone: String?
    /// Address lines, comma-joined; the renderer wraps it in its spanning row.
    var address: String?

    // MARK: Exam findings — map onto findings rows (OD = right, OS = left)

    var refractionOD: String?
    var refractionOS: String?
    /// VA measured WITH correction — bundled into the subjective refraction
    /// line, so it always accompanies a refraction.
    var visualAcuityOD: String?
    var visualAcuityOS: String?
    /// VA measured WITHOUT correction, from its own exam section. Often
    /// absent — plenty of exams never record it.
    var uncorrectedVisualAcuityOD: String?
    var uncorrectedVisualAcuityOS: String?
    var keratometryOD: String?
    var keratometryOS: String?
    var intraocularPressureOD: String?
    var intraocularPressureOS: String?

    // MARK: Queries

    var isEmpty: Bool { !hasIdentity && !hasExamFindings }

    var hasIdentity: Bool {
        lastName != nil || firstName != nil || dob != nil
            || ahc != nil || phone != nil || address != nil
    }

    var hasExamFindings: Bool {
        ExamFinding.allCases.contains { finding in
            guard let storage = finding.storage else { return false }
            return self[keyPath: storage.od] != nil || self[keyPath: storage.os] != nil
        }
    }

    /// The OD/OS pair for a finding, or nil when neither eye has one.
    /// A SYNTHESIZED finding has no storage of its own and is composed here
    /// from the values it combines — computed on read, so a correction made
    /// in the review sheet flows into it instead of leaving a stale copy.
    func values(for finding: ExamFinding) -> (od: String?, os: String?)? {
        let pair: (od: String?, os: String?)
        switch finding {
        case .refractionWithVisualAcuity:
            pair = (fused(refractionOD, visualAcuityOD), fused(refractionOS, visualAcuityOS))
        default:
            guard let storage = finding.storage else { return nil }
            pair = (self[keyPath: storage.od], self[keyPath: storage.os])
        }
        guard pair.od != nil || pair.os != nil else { return nil }
        return pair
    }

    /// "-1.00 -0.25 × 100°   20/20" — a refraction and the acuity measured
    /// with it, in one cell. Only when BOTH exist: a lone refraction is
    /// better served by the plain refraction finding.
    private func fused(_ refraction: String?, _ visualAcuity: String?) -> String? {
        guard let refraction, !refraction.isEmpty,
              let visualAcuity, !visualAcuity.isEmpty else { return nil }
        return refraction + PatientDemographics.fusedSeparator + visualAcuity
    }

    /// Whitespace between the refraction and the VA in a fused cell.
    static let fusedSeparator = "   "

    /// A display name for messages ("Details for SAMPLE, Jane are ready").
    var displayName: String? {
        let parts = [lastName, firstName].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}
