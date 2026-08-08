import SwiftUI

// Shared text styles for the block editor, tuned for the app's primary
// dark-mode use: block titles need to read as section headers, and small
// field-name labels need more contrast than `.secondary` gives on black.
// The height SelectAllTextField renders at with no explicit frame override —
// e.g. FindingsEditor's paired/spanning value cells (Refraction, etc). Applied
// explicitly here so DateEditor/SalutationEditor/ImpressionsPlanEditor match
// it rather than relying on each one's surrounding layout to coincidentally
// produce the same intrinsic size.
let standardFieldHeight: CGFloat = 30

extension View {
    func blockTitleStyle() -> some View {
        self.font(.title3.bold())
            .foregroundStyle(.blue)
    }

    func fieldLabelStyle() -> some View {
        self.font(.caption)
            .foregroundStyle(.primary.opacity(0.75))
    }
}

/// Month display for the DD / MM / YYYY date fields (date block + patient
/// DOB): the user types a number, and on blur the field shows the ALL-CAPS
/// three-letter abbreviation ("8" → "AUG") — matching what the renderer
/// prints. The abbreviations here MUST stay in step with
/// `ReportRenderer.dateFormatter` (en_US_POSIX short months, uppercased).
enum MonthFormat {
    static let abbreviations = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                                "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// "AUG" for 8; nil outside 1–12 (including nil in).
    static func abbreviation(for month: Int?) -> String? {
        guard let month, (1...12).contains(month) else { return nil }
        return abbreviations[month - 1]
    }

    /// Month number from field text: digits 1–12, or a three-letter
    /// abbreviation in any case (so a displayed "AUG" round-trips). Anything
    /// else — including out-of-range digits — is nil.
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let n = Int(trimmed) { return (1...12).contains(n) ? n : nil }
        if let index = abbreviations.firstIndex(of: trimmed.uppercased()) {
            return index + 1
        }
        return nil
    }
}
