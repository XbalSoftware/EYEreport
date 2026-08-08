//
//  Presets.swift
//  EYEreport — built-in template factories
//
//  The built-in template(s) seeded on first launch (and by app reset):
//    • standardReferral — full OD/OS findings grid, boxed Impressions/Plan
//
//  Returns ReportDocument values usable as templates (patient block blank,
//  findings at defaultValue, boilerplate prose in place). The driver's-licence
//  letter was deliberately REMOVED from the seeds — the user maintains it as
//  an ordinary template with no special status.

import Foundation

enum Presets {

    static let all: [ReportDocument] = [standardReferral]

    /// The standard findings grid — single source for BOTH the built-in
    /// referral template and a findings block added from the editor's "+"
    /// menu. A computed var, so every use gets fresh row ids.
    static var standardFindings: FindingsContent {
        FindingsContent(
            header: "My findings today include:",
            rows: [
                FindingRow(
                    label: "Refraction",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "", os: "")
                ),
                FindingRow(
                    label: "VA (cc)",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "", os: ""),
                    affordance: FieldAffordance(prefix: "20/")
                ),
                FindingRow(
                    label: "IOP (NCT)",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "", os: ""),
                    affordance: FieldAffordance(suffix: "mmHg")
                ),
                FindingRow(
                    label: "Anterior Segment",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "Unremarkable", os: "Unremarkable")
                ),
                FindingRow(
                    label: "Posterior Segment",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "Unremarkable", os: "Unremarkable")
                ),
                FindingRow(
                    label: "cup:disc ratio",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "", os: "")
                ),
                FindingRow(
                    label: "Visual field (FDT)",
                    value: .paired(od: "", os: ""),
                    defaultValue: .paired(od: "30-5 screening full", os: "30-5 screening full")
                ),
                FindingRow(
                    label: "Pupils",
                    value: .spanning(""),
                    defaultValue: .spanning("Equal, Round, React to Light, no RAPD")
                ),
                FindingRow(
                    label: "Binocular vision",
                    value: .spanning(""),
                    defaultValue: .spanning("Within normal limits, EOMs full range of motion")
                ),
            ]
        )
    }

    // MARK: - Standard referral

    static var standardReferral: ReportDocument {
        ReportDocument(
            blocks: [
                // 1. Recipient — provider fax; name/fax left blank for the template
                Block(.recipient(.providerFax(name: "", fax: ""))),

                // 2. Bare date line (no label prefix)
                Block(.date(DateContent(label: "", date: nil))),

                // 3. Patient — full box, all fields
                Block(.patient(PatientContent(
                    renderStyle: .fullBox,
                    includedFields: Set(PatientField.allCases)
                ))),

                // 4. Salutation — doctor name blank in template
                Block(.salutation(.dearDoctor(name: "", mirrorsRecipient: true))),

                // 5. Subjective lead-in (clinician fills below)
                Block(.prose(ProseContent(paragraphs: [
                    Paragraph(runs: [
                        Run(.fixed(""))
                    ])
                ]))),

                // 6. Findings grid (shared standard row set — see standardFindings)
                Block(.findings(standardFindings)),

                // 7. Impressions / Plan — boxed, both sections volatile
                Block(.impressionsPlan(ImpressionsPlanContent(
                    sections: [
                        LabeledSection(
                            label: "Impressions:",
                            body: .empty,
                            carryForward: .volatile
                        ),
                        LabeledSection(
                            label: "Plan:",
                            body: .empty,
                            carryForward: .volatile
                        ),
                    ],
                    boxed: true
                ))),

                // 8. Closing
                Block(.closing(.sharingInCare)),

                // 9. Signature
                Block(.signature(SignatureContent(valediction: "Regards,"))),
            ],
            templateName: "Standard Referral"
        )
    }
}
