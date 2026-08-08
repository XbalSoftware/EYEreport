//
//  AppBackup.swift
//  EYEreport
//
//  One-file backup/restore of the entire BACKED-UP store: templates,
//  practitioner profile (name, credentials, ID, signature image),
//  letterheads (PDFs + calibrated safe zones), the provider directory, and
//  the sticky letterhead selection. Exported/imported from Settings →
//  BACKUP as a Files-app JSON — the quick-restore path around app reset or
//  a fresh install.
//
//  NO PHI, by design: the encrypted draft (and the future vault) are
//  deliberately excluded — a backup file lives outside the app's privacy
//  guarantees.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

nonisolated struct AppBackup: Codable {
    /// Bumped if the shape ever changes incompatibly; import currently
    /// accepts anything that decodes.
    var version: Int = 1
    var exportedAt: Date = Date()

    var templates: [ReportDocument] = []
    var profile: PractitionerProfile = PractitionerProfile()
    var letterheads: [Letterhead] = []
    var providers: [Provider] = []
    /// The sticky Preview letterhead, restored only if that letterhead is
    /// in the backup.
    var activeLetterheadID: UUID? = nil
}

/// Minimal FileDocument wrapper for `.fileExporter` (same pattern as
/// PreviewView's PDFExportDocument). Reading back through this type is
/// never used — import goes through `.fileImporter` + JSONDecoder.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let backup: AppBackup

    init(backup: AppBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        backup = try JSONDecoder().decode(AppBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(backup))
    }
}
