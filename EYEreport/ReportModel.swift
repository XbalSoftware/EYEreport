//
//  ReportModel.swift
//  Clinical Report Composer — core document model
//
//  Design summary (the decisions this file encodes):
//
//  • A report is an ORDERED LIST OF TYPED BLOCKS, not a fixed skeleton with
//    optional fields. "From scratch" is the empty list; a template is a saved
//    list with defaults; a filled report is a list with patient data. Same
//    structure throughout — only the storage location differs (templates +
//    letterheads back up normally; filled reports live in the encrypted,
//    biometric-gated vault).
//
//  • Every element that can hold a per-report VALUE carries a CarryForward
//    policy: .sticky (survives a duplicate — cumulative dose, start date) or
//    .volatile (cleared on duplicate — this-visit measurements, free-typed
//    impressions). This is what makes "duplicate last year's screening" a
//    shortcut rather than a stale-data landmine.
//
//  • The Patient block is a self-contained, copyable unit. "New report, same
//    patient" copies exactly that one block forward; nothing else leaks.
//
//  Codable is synthesized throughout (Swift 5.5+ synthesizes it for enums with
//  associated values), so the whole graph serializes for the vault, for
//  template export/import, and for backup with no custom coding.
//
//  Note: add `Sendable` conformances before moving decryption/render work off
//  the main actor; omitted here to keep the model legible.
//

import Foundation

// MARK: - Carry-forward policy

/// Whether a value-bearing element retains its value when a report is
/// duplicated for a new visit. The load-bearing flag for serial reports.
enum CarryForward: String, Codable, Hashable {
    /// Survives duplication. Use for facts that persist across visits:
    /// HCQ cumulative dose, medication start date, condition history.
    case sticky
    /// Cleared on duplication. Use for anything measured or judged at THIS
    /// visit: VA, IOP, today's impressions. Default everywhere — opt into
    /// sticky deliberately.
    case volatile
}

// MARK: - Document

/// A report. Identical in shape whether it's a blank, a template, or a filled
/// patient document — the distinction is where it's stored and whether the
/// patient block carries data.
struct ReportDocument: Codable, Identifiable {
    var id: UUID = UUID()

    /// The block sequence. Add / remove / reorder freely — this is what makes
    /// "from scratch" and "from template" the same editor.
    var blocks: [Block] = []

    /// Which letterhead to composite onto. Orthogonal to the content: any
    /// document prints on any letterhead (you, across offices). The actual
    /// letterhead asset + its safe-zone rect live in the Letterheads module.
    var letterheadID: UUID? = nil

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    /// Display name when saved as a template ("Driver's licence — Condition A
    /// removal"). nil for an in-progress patient report.
    var templateName: String? = nil

    /// Rendered body text size in points; nil = the historical 11pt (legacy
    /// JSON decodes unchanged). Titles render at this + 2; the page-number
    /// stamp stays 9. Chosen from the Preview toolbar (9–13); carries into
    /// templates via asTemplate's whole-document copy.
    var bodyFontSize: Double? = nil
}

// MARK: - Block wrapper

/// A stable identity wrapper so the editor can reorder/edit blocks in a
/// SwiftUI ForEach while the typed payload lives in `content`.
struct Block: Codable, Identifiable {
    let id: UUID
    var content: BlockContent

    init(id: UUID = UUID(), _ content: BlockContent) {
        self.id = id
        self.content = content
    }
}

/// The closed set of block types, derived from the four example letters.
/// Adding a 13th report type composes a new sequence of these — it does not
/// require new layout code.
enum BlockContent: Codable {
    case recipient(RecipientContent)        // "TO DOCTOR NAME / Fax" or "To: MVR"
    case title(TitleContent)                // "OCULAR HEALTH AND VISION REPORT"
    case date(DateContent)                  // "Date of exam: …"
    case patient(PatientContent)            // the copyable identity unit
    case subject(SubjectContent)            // "RE: hydroxychloroquine screening"
    case salutation(SalutationContent)      // "Dear Dr. X" / "To Whom it May Concern"
    case prose(ProseContent)                // free paragraphs, with slots + tokens
    case findings(FindingsContent)          // the OD/OS grid
    case impressionsPlan(ImpressionsPlanContent) // bordered Impressions/Plan box
    case closing(ClosingContent)            // "Thank you for sharing…"
    case signature(SignatureContent)        // pulls from practitioner profile
    case spacer(SpacerContent)              // adjustable blank vertical gap
}

