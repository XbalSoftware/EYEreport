//
//  SettingsView.swift
//  EYEreport
//
//  Practitioner profile: name, credentials, practitioner ID, and the
//  handwritten signature (drawn in SignatureCaptureView). Everything binds
//  straight to PractitionerProfileStore.profile, which saves on change.
//  The renderer's signature block resolves against this profile.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var profileStore: PractitionerProfileStore
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var letterheadStore: LetterheadStore
    @EnvironmentObject private var draftStore: DraftStore
    @EnvironmentObject private var providerStore: ProviderStore
    @State private var isSigning = false
    @State private var showingResetConfirmation = false
    @State private var importingLetterhead = false
    @State private var letterheadPendingDeletion: Letterhead?
    @State private var importingSignature = false
    @State private var showingRemoveSignatureConfirmation = false
    @State private var exportingBackup = false
    @State private var importingBackup = false
    /// Decoded backup held while the replace-everything confirmation shows.
    @State private var pendingBackup: AppBackup?
    @State private var showingBackupImportError = false

    private let labelColumnWidth: CGFloat = 190

    var body: some View {
        NavigationStack {
            Form {
                Section(header: sectionHeader("Practitioner")) {
                    labeledField("Name", placeholder: "",
                                 text: $profileStore.profile.name)
                    labeledField("Credentials", placeholder: "",
                                 text: $profileStore.profile.credentials)
                    labeledField("Practitioner ID", placeholder: "",
                                 text: $profileStore.profile.practitionerID)
                }

                Section(header: sectionHeader("Signature")) {
                    signatureSection
                }

                Section(header: sectionHeader("Letterheads")) {
                    letterheadsSection
                }

                Section(header: sectionHeader("Providers")) {
                    providersSection
                }

                Section(header: sectionHeader("About")) {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About EYEreport", systemImage: "info.circle")
                    }
                }

                Section(header: sectionHeader("Backup")) {
                    backupSection
                }

                Section(header: sectionHeader("Reset")) {
                    Button("Reset App to Defaults", role: .destructive) {
                        showingResetConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $isSigning) {
            SignatureCaptureView { data in
                profileStore.profile.signatureImageData = data
            }
        }
        .fileImporter(
            isPresented: $importingLetterhead,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleLetterheadImport(result)
        }
        .alert("Delete this letterhead?",
               isPresented: Binding(
                   get: { letterheadPendingDeletion != nil },
                   set: { if !$0 { letterheadPendingDeletion = nil } }),
               presenting: letterheadPendingDeletion) { letterhead in
            Button("Delete", role: .destructive) { letterheadStore.delete(letterhead) }
            Button("Cancel", role: .cancel) { }
        } message: { letterhead in
            Text("\"\(letterhead.name)\" and its calibrated safe zone will be removed.")
        }
        .alert("Import backup?",
               isPresented: Binding(
                   get: { pendingBackup != nil },
                   set: { if !$0 { pendingBackup = nil } }),
               presenting: pendingBackup) { backup in
            Button("Replace Everything", role: .destructive) {
                applyBackup(backup)
                pendingBackup = nil
            }
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: { backup in
            Text("This replaces all current data with the backup's contents: \(backup.templates.count) template(s), \(backup.letterheads.count) letterhead(s), \(backup.providers.count) provider(s), and the practitioner profile.")
        }
        .alert("Couldn't read backup", isPresented: $showingBackupImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("That file isn't a valid EYEreport backup.")
        }
        .alert("Reset app to defaults?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) { resetApp() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes ALL templates (only the built-in Standard Referral is restored), all letterheads, all saved providers, and the practitioner profile including the signature. Export a backup first (Settings → Backup) if you want a restore point.")
        }
    }

    // MARK: - Letterheads (inline — no click-through screen)

    /// The letterhead list + import, directly on the Settings page: each row
    /// pushes the safe-zone editor; the trash asks first (a letterhead
    /// carries its calibrated safe zone).
    @ViewBuilder
    private var letterheadsSection: some View {
        if letterheadStore.letterheads.isEmpty {
            Text("No letterheads imported — import your office letterhead PDF.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        ForEach(letterheadStore.letterheads) { letterhead in
            HStack(spacing: 6) {
                // Radio: which letterhead Preview opens on (the sticky
                // app-wide active selection; Preview picks write it too).
                Button {
                    letterheadStore.activeSelection = .letterhead(letterhead.id)
                } label: {
                    Image(systemName:
                        letterheadStore.activeSelection == .letterhead(letterhead.id)
                            ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(
                            letterheadStore.activeSelection == .letterhead(letterhead.id)
                                ? Color.accentColor : Color.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                NavigationLink {
                    SafeZoneEditorView(letterhead: letterhead, store: letterheadStore)
                } label: {
                    HStack {
                        Text(letterhead.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    letterheadPendingDeletion = letterhead
                } label: {
                    Image(systemName: "trash")
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }

        if !letterheadStore.letterheads.isEmpty {
            Text("The selected letterhead is what Preview opens with; picking one inside Preview moves the selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Button {
            importingLetterhead = true
        } label: {
            Label("Import letterhead PDF…", systemImage: "plus")
        }
    }

    private func handleLetterheadImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  PDFDocument(data: data) != nil else { return }
            let name = url.deletingPathExtension().lastPathComponent
            letterheadStore.add(Letterhead(name: name, pdfData: data))
        case .failure:
            break
        }
    }

    // MARK: - Providers (count + link; the editable list lives on
    // ManageProvidersView, pushed — keeps Settings uncluttered)

    @ViewBuilder
    private var providersSection: some View {
        Text(providerStore.providers.count == 1
             ? "1 saved provider"
             : "\(providerStore.providers.count) saved providers")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        NavigationLink {
            ManageProvidersView()
        } label: {
            Label("Manage providers…", systemImage: "person.2")
        }
    }

    // MARK: - Backup (whole backed-up store, one Files-app JSON)

    /// Export/import of everything the backed-up store holds — templates,
    /// profile + signature, letterheads + safe zones, providers, the sticky
    /// letterhead choice. NO patient data (the draft is deliberately
    /// excluded). Import REPLACES current data after confirmation.
    @ViewBuilder
    private var backupSection: some View {
        Text("One file with all templates, letterheads, providers, and the practitioner profile including the signature. No patient data is included.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        // BOTH buttons MUST carry .buttonStyle(.borderless) — same rule the
        // letterhead row follows. Two buttons in one Form/List row with the
        // default style are treated as ONE tappable row, so a tap runs BOTH
        // actions: tapping "Import backup…" also set exportingBackup, the
        // save panel (declared first) appeared, and the importer only showed
        // once that was dismissed. It looked like a fileExporter/fileImporter
        // collision; it is the row-tap-dispatch lesson in CLAUDE.md.
        HStack(spacing: 16) {
            Button {
                exportingBackup = true
            } label: {
                Label("Export backup…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .fileExporter(isPresented: $exportingBackup,
                          document: BackupDocument(backup: currentBackup),
                          contentType: .json,
                          defaultFilename: backupFilename) { _ in }

            Button {
                importingBackup = true
            } label: {
                Label("Import backup…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .fileImporter(
                isPresented: $importingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleBackupImport(result)
            }
        }
    }

    private var currentBackup: AppBackup {
        var activeID: UUID?
        if case .letterhead(let id) = letterheadStore.activeSelection {
            activeID = id
        }
        return AppBackup(templates: templateStore.templates,
                         profile: profileStore.profile,
                         letterheads: letterheadStore.letterheads,
                         providers: providerStore.providers,
                         activeLetterheadID: activeID)
    }

    private var backupFilename: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "EYEreport backup \(df.string(from: Date()))"
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(AppBackup.self, from: data) else {
            showingBackupImportError = true
            return
        }
        pendingBackup = backup
    }

    /// The restore: wholesale replacement of every backed-up store. The
    /// draft is untouched (it isn't part of a backup).
    private func applyBackup(_ backup: AppBackup) {
        templateStore.replaceAll(backup.templates)
        letterheadStore.replaceAll(backup.letterheads)
        profileStore.profile = backup.profile
        providerStore.providers = backup.providers
        if let id = backup.activeLetterheadID,
           backup.letterheads.contains(where: { $0.id == id }) {
            letterheadStore.activeSelection = .letterhead(id)
        } else {
            letterheadStore.activeSelection = nil
        }
    }

    /// First-launch state: seed templates only, no letterheads, default
    /// profile. Saved template EXPORTS (Files) are untouched — that's the
    /// restore path.
    private func resetApp() {
        templateStore.resetToDefaults()
        letterheadStore.removeAll()
        profileStore.profile = PractitionerProfile()
        draftStore.clear()
        providerStore.removeAll()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .blockTitleStyle()
            .textCase(nil)
    }

    private func labeledField(_ label: String, placeholder: String,
                              text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.title2)
                .foregroundStyle(.primary.opacity(0.75))
                .frame(width: labelColumnWidth, alignment: .leading)
            SelectAllTextField(placeholder: placeholder, text: text)
                .frame(height: standardFieldHeight)
        }
    }

    @ViewBuilder
    private var signatureSection: some View {
        if let data = profileStore.profile.signatureImageData,
           let image = UIImage(data: data) {
            // White backing: the stored ink is black on transparent, exactly
            // as it will stamp onto the letterhead paper.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 110, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 1)
                )
        } else {
            Text("No signature on file — reports print without one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 16) {
            Button(profileStore.profile.signatureImageData == nil ? "Sign…" : "Re-sign…") {
                isSigning = true
            }

            // Attached to this button (not the shared outer chain) so it
            // can't collide with the letterheads fileImporter.
            Button("Import from file…") {
                importingSignature = true
            }
            .fileImporter(
                isPresented: $importingSignature,
                allowedContentTypes: [.png, .jpeg],
                allowsMultipleSelection: false
            ) { result in
                handleSignatureImport(result)
            }

            if profileStore.profile.signatureImageData != nil {
                Button("Remove signature", role: .destructive) {
                    showingRemoveSignatureConfirmation = true
                }
                .alert("Remove signature?", isPresented: $showingRemoveSignatureConfirmation) {
                    Button("Remove", role: .destructive) {
                        profileStore.profile.signatureImageData = nil
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Reports will print without a signature until you sign or import a new one.")
                }
            }
        }
    }

    /// Import a signature image (.png / .jpg). Downscaled to a sane size and
    /// re-encoded as PNG — the profile stores the bytes inline and the
    /// renderer prints at ~44pt, so megapixel scans are wasted weight. PNG
    /// transparency survives; a JPEG keeps its white background, which is
    /// invisible on white paper. Drawing through UIImage also bakes in EXIF
    /// orientation from photographed signatures.
    private func handleSignatureImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data),
              image.size.width > 0, image.size.height > 0 else { return }

        let maxDimension: CGFloat = 1200
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale,
                          height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let png = normalized.pngData() {
            profileStore.profile.signatureImageData = png
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PractitionerProfileStore())
        .environmentObject(TemplateStore())
        .environmentObject(LetterheadStore())
        .environmentObject(DraftStore())
        .environmentObject(ProviderStore())
}
