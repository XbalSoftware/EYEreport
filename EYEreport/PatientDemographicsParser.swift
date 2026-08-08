//
//  PatientDemographicsParser.swift
//  EYEreport
//
//  Extracts patient details from an IRIS EMR PDF. The PDF carries real,
//  selectable text (PDFKit reads it directly — no OCR), so parsing is
//  deterministic: anchor on the "FILE EXCERPT" divider that separates the
//  clinic letterhead from the patient block, then pick out fields by
//  label/pattern. Exam findings anchor on their own section headers, because
//  every section reuses the same "OD:"/"OS:" labels.
//
//  Ported from Form Filler, where this logic was validated end-to-end
//  against two real IRIS exports (a FILE EXCERPT report and a Complete
//  Exam). Differences here are EYEreport's model, not the parsing: the name
//  comes back split into first/last (the renderer upper-cases the surname
//  itself) and the birth date comes back as DateComponents.
//
//  Every field is extracted independently and defensively — a miss yields
//  nil, never a crash or a wrong guess — and the review sheet is the safety
//  net: the clinician sees and can edit every value before it lands.
//

import Foundation
import PDFKit

nonisolated enum PatientDemographicsParser {

    /// Reads a PDF's text and parses it. nil if the file can't be read or
    /// nothing usable was found.
    static func demographics(fromPDFAt url: URL) -> PatientDemographics? {
        guard let document = PDFDocument(url: url), let text = document.string else { return nil }
        let parsed = parse(pdfText: text)
        return parsed.isEmpty ? nil : parsed
    }

    /// Pure text → demographics. Exposed for testing with synthetic, PHI-free
    /// sample text.
    static func parse(pdfText: String) -> PatientDemographics {
        let lines = pdfText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result = PatientDemographics()
        parseIdentity(from: lines, into: &result)
        parseExamFindings(from: lines, into: &result)
        return result
    }

    // MARK: - Identity

    private static func parseIdentity(from lines: [String], into result: inout PatientDemographics) {
        // The patient block sits between the "FILE EXCERPT" divider and the
        // first exam/entry line (IRIS marks entries with a "•" bullet).
        // Anchoring here skips the clinic letterhead above the divider, so
        // the clinic's own name/address/phone are never captured.
        guard let separator = lines.firstIndex(where: {
            $0.range(of: "FILE EXCERPT", options: .caseInsensitive) != nil
        }) else { return }

        let afterSeparator = lines[(separator + 1)...]
        let regionEnd = afterSeparator.firstIndex(where: { $0.contains("•") }) ?? lines.endIndex
        let region = Array(lines[(separator + 1)..<regionEnd])
        guard !region.isEmpty else { return }

        // Name: first line of the patient block, split into given/surname.
        if let nameLine = region.first?.nilIfEmpty {
            let parts = splitName(nameLine)
            result.firstName = parts.first
            result.lastName = parts.last
        }

        // Address: the lines after the name, up to and including the postal
        // code — stop early if a labelled/number row appears first.
        var addressLines: [String] = []
        for line in region.dropFirst() {
            if let postal = normalizedPostalCode(line) {
                addressLines.append(postal)
                break
            }
            if matchesBirthDate(line) || firstHealthcareNumber(in: line) != nil { break }
            addressLines.append(line)
        }
        result.address = addressLines.isEmpty ? nil : addressLines.joined(separator: ", ")

        // DOB and healthcare # by pattern, anywhere in the patient region.
        let regionText = region.joined(separator: "\n")
        result.dob = firstBirthDate(in: regionText).flatMap(birthComponents)
        result.ahc = firstHealthcareNumber(in: regionText).map(reformattedHealthcareNumber)

        // Phone isn't present in IRIS PDFs; left nil deliberately.
    }

    // MARK: - Exam findings

    /// Exam sections all label each eye with "OD:"/"OS:" (or "O.D.:"/"O.S.:"),
    /// and the same labels recur across sections — so each finding is anchored
    /// to its own section header first, then the next OD/OS lines are read.
    private static func parseExamFindings(from lines: [String], into result: inout PatientDemographics) {
        // Refraction + VA: the source is the most recent "Subjective
        // Refraction (BVA)" (the first such line in the report) — NOT the
        // autorefractor values, which appear earlier with the same labels.
        if let (od, os) = odosValues(afterLineContaining: "Subjective Refraction (BVA)", in: lines) {
            let odParts = splitRefraction(od)
            let osParts = splitRefraction(os)
            result.refractionOD = odParts.refraction
            result.refractionOS = osParts.refraction
            result.visualAcuityOD = odParts.visualAcuity
            result.visualAcuityOS = osParts.visualAcuity
        }

        // Uncorrected (sc) VA, when the exam recorded it. Often one eye only.
        if let (od, os) = uncorrectedVisualAcuities(in: lines) {
            result.uncorrectedVisualAcuityOD = od
            result.uncorrectedVisualAcuityOS = os
        }

        // Keratometry: compacted to "##.##@###/##.##" — first power, first
        // axis (zero-padded to 3 digits), second power; second axis dropped.
        if let (od, os) = odosValues(afterLineContaining: "Keratometry", in: lines) {
            result.keratometryOD = reformattedKeratometry(od)
            result.keratometryOS = reformattedKeratometry(os)
        }

        // IOP as a bare number (the findings row prints its own "mmHg"
        // suffix). Requiring "mmHg" on the OD/OS lines guards against
        // grabbing the neighbouring Pachymetry (µm) line when IOP wasn't
        // recorded — a partial exam shows the header but no values.
        // Window widened past the default: a real export put the page footer
        // between the section header and its readings, and "mmHg" only ever
        // appears on a pressure line, so searching further can find a value
        // that a tight window would miss but can't find a wrong one.
        if let (od, os) = odosValues(afterLineContaining: "Intraocular Pressure", in: lines,
                                     requiring: "mmHg", window: 12) {
            result.intraocularPressureOD = cleanIOP(od)
            result.intraocularPressureOS = cleanIOP(os)
        }
    }

    /// Uncorrected acuities are NOT laid out like the other exam sections.
    /// Under "Entrance Skills → Visual Acuities" IRIS labels each acuity line
    /// with its own viewing condition, and an eye appears only under the
    /// condition it was measured in:
    ///
    ///     Visual Acuities
    ///     Distance • Glasses
    ///     OD: 20 / 20            ← corrected; not ours
    ///     Distance • Unaided
    ///     OS: 20 / 40 -2         ← uncorrected, THIS EYE ONLY
    ///     Near
    ///     OU: 0.37M
    ///
    /// So this can't use `odosValues` (which anchors a section and demands
    /// both eyes): a one-eyed result is normal and must be kept. Instead every
    /// line naming an uncorrected condition is treated as a marker, and the
    /// eye lines that follow it are collected — merging across markers, since
    /// two unaided eyes may be labelled separately.
    ///
    /// Three guards keep a stray marker (e.g. the free-text note "OD with
    /// correction, OS without correction") from importing anything: values
    /// must be Snellen-shaped, collection stops at the first non-eye line once
    /// it has begun, and the scan aborts if a DIFFERENT viewing condition is
    /// named before any value appears.
    private static func uncorrectedVisualAcuities(in lines: [String]) -> (od: String?, os: String?)? {
        var od: String?
        var os: String?

        for (index, line) in lines.enumerated() where namesUncorrectedCondition(line) {
            var cursor = index + 1
            var preamble = 0
            var collecting = false

            while cursor < lines.count {
                let candidate = lines[cursor]
                guard let eye = eyeLabelled(candidate) else {
                    if collecting { break }                          // values ended
                    if namesCorrectedCondition(candidate) { break }  // different condition
                    preamble += 1                                    // "Visual Acuities" etc.
                    if preamble > 2 { break }
                    cursor += 1
                    continue
                }
                guard let value = snellen(candidate) else { break }  // not an acuity line
                collecting = true
                switch eye {
                case .right: if od == nil { od = value }
                case .left:  if os == nil { os = value }
                }
                cursor += 1
            }

            if od != nil, os != nil { break }
        }

        guard od != nil || os != nil else { return nil }
        return (od, os)
    }

    private enum Eye { case right, left }

    /// The eye an "OD: …" / "OS: …" line reports on, or nil for anything else
    /// (including "OU:", which is binocular and never an eye's own acuity).
    private static func eyeLabelled(_ line: String) -> Eye? {
        if value(after: ["OD:", "O.D.:"], in: line) != nil { return .right }
        if value(after: ["OS:", "O.S.:"], in: line) != nil { return .left }
        return nil
    }

    /// "Distance • Unaided", "Uncorrected VA", "VA (sc)" — a line saying the
    /// acuity below it was measured WITHOUT correction.
    private static func namesUncorrectedCondition(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if ["unaided", "uncorrect", "without correction", "no correction"].contains(where: lowered.contains) {
            return true
        }
        return words(of: lowered).contains("sc")
    }

    /// The opposite: a condition that means the acuity below it was measured
    /// WITH correction. Checked only while looking for values, to stop a
    /// marker from reaching across into the next condition's numbers.
    private static func namesCorrectedCondition(_ line: String) -> Bool {
        let lowered = line.lowercased()
        guard !namesUncorrectedCondition(lowered) else { return false }  // "unaided" ⊃ "aided"
        if ["glasses", "spectacle", "contact", "with correction", "habitual", "aided"]
            .contains(where: lowered.contains) { return true }
        return !words(of: lowered).isDisjoint(with: ["cc", "rx"])
    }

    private static func words(of loweredLine: String) -> Set<String> {
        Set(loweredLine.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    }

    /// The Snellen fraction in a line, spaces squeezed out ("20 / 40" →
    /// "20/40"); nil when the text holds no acuity.
    private static func snellen(_ raw: String) -> String? {
        capture(visualAcuity, in: raw).map { $0.replacingOccurrences(of: " ", with: "") }
    }

    /// Pulls the bare IOP number (e.g. "19") from a line like
    /// "Average: 19 mmHg (8:52)".
    private static func cleanIOP(_ raw: String) -> String? {
        capture(iopReading, in: raw) ?? raw.nilIfEmpty
    }

    /// "39.25 @163° × 40.25 @73°" → "39.25@163/40.25". First axis is padded
    /// to 3 digits; the second axis is dropped. Unrecognized input is kept.
    private static func reformattedKeratometry(_ raw: String) -> String {
        guard let match = keratometryReading.firstMatch(in: raw, range: fullRange(raw)),
              let power1 = Range(match.range(at: 1), in: raw),
              let axis1 = Range(match.range(at: 2), in: raw),
              let power2 = Range(match.range(at: 3), in: raw)
        else { return raw }
        let paddedAxis = Int(raw[axis1]).map { String(format: "%03d", $0) } ?? String(raw[axis1])
        return "\(raw[power1])@\(paddedAxis)/\(raw[power2])"
    }

    /// Finds the first line containing `anchor`, then reads the next OD and OS
    /// values within a few following lines. Returns their trimmed contents.
    /// `requiring`: if set, only OD/OS lines containing this token are
    /// considered (used by IOP to skip non-mmHg rows).
    /// `window`: how many lines after the anchor to search. A section's
    /// preamble varies — IRIS injects its "Printed on … N of M" page footer
    /// mid-section — so this is sized generously where a `requiring` token
    /// makes over-reaching harmless.
    private static func odosValues(afterLineContaining anchor: String,
                                   in lines: [String],
                                   requiring token: String? = nil,
                                   window: Int = 8) -> (od: String, os: String)? {
        guard let start = lines.firstIndex(where: { $0.contains(anchor) }) else { return nil }
        var od: String?
        var os: String?
        for line in lines[(start + 1)...].prefix(window) {
            if let token, !line.contains(token) { continue }
            if od == nil, let value = value(after: ["OD:", "O.D.:"], in: line) { od = value; continue }
            if os == nil, let value = value(after: ["OS:", "O.S.:"], in: line) { os = value }
            if od != nil, os != nil { break }
        }
        guard let od, let os else { return nil }
        return (od, os)
    }

    /// If `line` starts with one of `labels`, returns the trimmed remainder.
    private static func value(after labels: [String], in line: String) -> String? {
        for label in labels where line.hasPrefix(label) {
            return String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces).nilIfEmpty
        }
        return nil
    }

    /// Splits a refraction line like "-2.00 -1.00 × 130° ADD +1.25 20 / 15"
    /// into the sphere/cyl/axis part (ADD dropped) and the bundled Snellen VA
    /// ("20/15").
    private static func splitRefraction(_ raw: String) -> (refraction: String?, visualAcuity: String?) {
        let va = capture(visualAcuity, in: raw).map { $0.replacingOccurrences(of: " ", with: "") }

        var refractionPart = raw
        if let addRange = raw.range(of: "ADD", options: .caseInsensitive) {
            refractionPart = String(raw[..<addRange.lowerBound])
        } else if let vaText = capture(visualAcuity, in: raw), let vaRange = raw.range(of: vaText) {
            refractionPart = String(raw[..<vaRange.lowerBound])
        }
        return (refractionPart.trimmingCharacters(in: .whitespaces).nilIfEmpty, va)
    }

    // MARK: - Name

    /// Surname prefixes that appear as their own word and belong WITH the
    /// surname (e.g. "van der Berg"). Matched case-insensitively.
    private static let surnameParticles: Set<String> = [
        "von", "van", "der", "den", "de", "del", "della", "di", "da", "dos",
        "das", "du", "la", "le", "lo", "los", "las", "ter", "ten", "saint",
        "st", "st.", "af", "av", "bin", "ibn", "al", "el", "abu",
    ]

    /// Splits "First Last" into given name + surname. The surname starts at
    /// the first particle after the given name, or (no particle) at the last
    /// word — so middle names stay with the given name. A one-word name is
    /// treated as a surname (that's what a lone name on a chart is).
    /// Genuinely ambiguous splits ("Anna Maria Rossi") are left for the
    /// clinician to fix in the review sheet.
    ///
    /// The surname comes back UPPER-CASED (particles included), which is how
    /// the renderer prints it — so the review sheet and the patient block show
    /// the same "LAST, First" that will appear on the letter, and the
    /// renderer's own `.uppercased()` becomes a no-op for imported names.
    private static func splitName(_ fullName: String) -> (first: String?, last: String?) {
        let tokens = fullName.split(separator: " ").map(String.init)
        guard let firstToken = tokens.first else { return (nil, nil) }
        guard tokens.count >= 2 else { return (nil, firstToken.uppercased()) }

        let surnameStart = tokens.indices.dropFirst().first {
            surnameParticles.contains(tokens[$0].lowercased())
        } ?? (tokens.count - 1)

        let given = tokens[..<surnameStart].joined(separator: " ")
        let surname = tokens[surnameStart...].joined(separator: " ").uppercased()
        return (given.nilIfEmpty, surname.nilIfEmpty)
    }

    // MARK: - Field patterns

    private static let postalCode = regex(#"^[A-Za-z]\d[A-Za-z]\s?\d[A-Za-z]\d$"#)
    private static let birthDate = regex(#"Birth Date:\s*(\d{4}-\d{2}-\d{2})"#, caseInsensitive: true)
    // Alberta PHN: three groups of three digits (e.g. "999 999 999").
    private static let healthcareNumber = regex(#"\b(\d{3}\s\d{3}\s\d{3})\b"#)
    // Snellen VA bundled in refraction lines, e.g. "20 / 15" or "20 / 15 -1".
    private static let visualAcuity = regex(#"(\d{1,3}\s*/\s*\d{1,3}(?:\s*[+-]\s*\d+)?)"#)
    // IOP reading: captures just the number (e.g. "19") but requires a
    // following "mmHg" so only a real pressure value matches.
    private static let iopReading = regex(#"(\d{1,2}(?:\.\d)?)\s*mmHg"#)
    // Keratometry "power1 @axis1 × power2 @axis2" — groups: power1, axis1, power2.
    private static let keratometryReading = regex(#"([\d.]+)\s*@\s*(\d+)°?\s*[×x]\s*([\d.]+)"#)

    private static func matchesBirthDate(_ s: String) -> Bool {
        birthDate.firstMatch(in: s, range: fullRange(s)) != nil
    }

    private static func firstBirthDate(in s: String) -> String? {
        capture(birthDate, in: s)
    }

    /// IRIS prints DOB as ISO "yyyy-MM-dd"; the model stores year/month/day
    /// (the renderer formats it as "25 DEC 1975"). An impossible date —
    /// "2020-13-45", or "2021-02-30" — yields nil rather than a silently
    /// rolled-over date, so the review sheet simply shows an empty DOB.
    private static func birthComponents(_ iso: String) -> DateComponents? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        let components = DateComponents(year: year, month: month, day: day)
        let calendar = Calendar(identifier: .gregorian)
        // date(from:) happily rolls month 13 into the next January, so the
        // result is round-tripped and compared rather than merely non-nil.
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else { return nil }
        return components
    }

    private static func firstHealthcareNumber(in s: String) -> String? {
        capture(healthcareNumber, in: s)
    }

    /// IRIS prints the Alberta PHN as "### ### ###"; EYEreport's own AHC
    /// field formats to "#####-####" on blur, so imports match it (e.g.
    /// "999 999 999" → "99999-9999"). Anything that isn't exactly 9 digits is
    /// kept verbatim.
    private static func reformattedHealthcareNumber(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 9 else { return raw }
        let split = digits.index(digits.startIndex, offsetBy: 5)
        return "\(digits[..<split])-\(digits[split...])"
    }

    /// Returns the postal code normalized to "A1A 1A1", or nil if the line
    /// isn't a postal code.
    private static func normalizedPostalCode(_ line: String) -> String? {
        guard postalCode.firstMatch(in: line, range: fullRange(line)) != nil else { return nil }
        let compact = line.replacingOccurrences(of: " ", with: "").uppercased()
        guard compact.count == 6 else { return line.uppercased() }
        let mid = compact.index(compact.startIndex, offsetBy: 3)
        return "\(compact[..<mid]) \(compact[mid...])"
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programmer
        // error, so trapping is appropriate.
        try! NSRegularExpression(
            pattern: pattern,
            options: caseInsensitive ? [.caseInsensitive] : []
        )
    }

    private static func fullRange(_ s: String) -> NSRange {
        NSRange(s.startIndex..., in: s)
    }

    private static func capture(_ re: NSRegularExpression, in s: String) -> String? {
        guard let match = re.firstMatch(in: s, range: fullRange(s)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: s)
        else { return nil }
        return String(s[range]).nilIfEmpty
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