// MARK: - Recipient

enum RecipientContent: Codable {
    /// Provider referral: "TO DOCTOR NAME" + "Fax (403) …"
    case providerFax(name: String, fax: String)
    /// Agency / freeform: "To: Alberta Motor Vehicle Registry"
    case freeform(String)
    case none
}

// MARK: - Title / Date / Subject

struct TitleContent: Codable {
    var text: String
}

struct DateContent: Codable {
    /// "Date:", "Date of exam:", or "" for a bare date line.
    var label: String
    var date: Date?
    /// Always volatile in practice — a duplicate resets to today regardless,
    /// but the flag keeps the rule uniform across value-bearing blocks.
    var carryForward: CarryForward = .volatile
}

struct SubjectContent: Codable {
    /// Part of a template's identity ("RE: hydroxychloroquine retinopathy
    /// screening"), so it's retained when saving as a template.
    var text: String
}

// MARK: - Spacer

/// A deliberate blank vertical gap for positioning — extra room between blocks
/// or at the top of a report. `lines` blank body-height lines are rendered;
/// carries no text, so it never triggers deletion warnings and is preserved
/// as-is by duplicate and save-as-template.
struct SpacerContent: Codable {
    var lines: Int = 1
}

// MARK: - Salutation / Closing

enum SalutationContent: Codable {
    /// `mirrorsRecipient` (default true): the editor keeps `name` in sync
    /// with the recipient block's doctor name; off = hand-typed name.
    case dearDoctor(name: String, mirrorsRecipient: Bool)
    case toWhomItMayConcern
    case custom(String)

    // Custom Codable, byte-compatible with the previously synthesized format
    // ({"dearDoctor":{"name":…}}, {"custom":{"_0":…}}), so existing JSON
    // decodes unchanged — a missing mirrorsRecipient reads as true (the
    // default the feature ships with).
    private enum CodingKeys: String, CodingKey { case dearDoctor, toWhomItMayConcern, custom }
    private enum DearDoctorKeys: String, CodingKey { case name, mirrorsRecipient }
    private enum UnlabeledKeys: String, CodingKey { case _0 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.dearDoctor) {
            let n = try c.nestedContainer(keyedBy: DearDoctorKeys.self, forKey: .dearDoctor)
            self = .dearDoctor(name: try n.decode(String.self, forKey: .name),
                               mirrorsRecipient: try n.decodeIfPresent(Bool.self, forKey: .mirrorsRecipient) ?? true)
        } else if c.contains(.custom) {
            let n = try c.nestedContainer(keyedBy: UnlabeledKeys.self, forKey: .custom)
            self = .custom(try n.decode(String.self, forKey: ._0))
        } else {
            self = .toWhomItMayConcern
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dearDoctor(let name, let mirrors):
            var n = c.nestedContainer(keyedBy: DearDoctorKeys.self, forKey: .dearDoctor)
            try n.encode(name, forKey: .name)
            try n.encode(mirrors, forKey: .mirrorsRecipient)
        case .toWhomItMayConcern:
            _ = c.nestedContainer(keyedBy: UnlabeledKeys.self, forKey: .toWhomItMayConcern)
        case .custom(let s):
            var n = c.nestedContainer(keyedBy: UnlabeledKeys.self, forKey: .custom)
            try n.encode(s, forKey: ._0)
        }
    }
}

enum ClosingContent: Codable {
    case sharingInCare              // "Thank you for sharing in the care…"
    case contactOffice             // "Please contact my office if…"
    case custom(String)
}

// MARK: - Patient (the copyable unit)

enum PatientField: String, Codable, CaseIterable {
    case name, dob, ahc, phone, address
}

