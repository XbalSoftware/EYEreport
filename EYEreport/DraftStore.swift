//
//  DraftStore.swift
//  EYEreport
//

import Foundation
import SwiftUI
import Combine
import CryptoKit
import Security

/// The persisted in-progress report: the working document PLUS its
/// ModifiedTextGuard baseline, so resuming a draft restores deletion
/// warnings exactly as they were mid-session.
struct ReportDraft: Codable {
    var document: ReportDocument
    var baseline: ReportDocument
    var savedAt: Date
}

/// Auto-saves the SINGLE active draft so a half-filled report survives an app
/// quit. Exactly one draft ever exists; starting a new report replaces it and
/// Start Over deletes it.
///
/// Privacy: a draft contains PHI, so this is a mini vault of one — the payload
/// is sealed with CryptoKit AES.GCM before it touches disk, the 256-bit key
/// lives in the Keychain (this-device-only, no iCloud sync), and the sealed
/// file is excluded from backup. Unlike the full vault design there is NO
/// user-presence gate: restore is silent on relaunch, by user decision — the
/// draft is a crash/quit safety net, not an archive.
final class DraftStore: ObservableObject {
    @Published private(set) var draft: ReportDraft?

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("EYEreport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("draft.sealed")
    }()

    /// Last plaintext written (document + baseline only, savedAt excluded) —
    /// lets the periodic autosave tick skip the write when nothing changed.
    private var lastSnapshot: Data?

    private lazy var key: SymmetricKey = Self.loadOrCreateKey()

    init() {
        load()
    }

    /// Saves the working session, overwriting any previous draft. Called on a
    /// timer while editing and when the scene leaves the foreground; cheap
    /// no-op when the document and baseline are unchanged since the last write.
    func autosave(document: ReportDocument, baseline: ReportDocument) {
        let payload = ReportDraft(document: document, baseline: baseline, savedAt: Date())
        // Compare on a savedAt-free encoding so an unchanged session doesn't
        // rewrite (and republish) every tick.
        guard let snapshot = try? Self.encoder.encode([document, baseline]) else { return }
        if snapshot == lastSnapshot { return }

        guard let plaintext = try? Self.encoder.encode(payload),
              let sealed = try? AES.GCM.seal(plaintext, using: key).combined else { return }
        do {
            try sealed.write(to: fileURL, options: [.atomic])
        } catch {
            return
        }
        excludeFromBackup()
        // Defense-in-depth only — AES.GCM is the guarantee, not OS protection.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: fileURL.path)
        lastSnapshot = snapshot
        draft = payload
    }

    /// Deletes the draft (Start Over, replace-with-new, app reset).
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        lastSnapshot = nil
        draft = nil
    }

    private func load() {
        guard let sealed = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plaintext = try? AES.GCM.open(box, using: key),
              let payload = try? JSONDecoder().decode(ReportDraft.self, from: plaintext) else {
            // Missing, corrupt, or key mismatch: no draft. The file (if any)
            // stays put and is simply overwritten by the next autosave.
            draft = nil
            return
        }
        lastSnapshot = try? Self.encoder.encode([payload.document, payload.baseline])
        draft = payload
    }

    private func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// sortedKeys makes repeat encodings of the same value byte-identical, so
    /// the unchanged-snapshot comparison doesn't false-positive on dictionary
    /// key order (fieldLabels).
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: Keychain-held encryption key

    private static let keychainService = "com.eyereport.draft-key"
    private static let keychainAccount = "draft"

    /// Fetches the draft key, generating and storing one on first use.
    /// AfterFirstUnlockThisDeviceOnly: readable for a background autosave,
    /// never synced or restored to another device — losing the device loses
    /// the draft, which is the point.
    private static func loadOrCreateKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
        return key
    }
}
