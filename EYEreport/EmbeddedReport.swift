//
//  EmbeddedReport.swift
//  EYEreport
//
//  The invisible round-trip: every PDF the renderer produces carries the
//  full structured `ReportDocument` as JSON in the PDF's Info dictionary.
//  "Import report PDF…" on the New Report chooser reads it back, so a
//  previously exported report reopens in the editor with PERFECT fidelity —
//  no text scraping, no layout guessing. (Chosen over parsing the visible
//  text, which was rejected as silently error-prone; the vault remains the
//  planned long-term home for reopening past reports.)
//
//  The payload is the same PHI the PDF shows visibly — no new exposure.
//  Caveats, by design: only PDFs exported AFTER this feature ships carry
//  the payload, and an intermediary that REWRITES the PDF (some EMR
//  pipelines, PDF optimizers) may strip the Info dictionary.
//

import Foundation
import CoreGraphics

enum EmbeddedReport {
    /// The payload lives in the DOCUMENTED "Keywords" Info key, marked by a
    /// versioned prefix. CGPDFContext silently DROPS custom Info-dictionary
    /// keys (verified empirically — a custom key never reached the file;
    /// Keywords and Subject round-tripped fine, including a 120KB value),
    /// so a documented key is the only reliable carrier.
    static let infoKey = "Keywords"
    static let payloadPrefix = "EYEreport1:"

    /// The prefixed base64 payload for the renderer's `documentInfo`. nil if
    /// encoding ever fails — the PDF then simply renders without a payload.
    static func payload(for document: ReportDocument) -> String? {
        guard let json = try? JSONEncoder().encode(document) else { return nil }
        return payloadPrefix + json.base64EncodedString()
    }

    /// The embedded document, or nil when the data isn't a PDF, carries no
    /// payload (foreign/pre-feature PDF), or fails to decode.
    static func document(from pdfData: Data) -> ReportDocument? {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let pdf = CGPDFDocument(provider),
              let info = pdf.info else { return nil }

        var stringRef: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, infoKey, &stringRef),
              let stringRef,
              let text = CGPDFStringCopyTextString(stringRef) as String?,
              text.hasPrefix(payloadPrefix),
              let json = Data(base64Encoded: String(text.dropFirst(payloadPrefix.count))),
              let document = try? JSONDecoder().decode(ReportDocument.self, from: json)
        else { return nil }
        return document
    }
}