/// How the patient block renders, captured from the three examples:
/// full box (referral), reduced box (fight: Patient + DOB only), or inline
/// bold labels (driver's letter).
enum PatientRenderStyle: String, Codable {
    case fullBox
    case reducedBox
    case inlineLabels
}

/// The self-contained patient identity. This whole struct is what
/// `newReport(from:carryingPatient:)` copies forward — the unit that lets you
/// skip re-entering details. Match/dedupe patients on `lastName` +
/// `firstName` + `dob` (name alone collides).
struct PatientContent: Codable {
    var lastName: String = ""
    var firstName: String = ""
    /// year/month/day only — avoids time-zone drift on a birthdate and gives
    /// an exact match key for vault search. Date-picker backed in the UI.
    var dob: DateComponents? = nil
    var ahc: String = ""
    var phone: String = ""
    var address: String = ""

    var renderStyle: PatientRenderStyle = .fullBox
    /// Which fields actually display (fight letter shows only name + dob).
    var includedFields: Set<PatientField> = Set(PatientField.allCases)
    /// Display order AND presence of the patient rows — the editor prompts
    /// and the renderer prints in this order. nil = the standard five in
    /// standard order (legacy JSON decodes unchanged). A field absent from
    /// the list is DELETED from this template/report: not prompted, not
    /// printed. Its typed storage stays, so identity matching, tokens, and
    /// PHI blanking are unaffected.
    var fieldOrder: [PatientField]? = nil
    /// Custom row labels keyed by `PatientField.rawValue` ("ahc" → "PHN"),
    /// stored WITHOUT trailing punctuation (the renderer adds ":"). A
    /// missing/empty entry = the default label; nil = all defaults.
    var fieldLabels: [String: String]? = nil

    /// The effective ordered field list (standard order when unset).
    var resolvedFieldOrder: [PatientField] { fieldOrder ?? PatientField.allCases }

    /// The custom label for a field, nil when unset/empty (use the default).
    func customLabel(for field: PatientField) -> String? {
        guard let label = fieldLabels?[field.rawValue], !label.isEmpty else { return nil }
        return label
    }

    /// True when no identifying data is present (a template's patient block).
    var isBlank: Bool {
        lastName.isEmpty && firstName.isEmpty && dob == nil
            && ahc.isEmpty && phone.isEmpty && address.isEmpty
    }

    /// Strip identity but preserve render style + field selection/order/labels,
    /// so a template keeps its layout without carrying a person.
    func blanked() -> PatientContent {
        PatientContent(renderStyle: renderStyle, includedFields: includedFields,
                       fieldOrder: fieldOrder, fieldLabels: fieldLabels)
    }
}

// MARK: - Findings (OD/OS grid)

enum FindingValue: Codable {
    case paired(od: String, os: String)     // VA, IOP, segments
    case spanning(String)                    // "Equal, Round, React to Light, no RAPD"

    var isEmpty: Bool {
        switch self {
        case .paired(let od, let os): return od.isEmpty && os.isEmpty
        case .spanning(let s):        return s.isEmpty
        }
    }
}

/// Affordances rendered around the value, e.g. "20/" prefix, "mmHg" suffix.
struct FieldAffordance: Codable {
    var prefix: String? = nil
    var suffix: String? = nil
}

struct FindingRow: Codable, Identifiable {
    let id: UUID
    var label: String                 // "VA (cc)", "IOP (NCT)", "Pupils"
    var value: FindingValue
    var defaultValue: FindingValue    // "Unremarkable", "20/", the screening default
    var affordance: FieldAffordance?
    var carryForward: CarryForward = .volatile  // exam values reset on duplicate
    var included: Bool = true         // tap to omit a row entirely

    init(id: UUID = UUID(),
         label: String,
         value: FindingValue,
         defaultValue: FindingValue,
         affordance: FieldAffordance? = nil,
         carryForward: CarryForward = .volatile,
         included: Bool = true) {
        self.id = id
        self.label = label
        self.value = value
        self.defaultValue = defaultValue
        self.affordance = affordance
        self.carryForward = carryForward
        self.included = included
    }

    /// Reset to the row's default — used on duplicate for volatile rows and
    /// when blanking to a template.
    mutating func resetToDefault() { value = defaultValue }
}

