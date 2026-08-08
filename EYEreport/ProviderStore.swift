//
//  ProviderStore.swift
//  EYEreport
//
//  The provider directory: regularly-used referral recipients (name + fax).
//  Reference data, no PHI — lives in the BACKED-UP store alongside templates
//  and the profile: Application Support/EYEreport/providers.json. Managed in
//  Settings; the recipient editor offers type-ahead suggestions from it and
//  can save the currently-typed recipient into it.
//

import Foundation
import Combine

/// One directory entry. `fax` is stored as displayed (formatted on blur by
/// the usual digit-snap), so recipient fill-in and equality checks are
/// straight string operations.
struct Provider: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var fax: String = ""
}

final class ProviderStore: ObservableObject {
    /// Saved on every change (Settings binds row fields straight into this).
    /// Insertion order is display order — deliberately NOT auto-sorted, so a
    /// row can't jump out from under the user mid-rename.
    @Published var providers: [Provider] {
        didSet { save() }
    }

    private let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EYEreport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("providers.json")
    }()

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([Provider].self, from: data) {
            providers = decoded
        } else {
            providers = []
        }
    }

    func add(_ provider: Provider) {
        providers.append(provider)
    }

    /// In-place update — the row keeps its position (display order is
    /// insertion order).
    func update(id: UUID, name: String, fax: String) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        providers[index].name = name
        providers[index].fax = fax
    }

    func delete(id: UUID) {
        providers.removeAll { $0.id == id }
    }

    func removeAll() {
        providers = []
    }

    /// The saved provider with this display name, if any (case-insensitive,
    /// whitespace-trimmed) — drives the recipient editor's add-vs-update
    /// choice for its "save this provider" affordance.
    func provider(named name: String) -> Provider? {
        let query = name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return nil }
        return providers.first {
            $0.name.trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare(query) == .orderedSame
        }
    }

    /// Type-ahead matches for a partial name: prefix matches rank ahead of
    /// mid-string matches, stored order breaks ties. Empty query = no
    /// suggestions (the editor shows them only while the user is typing).
    func suggestions(for query: String) -> [Provider] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let hits = providers.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        return hits.sorted { a, b in
            let aPrefix = a.name.lowercased().hasPrefix(trimmed.lowercased())
            let bPrefix = b.name.lowercased().hasPrefix(trimmed.lowercased())
            if aPrefix != bPrefix { return aPrefix }
            // Stable: keep stored order within the same rank.
            guard let ai = providers.firstIndex(of: a),
                  let bi = providers.firstIndex(of: b) else { return false }
            return ai < bi
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
