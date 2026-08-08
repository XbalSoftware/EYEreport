//
//  PractitionerProfileStore.swift
//  EYEreport
//
//  The practitioner identity (name, credentials, ID, signature image) lives
//  in the BACKED-UP store — no patient data — alongside templates and
//  letterheads: Application Support/EYEreport/profile.json. One profile per
//  install; the renderer resolves the signature block against it.
//

import Foundation
import Combine

final class PractitionerProfileStore: ObservableObject {
    /// Saved on every change (Settings binds fields straight to this).
    @Published var profile: PractitionerProfile {
        didSet { save() }
    }

    private let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EYEreport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }()

    init() {
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode(PractitionerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = PractitionerProfile()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