struct FindingsContent: Codable {
    /// Optional lead-in printed above the grid ("My findings today include:").
    /// Lives on the block so it can't be reordered away from its table.
    var header: String? = nil
    var rows: [FindingRow] = []
}

// MARK: - Prose with runs (the slot/token abstraction)

/// Inline emphasis carried by a run, applied at render time. Authored, not
/// derived: the driver's letter bolds "Condition A" and "20/20 OU"; the HCQ
/// letter bolds "no evidence of hydroxychloroquine maculopathy". A whole-
/// paragraph bold (the driver's-letter "In my professional opinion…" line) is
/// expressed by marking every run in that paragraph .bold — no separate
/// paragraph-level emphasis needed.
enum Emphasis: String, Codable {
    case regular, bold, italic, boldItalic
    // Underline is orthogonal to bold/italic, so it needs its own combinations.
    // These are added as new raw-value cases (not an OptionSet refactor) so that
    // existing "regular"/"bold"/"italic"/"boldItalic" values in saved templates
    // keep decoding unchanged — additive, zero migration.
    case underline, boldUnderline, italicUnderline, boldItalicUnderline
}

/// What a run carries, independent of its emphasis.
enum RunContent: Codable {
    case fixed(String)
    case token(DataToken)
    case slot(Slot)
}

/// A paragraph is a sequence of runs. A run is fixed text, a data token that
/// pulls from the patient/practitioner/date, or a pick-one slot — each with its
/// own emphasis. One mechanism covers "Dear Dr. ___", the inserted exam date,
/// the driver's-letter bracketed choice, and inline bold.
struct Run: Codable {
    var content: RunContent
    var emphasis: Emphasis = .regular

    init(_ content: RunContent, emphasis: Emphasis = .regular) {
        self.content = content
        self.emphasis = emphasis
    }
}

/// Values pulled at render time so they stay consistent and never go stale.
enum DataToken: String, Codable {
    case patientFullName
    case patientFirstName
    case patientLastName
    case patientDOB
    case examDate
    case practitionerName
    case practitionerCredentials
}

/// A pick-one-or-free-type slot embedded in prose.
struct Slot: Codable {
    var options: [String]            // the bracketed alternatives
    var selectedIndex: Int? = nil    // nil = unfilled
    var freeText: String? = nil      // overrides options when the user types
    var carryForward: CarryForward = .volatile

    var isFilled: Bool { selectedIndex != nil || (freeText?.isEmpty == false) }

    /// Clear the choice (duplicate of a volatile slot, or template blanking).
    mutating func clear() { selectedIndex = nil; freeText = nil }
}

enum ParagraphStyle: Codable {
    case body
    case bullet
    /// Whole-paragraph indent relative to the rest — maps to
    /// NSParagraphStyle.headIndent (and firstLineHeadIndent) at render time.
    case indented(level: Int)
    /// Ordered list item. The number is NOT stored — the renderer numbers a run
    /// of consecutive `.numbered` paragraphs 1, 2, 3…, restarting whenever a
    /// non-numbered paragraph interrupts, mirroring how `.bullet` is drawn.
    case numbered
}

struct Paragraph: Codable, Identifiable {
    let id: UUID
    var runs: [Run]
    var style: ParagraphStyle = .body

    init(id: UUID = UUID(), runs: [Run], style: ParagraphStyle = .body) {
        self.id = id
        self.runs = runs
        self.style = style
    }
}

struct ProseContent: Codable {
    var paragraphs: [Paragraph] = []

    /// Draw a rectangular frame around the whole block at render time — the
    /// same box style as Impressions/Plan. Optional so documents saved before
    /// this field existed keep decoding (missing key = nil = no box). A boxed
    /// prose block moves whole at pagination instead of splitting, exactly
    /// like the Impressions/Plan box.
    var boxed: Bool? = nil

    static let empty = ProseContent()
}

// MARK: - Impressions / Plan

