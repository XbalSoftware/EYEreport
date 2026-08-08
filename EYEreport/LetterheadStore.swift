//
//  LetterheadStore.swift
//  EYEreport
//

import Foundation
import Combine

/// The user's STICKY letterhead choice for Preview. `.plain` is the explicit
/// "None (plain)" pick — distinct from "never chosen" (a nil selection),
/// which falls back to the first stored letterhead.
enum LetterheadSelection: Equatable {
    case plain
    case letterhead(Letterhead.ID)
}

final class LetterheadStore: ObservableObject {
    @Published private(set) var letterheads: [Letterhead] = []

    /// Sticky Preview default: seeded into every Preview and written back on
    /// every letterhead pick there; Settings shows it as radio buttons.
    /// Persisted in UserDefaults (a UI preference, not document data —
    /// letterheads.json's [Letterhead] shape stays untouched).
    @Published var activeSelection: LetterheadSelection? {
        didSet { saveActiveSelection() }
    }

    private static let activeSelectionKey = "activeLetterheadSelection"

    private let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EYEreport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("letterheads.json")
    }()

    init() {
        load()
        loadActiveSelection()
    }

    func add(_ letterhead: Letterhead) {
        letterheads.append(letterhead)
        save()
    }

    func update(_ letterhead: Letterhead) {
        guard let idx = letterheads.firstIndex(where: { $0.id == letterhead.id }) else { return }
        var updated = letterhead
        updated.modifiedAt = Date()
        letterheads[idx] = updated
        save()
    }

    func delete(_ letterhead: Letterhead) {
        delete(id: letterhead.id)
    }

    func delete(id: UUID) {
        letterheads.removeAll { $0.id == id }
        // Deleting the active letterhead clears the selection back to
        // "never chosen" — Preview then falls back to the first remaining.
        if activeSelection == .letterhead(id) {
            activeSelection = nil
        }
        save()
    }

    /// Removes every letterhead (app reset).
    func removeAll() {
        letterheads = []
        activeSelection = nil
        save()
    }

    /// Backup restore: wholesale replacement, ids kept. The caller decides
    /// what the active selection becomes (the backup may carry one).
    func replaceAll(_ newLetterheads: [Letterhead]) {
        letterheads = newLetterheads
        if case .letterhead(let id) = activeSelection,
           !letterheads.contains(where: { $0.id == id }) {
            activeSelection = nil
        }
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([Letterhead].self, from: data) else {
            letterheads = []
            return
        }
        letterheads = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(letterheads) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: Active-selection persistence (UserDefaults)

    /// Absent key = never chosen; "none" = the explicit plain pick; a UUID
    /// string = that letterhead (dropped back to "never chosen" if it no
    /// longer exists).
    private func loadActiveSelection() {
        guard let raw = UserDefaults.standard.string(forKey: Self.activeSelectionKey) else {
            activeSelection = nil
            return
        }
        if raw == "none" {
            activeSelection = .plain
        } else if let id = UUID(uuidString: raw),
                  letterheads.contains(where: { $0.id == id }) {
            activeSelection = .letterhead(id)
        } else {
            activeSelection = nil
        }
    }

    private func saveActiveSelection() {
        let defaults = UserDefaults.standard
        switch activeSelection {
        case nil:
            defaults.removeObject(forKey: Self.activeSelectionKey)
        case .plain:
            defaults.set("none", forKey: Self.activeSelectionKey)
        case .letterhead(let id):
            defaults.set(id.uuidString, forKey: Self.activeSelectionKey)
        }
    }
}
