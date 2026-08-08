import SwiftUI

// MARK: - Shared prose routing check

extension ProseContent {
    /// True when every run of every paragraph is `.fixed` — the condition for
    /// the consolidated one-box editor (and thus for one tab stop). Single
    /// source: ProseEditor's routing, ImpressionsPlanEditor's routing, and
    /// FocusOrder's key list all read this, so the tab chain cannot disagree
    /// with which editor is actually on screen.
    var isAllFixed: Bool {
        paragraphs.allSatisfy { para in
            para.runs.allSatisfy { if case .fixed = $0.content { return true }; return false }
        }
    }
}

// MARK: - Per-block focus chain handle

/// The document-wide focus chain, as seen from inside one block. Created by
/// `ReportEditorView` per block row and threaded through `BlockContentEditor`
/// into every per-type editor: it namespaces field keys by block ID, carries
/// the ONE shared focused-field binding, and moves focus along the
/// document-ordered chain on Tab / Shift-Tab.
///
/// Every editor declares it as `var focus: BlockFocusChain? = nil` — nil (the
/// default, and what previews get) means "outside any chain": fields then
/// behave as plain bridged fields with no Tab handling.
struct BlockFocusChain {
    let blockID: UUID
    let binding: Binding<String?>
    let move: (_ fromKey: String, _ backward: Bool) -> Void

    static func key(blockID: UUID, field: String) -> String {
        "\(blockID.uuidString)/\(field)"
    }

    func key(_ field: String) -> String {
        Self.key(blockID: blockID, field: field)
    }
}

/// Sugar so editors can write `focus.key(...)` / `focus.tab(...)` without
/// unwrapping — everything degrades to nil (field out of the chain) when the
/// editor was mounted without a chain.
extension Optional where Wrapped == BlockFocusChain {
    func key(_ field: String) -> String? { self?.key(field) }
    var binding: Binding<String?>? { self?.binding }
    func tab(_ field: String) -> ((Bool) -> Void)? {
        guard let chain = self else { return nil }
        return { backward in chain.move(chain.key(field), backward) }
    }
}

// MARK: - Field names (single source — editors AND FocusOrder use these)

enum FocusFields {
    static let title = "title"
    static let subject = "subject"
    static let recipientName = "recipientName"
    static let recipientFax = "recipientFax"
    static let recipientFreeform = "recipientFreeform"
    static let salutationName = "salutationName"
    static let salutationCustom = "salutationCustom"
    static let dateLabel = "dateLabel"
    static let dateDay = "dateDay"
    static let dateMonth = "dateMonth"
    static let dateYear = "dateYear"
    static let patientLastName = "patientLastName"
    static let patientFirstName = "patientFirstName"
    static let patientDOBDay = "patientDOBDay"
    static let patientDOBMonth = "patientDOBMonth"
    static let patientDOBYear = "patientDOBYear"
    static let patientAHC = "patientAHC"
    static let patientPhone = "patientPhone"
    static let patientAddress = "patientAddress"
    static let prose = "prose"
    static let closingCustom = "closingCustom"
    static let signatureValediction = "signatureValediction"

    static func findingsCell(_ rowID: UUID, _ slot: String) -> String {
        "findings-\(rowID.uuidString)-\(slot)"
    }
    static func impressionsPlanBody(_ sectionID: UUID) -> String {
        "ipBody-\(sectionID.uuidString)"
    }
}

// MARK: - Document-ordered key list

/// Derives the whole document's tab order from the model, block by block in
/// list order, mirroring exactly which fields each editor puts in the chain.
/// It is computed fresh at every Tab press, so reordering / adding / deleting
/// blocks reorders tabbing with no extra bookkeeping.
///
/// Deliberately NOT in the chain: fields behind "Edit fields" toggles
/// (findings header / row labels / affordances, Impressions/Plan section
/// labels) — the chain covers data entry, not structural editing — and the
/// per-paragraph fallback editors of slot/token prose blocks (known
/// limitation of the fallback surface).
enum FocusOrder {
    static func orderedKeys(for document: ReportDocument) -> [String] {
        // A closure, not a bare function reference: keys(for:) counts as
        // main-actor-isolated (it reads SignatureEditor.fixedChoices), and
        // passing it directly into flatMap warns under concurrency checking.
        document.blocks.flatMap { keys(for: $0) }
    }

    static func keys(for block: Block) -> [String] {
        func k(_ field: String) -> String {
            BlockFocusChain.key(blockID: block.id, field: field)
        }
        switch block.content {
        case .recipient(let r):
            switch r {
            case .providerFax: return [k(FocusFields.recipientName), k(FocusFields.recipientFax)]
            case .freeform:    return [k(FocusFields.recipientFreeform)]
            case .none:        return []
            }
        case .title:
            return [k(FocusFields.title)]
        case .date:
            return [k(FocusFields.dateLabel), k(FocusFields.dateDay),
                    k(FocusFields.dateMonth), k(FocusFields.dateYear)]
        case .patient(let p):
            // Follows the block's field order; deleted fields have no rows,
            // and include-toggled-off rows are SKIPPED (matching Findings —
            // they remain tappable, just not tab stops). Rename fields
            // (edit-fields mode) are not in the chain.
            var keys: [String] = []
            for field in p.resolvedFieldOrder where p.includedFields.contains(field) {
                switch field {
                case .name:
                    keys.append(k(FocusFields.patientLastName))
                    keys.append(k(FocusFields.patientFirstName))
                case .dob:
                    keys.append(k(FocusFields.patientDOBDay))
                    keys.append(k(FocusFields.patientDOBMonth))
                    keys.append(k(FocusFields.patientDOBYear))
                case .ahc:
                    keys.append(k(FocusFields.patientAHC))
                case .phone:
                    keys.append(k(FocusFields.patientPhone))
                case .address:
                    keys.append(k(FocusFields.patientAddress))
                }
            }
            return keys
        case .subject:
            return [k(FocusFields.subject)]
        case .salutation(let s):
            switch s {
            case .dearDoctor(_, let mirrors):
                // While mirroring the recipient, the name field is a grayed
                // preview — no tab stop.
                return mirrors ? [] : [k(FocusFields.salutationName)]
            case .toWhomItMayConcern: return []
            case .custom:             return [k(FocusFields.salutationCustom)]
            }
        case .prose(let p):
            // The consolidated box is ONE tab stop; a slot/token block uses
            // the per-paragraph fallback, which is outside the chain.
            return p.isAllFixed ? [k(FocusFields.prose)] : []
        case .findings(let f):
            var keys: [String] = []
            for row in f.rows where row.included {
                switch row.value {
                case .paired:
                    keys.append(k(FocusFields.findingsCell(row.id, "od")))
                    keys.append(k(FocusFields.findingsCell(row.id, "os")))
                case .spanning:
                    keys.append(k(FocusFields.findingsCell(row.id, "span")))
                }
            }
            return keys
        case .impressionsPlan(let ip):
            return ip.sections.compactMap { section in
                section.body.isAllFixed ? k(FocusFields.impressionsPlanBody(section.id)) : nil
            }
        case .closing(let c):
            if case .custom = c { return [k(FocusFields.closingCustom)] }
            return []
        case .signature(let s):
            // The custom-valediction field is visible exactly when the stored
            // valediction is not one of the fixed picker choices.
            return SignatureEditor.fixedChoices.contains(s.valediction)
                ? [] : [k(FocusFields.signatureValediction)]
        case .spacer:
            return [] // no typed fields
        }
    }
}
