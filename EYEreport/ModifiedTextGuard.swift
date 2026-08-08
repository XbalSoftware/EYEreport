//
//  ModifiedTextGuard.swift
//  EYEreport
//
//  Dirty-check for deletion warnings: has the user entered or changed text
//  relative to the BASELINE document (the template copy — or blank document —
//  the editing session started from)?
//
//  A block's "fingerprint" is the ordered list of the values a user can
//  enter in the NORMAL data-entry flow. A block is MODIFIED when its
//  fingerprint differs from the same-id block in the baseline (or, for a
//  block the user added, when its fingerprint is non-empty — which is why
//  seeded boilerplate must stay OUT of the fingerprint, or a freshly added
//  block would warn untouched). Deliberately ignored as structure: include
//  toggles, render styles, carry-forward, block order, everything behind an
//  "Edit fields" toggle (findings header / row labels / affordances, patient
//  custom labels, Impressions/Plan section labels), and picker choices (a
//  fixed valediction).
//
//  Maintenance note (mirrors FocusOrder's rule): when an editor gains a NEW
//  user-typed field, add it to `fingerprint(of:)` here, or deleting that
//  block will silently skip the warning.
//

import Foundation

enum ModifiedText {

    /// True when this block's entered text differs from its baseline
    /// counterpart — deleting it would lose typed content.
    static func isModified(_ block: Block, against baseline: ReportDocument) -> Bool {
        let current = fingerprint(of: block.content)
        guard let original = baseline.blocks.first(where: { $0.id == block.id }) else {
            // User-added block: modified as soon as it holds any text.
            return !current.isEmpty
        }
        return current != fingerprint(of: original.content)
    }

    /// True when ANY current block is modified — the Start Over gate.
    /// (Blocks already deleted from the document have nothing left to lose.)
    static func hasModifiedText(_ document: ReportDocument, against baseline: ReportDocument) -> Bool {
        document.blocks.contains { isModified($0, against: baseline) }
    }

    // MARK: - Fingerprint

    /// Every user-enterable value in the block, in stable order, trimmed,
    /// with empties dropped (clearing a field still reads as a change,
    /// because the baseline kept its value).
    static func fingerprint(of content: BlockContent) -> [String] {
        var values: [String] = []
        func add(_ s: String?) {
            guard let s else { return }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values.append(trimmed) }
        }

        switch content {
        case .recipient(let r):
            switch r {
            case .providerFax(let name, let fax):
                add(name); add(fax)
            case .freeform(let s):
                add(s)
            case .none:
                break
            }

        case .title(let t):
            add(t.text)

        case .date(let d):
            add(d.label)
            if let date = d.date {
                let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
                add("\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)")
            }

        case .patient(let p):
            add(p.lastName); add(p.firstName)
            if let dob = p.dob {
                add("\(dob.year ?? 0)-\(dob.month ?? 0)-\(dob.day ?? 0)")
            }
            add(p.ahc); add(p.phone); add(p.address)

        case .subject(let s):
            add(s.text)

        case .salutation(let s):
            switch s {
            case .dearDoctor(let name, let mirrors):
                // A mirrored name is DERIVED from the recipient block, not
                // typed here — the recipient block carries that change.
                if !mirrors { add(name) }
            case .toWhomItMayConcern:
                break
            case .custom(let c):
                add(c)
            }

        case .prose(let p):
            addProse(p, add: add)

        case .findings(let f):
            // Values only — the header, row labels, and prefix/suffix are
            // seeded structure (edit-fields territory).
            for row in f.rows {
                switch row.value {
                case .paired(let od, let os): add(od); add(os)
                case .spanning(let s):        add(s)
                }
            }

        case .impressionsPlan(let ip):
            // Bodies only — the section labels are seeded structure.
            for section in ip.sections {
                addProse(section.body, add: add)
            }

        case .closing(let c):
            if case .custom(let s) = c { add(s) }

        case .signature(let s):
            // A fixed-choice valediction is a picker selection, not typed
            // text; only a custom one counts.
            if !SignatureEditor.fixedChoices.contains(s.valediction) {
                add(s.valediction)
            }

        case .spacer:
            // No typed text; line count is structural (like a style), so a
            // spacer never triggers the "changes will be lost" warning.
            break
        }

        return values
    }

    /// Fixed run text, slot free-text, and slot selections — the values a
    /// user can enter in any prose surface. Appends ONLY through `add` (which
    /// captures the caller's array) — passing the array inout here as well
    /// would be two overlapping write paths to the same storage, a Swift
    /// exclusivity crash.
    private static func addProse(_ prose: ProseContent,
                                 add: (String?) -> Void) {
        for paragraph in prose.paragraphs {
            for run in paragraph.runs {
                switch run.content {
                case .fixed(let s):
                    add(s)
                case .slot(let slot):
                    add(slot.freeText)
                    if let picked = slot.selectedIndex { add("slot:\(picked)") }
                case .token:
                    break
                }
            }
        }
    }
}
