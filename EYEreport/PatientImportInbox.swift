//
//  PatientImportInbox.swift
//  EYEreport
//
//  Receives a PDF opened or shared into the app from elsewhere (the EMR's
//  Share sheet, Files, AirDrop) and works out what it is:
//
//    1. an EYEreport export  → the embedded ReportDocument, reopened whole
//    2. an IRIS patient PDF  → parsed demographics, held for the next report
//    3. anything else        → a plain "couldn't read that" message
//
//  Order matters: our own exports also contain readable patient text, so the
//  embedded payload is checked FIRST or a reopened report would be reduced to
//  a handful of scraped fields.
//
//  PHI hygiene: the app does NOT declare in-place opening, so iOS always
//  stages a COPY in Documents/Inbox — this class deletes that copy as soon as
//  it has read it. Nothing parsed here is written to disk; values reach
//  storage only once applied into the working report, via the encrypted
//  draft, exactly like hand-typed data.
//

import Foundation
import Combine

final class PatientImportInbox: ObservableObject {

    /// Patient details waiting for a report to receive them. In-memory only.
    @Published var pendingPatient: PatientDemographics?

    /// A previously exported report, shared back in to be reopened.
    @Published var pendingReport: ReportDocument?

    /// One-shot message when a shared PDF was neither of the above.
    @Published var failureMessage: String?

    /// Handles a PDF opened/shared into the app.
    func receive(pdfAt url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            deleteInboxCopy(url)
        }

        // 1 — one of our own exported reports?
        if let data = try? Data(contentsOf: url),
           var document = EmbeddedReport.document(from: data) {
            // Same rules as "Import report PDF…": an exact copy, fresh
            // identity only (no volatile clearing — user decision).
            document.id = UUID()
            document.templateName = nil
            document.createdAt = Date()
            document.modifiedAt = Date()
            pendingReport = document
            return
        }

        // 2 — an IRIS patient PDF?
        if let demographics = PatientDemographicsParser.demographics(fromPDFAt: url) {
            pendingPatient = demographics
            return
        }

        // 3 — neither.
        failureMessage = "No patient details could be read from that PDF, and it isn't a report exported by EYEreport."
    }

    /// Removes the file only if it's the copy iOS staged in our Documents/
    /// Inbox (we don't declare in-place opening, so shares always land
    /// there). Never deletes a file outside our own inbox — a Files-app pick
    /// points at the user's own document and must be left alone.
    private func deleteInboxCopy(_ url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox").standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
