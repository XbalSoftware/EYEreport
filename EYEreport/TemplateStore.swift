//
//  TemplateStore.swift
//  EYEreport
//

import Foundation
import SwiftUI
import Combine

final class TemplateStore: ObservableObject {
    @Published private(set) var templates: [ReportDocument] = []

    private let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EYEreport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("templates.json")
    }()

    init() {
        load()
    }

    func add(_ template: ReportDocument) {
        templates.append(template)
        save()
    }

    func delete(at offsets: IndexSet) {
        templates.remove(atOffsets: offsets)
        save()
    }

    /// Reorders templates (list drag). Array order IS the display order —
    /// here and in the New Report chooser — and persists like everything else.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        templates.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Renames a template. `templateName` must stay non-nil (nil is what
    /// distinguishes a report from a template), so an empty name is ignored
    /// at the call site.
    func rename(id: UUID, to name: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].templateName = name
        templates[index].modifiedAt = Date()
        save()
    }

    /// Appends templates from an export file. Each gets a FRESH id so
    /// re-importing an earlier export can never id-collide with what's
    /// already here (it shows up as a duplicate the user can delete).
    func importTemplates(_ imported: [ReportDocument]) {
        for template in imported {
            var copy = template
            copy.id = UUID()
            templates.append(copy)
        }
        save()
    }

    /// Backup restore: wholesale replacement. Unlike `importTemplates`
    /// (append with fresh ids, for merging a colleague's export), a restore
    /// keeps the backup's ids as-is.
    func replaceAll(_ newTemplates: [ReportDocument]) {
        templates = newTemplates
        save()
    }

    /// Back to first-launch state: exactly the built-in seed templates.
    func resetToDefaults() {
        templates = Presets.all
        save()
    }

    private func load() {
        // First launch (no store file yet): seed the built-in templates and
        // persist immediately, so this seeding happens exactly once. After this,
        // the built-ins are ordinary templates (user-deletable, no re-seed).
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            templates = Presets.all
            save()
            return
        }
        // File exists but is unreadable/corrupt: leave empty rather than
        // clobbering with a fresh seed.
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([ReportDocument].self, from: data) else {
            templates = []
            return
        }
        templates = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