/// A labelled sub-section inside the bordered box. Its body reuses ProseContent
/// (so bullets + inline bold + slots all work). The section-level carryForward
/// is the guard against stale clinical text: free-typed, visit-specific
/// impressions default to .volatile and clear on duplicate; standardized
/// boilerplate (the fight-clearance wording) is marked .sticky and survives.
struct LabeledSection: Codable, Identifiable {
    let id: UUID
    /// The section heading ("Impressions:", "Plan:"), rich content so it can
    /// carry emphasis. Conventionally a single bold paragraph — the String
    /// convenience init below seeds exactly that.
    var label: ProseContent
    var body: ProseContent
    var carryForward: CarryForward = .volatile

    init(id: UUID = UUID(),
         label: ProseContent,
         body: ProseContent,
         carryForward: CarryForward = .volatile) {
        self.id = id
        self.label = label
        self.body = body
        self.carryForward = carryForward
    }

    /// String convenience: seeds the conventional single bold label run.
    init(id: UUID = UUID(),
         label: String,
         body: ProseContent,
         carryForward: CarryForward = .volatile) {
        self.init(id: id,
                  label: ProseContent(paragraphs: [Paragraph(runs: [Run(.fixed(label), emphasis: .bold)])]),
                  body: body,
                  carryForward: carryForward)
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, body, carryForward
    }

    /// `label` was a plain String before it became rich — a legacy value is
    /// mapped to the single bold run it always rendered as, so existing saved
    /// templates and reports keep decoding unchanged.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        if let legacy = try? c.decode(String.self, forKey: .label) {
            label = ProseContent(paragraphs: [Paragraph(runs: [Run(.fixed(legacy), emphasis: .bold)])])
        } else {
            label = try c.decode(ProseContent.self, forKey: .label)
        }
        body = try c.decode(ProseContent.self, forKey: .body)
        carryForward = try c.decode(CarryForward.self, forKey: .carryForward)
    }
}

struct ImpressionsPlanContent: Codable {
    var sections: [LabeledSection] = []
    var boxed: Bool = true
}

// MARK: - Signature

/// Carries no per-report data — it's rendered from the practitioner profile in
/// Settings (one identity, many letterheads). Kept as a block so its position
/// in the sequence is explicit and editable.
struct SignatureContent: Codable {
    /// Valediction printed above the signature image. Authored content, not a
    /// render constant, so it can vary ("Regards," / "Sincerely,").
    var valediction: String = "Regards,"
    /// Optional per-document override if a report must show different
    /// credentials than the profile default; nil = use profile.
    var credentialsOverride: String? = nil
}

// MARK: - Practitioner profile (lives in backed-up Settings, referenced here)

/// Minimal stub so SignatureContent has something to resolve against. Belongs
/// to the Settings store, not the document; included for completeness.
nonisolated struct PractitionerProfile: Codable {
    var name: String = ""
    var credentials: String = ""
    var practitionerID: String = ""
    /// Signature image stored as data in the profile, stamped at render.
    var signatureImageData: Data? = nil
}

// MARK: - Document operations (the three the model is built to make trivial)

extension ReportDocument {

    /// The patient block, if the document has one — the copyable identity unit.
    var patient: PatientContent? {
        for block in blocks {
            if case .patient(let p) = block.content { return p }
        }
        return nil
    }

    /// Replace the patient block's data in place (used when injecting a carried
    /// patient into a fresh template).
    private func settingPatient(_ patient: PatientContent) -> ReportDocument {
        var copy = self
        copy.blocks = copy.blocks.map { block in
            if case .patient(let existing) = block.content {
                // preserve the template's chosen layout — render style, field
                // set, field order/presence, custom labels — take the carried
                // identity
                var merged = patient
                merged.renderStyle = existing.renderStyle
                merged.includedFields = existing.includedFields
                merged.fieldOrder = existing.fieldOrder
                merged.fieldLabels = existing.fieldLabels
                return Block(id: block.id, .patient(merged))
            }
            return block
        }
        return copy
    }

    /// "New report, same patient." Start from a template, drop in the patient
    /// block, leave everything else at template defaults. Fresh identity + date.
    static func newReport(from template: ReportDocument,
                          carryingPatient patient: PatientContent) -> ReportDocument {
        var doc = template
        doc.id = UUID()
        doc.templateName = nil
        doc.createdAt = Date()
        doc.modifiedAt = Date()
        doc = doc.settingPatient(patient)
        doc.resetDateBlocksToToday()
        return doc
    }

    /// Convenience: a fresh in-progress report from a template with no patient
    /// carried forward (blank patient). Routes through the designated
    /// newReport(from:carryingPatient:) so all resets stay in one place.
    static func newReport(from template: ReportDocument) -> ReportDocument {
        newReport(from: template, carryingPatient: PatientContent())
    }

    /// "Duplicate this report for a new visit." Keep the patient and every
    /// sticky value; clear every volatile one. This is the serial-report path
    /// (next year's HCQ screening from last year's) with the stale-data guard.
    func duplicatedForNewVisit() -> ReportDocument {
        var doc = self
        doc.id = UUID()
        doc.templateName = nil
        doc.createdAt = Date()
        doc.modifiedAt = Date()

        doc.blocks = doc.blocks.map { block in
            Block(id: UUID(), Self.clearVolatile(in: block.content))
        }
        doc.resetDateBlocksToToday()
        return doc
    }

    /// Strip to a shareable template: blank the patient and all per-report
    /// data, but keep structure, layout, and clinical boilerplate. Safe to
    /// export and back up — contains no PHI. (Save-as-template MUST go through
    /// this so a real patient is never baked into a shared file.)
    func asTemplate(named name: String) -> ReportDocument {
        var doc = self
        doc.id = UUID()
        doc.templateName = name
        doc.createdAt = Date()
        doc.modifiedAt = Date()

        doc.blocks = doc.blocks.map { block in
            Block(id: block.id, Self.blankForTemplate(block.content))
        }
        return doc
    }

    private mutating func resetDateBlocksToToday() {
        blocks = blocks.map { block in
            if case .date(var d) = block.content {
                d.date = Date()
                return Block(id: block.id, .date(d))
            }
            return block
        }
    }
}

// MARK: - Per-block transforms backing the operations

private extension ReportDocument {

    /// Clear only volatile values; retain sticky ones. Used by duplicate.
    static func clearVolatile(in content: BlockContent) -> BlockContent {
        switch content {
        case .findings(var f):
            f.rows = f.rows.map { row in
                var r = row
                if r.carryForward == .volatile { r.resetToDefault() }
                return r
            }
            return .findings(f)

        case .prose(var p):
            p.paragraphs = p.paragraphs.map { clearVolatileSlots(in: $0) }
            return .prose(p)

        case .impressionsPlan(var ip):
            ip.sections = ip.sections.map { section in
                var s = section
                if s.carryForward == .volatile {
                    s.body = .empty            // drop visit-specific text
                } else {
                    s.body.paragraphs = s.body.paragraphs.map { clearVolatileSlots(in: $0) }
                }
                return s
            }
            return .impressionsPlan(ip)

        // Recipient + salutation kept as-is on a same-patient follow-up;
        // user edits if the addressee changes.
        default:
            return content
        }
    }

    /// Blank everything per-report for a shareable template.
    static func blankForTemplate(_ content: BlockContent) -> BlockContent {
        switch content {
        case .patient(let p):
            return .patient(p.blanked())

        case .date(var d):
            d.date = nil
            return .date(d)

        // Recipient, subject, title, closing, signature, salutation,
        // prose, findings, impressionsPlan are preserved as-is in a template.
        default:
            return content
        }
    }

    static func clearVolatileSlots(in paragraph: Paragraph) -> Paragraph {
        var para = paragraph
        para.runs = para.runs.map { run in
            if case .slot(var slot) = run.content, slot.carryForward == .volatile {
                slot.clear(); return Run(.slot(slot), emphasis: run.emphasis)
            }
            return run
        }
        return para
    }

    static func clearAllSlots(in paragraph: Paragraph) -> Paragraph {
        var para = paragraph
        para.runs = para.runs.map { run in
            if case .slot(var slot) = run.content {
                slot.clear(); return Run(.slot(slot), emphasis: run.emphasis)
            }
            return run
        }
        return para
    }
}

// MARK: - Worked example: the driver's-letter slot, to sanity-check the model

