//
//  NewReportView.swift
//  EYEreport
//

import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers

struct NewReportView: View {
    @EnvironmentObject private var templateStore: TemplateStore
    @EnvironmentObject private var letterheadStore: LetterheadStore
    @EnvironmentObject private var profileStore: PractitionerProfileStore
    @EnvironmentObject private var draftStore: DraftStore
    @EnvironmentObject private var importInbox: PatientImportInbox
    @Environment(\.scenePhase) private var scenePhase
    @State private var document = ReportDocument()
    /// The document as the session STARTED (template copy or blank) — the
    /// reference for "has typed text been modified?" deletion warnings.
    @State private var baseline = ReportDocument()
    @State private var isEditing = false
    @State private var previewPayload: PreviewPayload?
    @State private var showingSaveTemplate = false
    @State private var newTemplateName = ""
    @State private var showingSavedConfirmation = false
    @State private var showingStartOverWarning = false
    /// Chooser tap stashed while the "replace saved draft?" warning shows.
    @State private var pendingNewDocument: ReportDocument?
    @State private var showingReplaceDraftWarning = false
    @State private var templateSearch = ""
    @State private var importingReportPDF = false
    @State private var showingPDFImportError = false
    /// Parsed patient details awaiting the clinician's review. Presented per
    /// import via `.sheet(item:)` so the sheet always shows that parse.
    @State private var patientReview: PatientReviewPayload?
    @State private var importingPatientPDF = false
    @StateObject private var keyboard = KeyboardOverlapObserver()

    /// Periodic autosave while editing. The tick is cheap when nothing
    /// changed (DraftStore compares an encoded snapshot before writing).
    private let autosaveTick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            // The patient-import surface (picker, review sheet, alert, inbox
            // watchers) is attached here rather than to the NavigationStack:
            // the stack already carries five alerts and the preview sheet, and
            // a second `.sheet` on the same view is unreliable.
            patientImportSurface(mainContent)
                .navigationTitle("New Report")
        }
        // MUST sit on the NavigationStack itself: the keyboard safe area is
        // applied at the navigation container's hosting view, so an
        // ignoresSafeArea INSIDE the stack (ZStack level — kept as
        // belt-and-braces) has no effect there. Without this, the pinned
        // finish bar lifts whenever a field is focused. Cost: the chooser's
        // search-results list no longer shrinks above the keyboard either —
        // acceptable (searching filters the list short).
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("Save as Template", isPresented: $showingSaveTemplate) {
            TextField("Template name", text: $newTemplateName)
            Button("Cancel", role: .cancel) { }
            Button("Save") { saveAsTemplate() }
        }
        .alert("Saved to Templates", isPresented: $showingSavedConfirmation) {
            Button("OK", role: .cancel) { }
        }
        .alert("Start over?", isPresented: $showingStartOverWarning) {
            Button("Start Over", role: .destructive) {
                isEditing = false
                draftStore.clear()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You are about to discard text that has been modified. Changes will be lost.")
        }
        .alert("Can't reopen this PDF", isPresented: $showingPDFImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Only PDFs exported by EYEreport (after the reopen feature was added) carry the data needed to rebuild the report. This file doesn't have it.")
        }
        .alert("Replace saved draft?", isPresented: $showingReplaceDraftWarning) {
            Button("Replace", role: .destructive) {
                if let doc = pendingNewDocument {
                    beginEditing(doc)
                }
                pendingNewDocument = nil
            }
            Button("Cancel", role: .cancel) { pendingNewDocument = nil }
        } message: {
            Text("Your saved draft has unsaved changes. Starting a new report will discard it.")
        }
        .onReceive(autosaveTick) { _ in
            // Skipped while Preview is up: the document can't be edited
            // there, and the tick's encode-and-compare is main-thread work
            // that a presented share extension pays for. Leaving the sheet,
            // and any scenePhase change, still autosaves.
            if isEditing && previewPayload == nil {
                draftStore.autosave(document: document, baseline: baseline)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Quit/app-switch: capture the session immediately rather than
            // waiting for the next tick.
            if phase != .active && isEditing {
                draftStore.autosave(document: document, baseline: baseline)
            }
        }
        .sheet(item: $previewPayload) { payload in
            PreviewView(document: payload.document,
                        onFontSizeChange: { document.bodyFontSize = $0 })
                .environmentObject(letterheadStore)
                .environmentObject(profileStore)
        }
        // While Preview (and the Print / Share / Save panels it presents) is
        // up, this screen is covered: freeze the keyboard-overlap publisher
        // and the autosave tick so nothing rebuilds the hierarchy — and so
        // nothing re-renders the preview PDF — behind a share extension that
        // is trying to take hardware-keyboard input.
        .onChange(of: previewPayload != nil) { _, showing in
            keyboard.isSuspended = showing
        }
    }

    /// The screen itself: the block editor while a session is open, otherwise
    /// the chooser. (Factored out of `body` so the patient-import modifiers
    /// can wrap it — see the comment at the call site.)
    @ViewBuilder
    private var mainContent: some View {
        if isEditing {
            // The finish bar is a ZStack overlay pinned to the SCREEN
            // bottom. SwiftUI's KEYBOARD safe area is ignored for the
            // WHOLE subtree (child-level opt-out does not work — the
            // inset is applied above the ZStack — and the safe-area
            // route floats the bar on stale/phantom keyboard heights;
            // see LESSONS). Scroll room over the keyboard is restored
            // manually: the clear spacer inset grows to the UIKit-
            // reported keyboard overlap, which is notification-driven
            // and immune to the phantom heights.
            ZStack(alignment: .bottom) {
                ReportEditorView(document: $document, baseline: baseline)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color.clear
                            .frame(height: max(Self.finishBarHeight, keyboard.overlap))
                    }
                finishBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Start Over") {
                        if ModifiedText.hasModifiedText(document, against: baseline) {
                            showingStartOverWarning = true
                        } else {
                            isEditing = false
                            draftStore.clear()
                        }
                    }
                }
                // A fixed spacer breaks the two into separate toolbar capsules
                // (iOS 26 groups adjacent items into one pill by default, so
                // Start Over and Patient details render fused). Guarded: the
                // API is iOS 26-only and this target deploys to 17.6, where
                // the grouping doesn't happen anyway.
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .navigationBarLeading)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        importingPatientPDF = true
                    } label: {
                        Label("Patient details", systemImage: "person.text.rectangle")
                    }
                }
            }
            // Mounted only while editing, so it can never coexist with the
            // chooser's two importers (see patientImportSurface).
            .fileImporter(
                isPresented: $importingPatientPDF,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handlePatientPDFImport(result)
            }
        } else {
            chooserList
        }
    }

    // MARK: - Patient-detail import

    /// Everything the patient-PDF import needs, in one place: the file
    /// picker, the review sheet, the "couldn't read it" alert, and the two
    /// watchers on the shared-in inbox.
    /// NOTE: the patient file picker is deliberately NOT here. Two
    /// `.fileImporter`s in one hierarchy collide — and this view wraps the
    /// chooser, which already carries the "Import report PDF…" importer on
    /// its own button. An importer here silently swallowed that one (the
    /// button did nothing at all). Each importer now sits in its own
    /// mutually-exclusive branch of `mainContent`; only ever one is mounted.
    private func patientImportSurface(_ content: some View) -> some View {
        content
            .sheet(item: $patientReview) { payload in
                DemographicsReviewSheet(
                    demographics: payload.demographics,
                    outcome: payload.outcome,
                    onApply: { details in
                        applyPatientDetails(details)
                        patientReview = nil
                    },
                    onCancel: { patientReview = nil }
                )
            }
            .alert("Can't read that PDF", isPresented: patientImportFailureBinding) {
                Button("OK", role: .cancel) { importInbox.failureMessage = nil }
            } message: {
                Text(importInbox.failureMessage ?? "")
            }
            // A patient PDF shared in while a report is already open.
            .onChange(of: importInbox.pendingPatient) { _, _ in consumePendingPatient() }
            // One of our own exported reports, shared back in — reopen it.
            .onChange(of: importInbox.pendingReport?.id) { _, _ in consumePendingReport() }
    }

    private var patientImportFailureBinding: Binding<Bool> {
        Binding(
            get: { importInbox.failureMessage != nil },
            set: { if !$0 { importInbox.failureMessage = nil } }
        )
    }

    /// A picked patient PDF. While a report is open the review sheet appears
    /// straight away; at the chooser the details are HELD until a template is
    /// picked, so the clinician still chooses which letter to write.
    private func handlePatientPDFImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let details = PatientDemographicsParser.demographics(fromPDFAt: url) else {
            importInbox.failureMessage = "No patient details could be read from that PDF. It needs to be a file excerpt or exam report exported from IRIS."
            return
        }
        if isEditing {
            presentReview(for: details)
        } else {
            importInbox.pendingPatient = details
        }
    }

    /// Takes the shared-in details once a report is open to receive them.
    private func consumePendingPatient() {
        guard isEditing, let pending = importInbox.pendingPatient else { return }
        importInbox.pendingPatient = nil
        presentReview(for: pending)
    }

    private func consumePendingReport() {
        guard let reopened = importInbox.pendingReport else { return }
        importInbox.pendingReport = nil
        startNewReport(reopened)
    }

    /// Presents the review sheet, carrying a DRY RUN of where each value
    /// would land so the sheet can warn about findings with no matching row.
    private func presentReview(for details: PatientDemographics) {
        let outcome = PatientImport.outcome(applying: details, to: document)
        // Deferred one runloop turn: presenting during the same update that
        // opens the editor (beginEditing flips isEditing) can swallow it.
        DispatchQueue.main.async {
            patientReview = PatientReviewPayload(demographics: details, outcome: outcome)
        }
    }

    /// Confirmed details → the working document, then straight to the draft
    /// so an imported report is quit-safe like any typed one.
    private func applyPatientDetails(_ details: PatientDemographics) {
        document.applyPatientDetails(details)
        draftStore.autosave(document: document, baseline: baseline)
    }

    /// Explicit bar height: 36pt controls + 16pt padding top and bottom.
    /// The scroll spacer inset reads this too — keep them in step.
    private static let finishBarHeight: CGFloat = 68

    /// The two "I'm done composing" actions side by side; Preview keeps the
    /// prominent style as the primary.
    private var finishBar: some View {
        HStack(spacing: 12) {
            Button {
                newTemplateName = ""
                showingSaveTemplate = true
            } label: {
                Label("Save as Template", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                // Snapshot the live document at tap time so the preview
                // renders exactly what's been entered — .sheet(item:) then
                // presents that snapshot rather than re-reading state on its
                // own schedule.
                previewPayload = PreviewPayload(document: document)
            } label: {
                Label("Preview", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(height: 36)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            // The material runs to the PHYSICAL bottom edge (through the
            // home-indicator band and the ignored keyboard region) — without
            // this, a thin strip below the bar showed system-dependent
            // translucency that flipped to clear when a field focused,
            // making the pinned bar look like it floated.
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var chooserList: some View {
        List {
            // Details shared in from the EMR wait here until a report exists
            // to put them in — the template choice stays the clinician's.
            if let pending = importInbox.pendingPatient {
                Section("Patient Details Ready") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending.displayName ?? "Imported patient")
                        Text("Start a report below — you'll be asked to check these details before they're applied.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Discard details", role: .destructive) {
                        importInbox.pendingPatient = nil
                    }
                }
            }

            if let draft = draftStore.draft {
                Section("In Progress") {
                    Button {
                        document = draft.document
                        baseline = draft.baseline
                        isEditing = true
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume Draft")
                            Text(draftSubtitle(draft))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Start") {
                Button("Blank Report") {
                    // No blank-document factory exists on ReportDocument yet;
                    // the memberwise init's defaults (empty blocks, nil
                    // templateName) already give a true blank document.
                    startNewReport(ReportDocument())
                }
                // Reopen a previously exported report: our PDFs carry their
                // structured source (EmbeddedReport); the report comes back
                // EXACTLY as exported (user decision — no volatile clearing).
                Button {
                    importingReportPDF = true
                } label: {
                    Label("Import report PDF…", systemImage: "doc.badge.arrow.up")
                }
                .fileImporter(
                    isPresented: $importingReportPDF,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    handleReportPDFImport(result)
                }
                // Pull the patient in from an IRIS PDF saved to Files. The
                // push equivalent — sharing straight from the EMR — needs no
                // button: it lands in the inbox and shows up above.
                // Its importer hangs off THIS button, matching the sibling
                // above: two importers on a shared ancestor collide.
                Button {
                    importingPatientPDF = true
                } label: {
                    Label("Import patient details…", systemImage: "person.text.rectangle")
                }
                .fileImporter(
                    isPresented: $importingPatientPDF,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: false
                ) { result in
                    handlePatientPDFImport(result)
                }
            }

            if !templateStore.templates.isEmpty {
                Section("Templates") {
                    ForEach(filteredTemplates) { template in
                        Button(template.templateName ?? "Untitled") {
                            startNewReport(ReportDocument.newReport(from: template))
                        }
                    }
                    if filteredTemplates.isEmpty {
                        ContentUnavailableView.search(text: templateSearch)
                    }
                }
            }
        }
        .searchable(text: $templateSearch, prompt: "Search templates")
    }

    /// Templates whose name matches the search text (all when empty). Order
    /// is the store's array order — the user's arranged order — unchanged.
    private var filteredTemplates: [ReportDocument] {
        let query = templateSearch.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return templateStore.templates }
        return templateStore.templates.filter {
            ($0.templateName ?? "Untitled").localizedCaseInsensitiveContains(query)
        }
    }

    /// A picked PDF → the embedded document → an EXACT copy in the editor
    /// (user decision: everything verbatim — findings, impressions, dates —
    /// edited by hand as needed; NOT routed through duplicatedForNewVisit,
    /// whose volatile-clearing surprised as "blank fields"). Only the
    /// document identity is refreshed. Foreign or pre-feature PDFs (no
    /// payload) get a clear error.
    private func handleReportPDFImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let document = EmbeddedReport.document(from: data) else {
            showingPDFImportError = true
            return
        }
        var reopened = document
        reopened.id = UUID()
        reopened.templateName = nil
        reopened.createdAt = Date()
        reopened.modifiedAt = Date()
        startNewReport(reopened)
    }

    /// Chooser tap: if a saved draft holds modified text, warn before the new
    /// session's first autosave replaces it (mirrors the Start Over warning).
    private func startNewReport(_ doc: ReportDocument) {
        if let draft = draftStore.draft,
           ModifiedText.hasModifiedText(draft.document, against: draft.baseline) {
            pendingNewDocument = doc
            showingReplaceDraftWarning = true
        } else {
            beginEditing(doc)
        }
    }

    private func beginEditing(_ doc: ReportDocument) {
        document = doc
        baseline = doc
        isEditing = true
        // Write the fresh session immediately so the draft on disk always
        // matches what's on screen (replacing any previous draft).
        draftStore.autosave(document: doc, baseline: doc)
        // Details held at the chooser were waiting for exactly this moment.
        consumePendingPatient()
    }

    /// "Lastname, Firstname — saved …", or just the save time before a
    /// patient name has been entered.
    private func draftSubtitle(_ draft: ReportDraft) -> String {
        let saved = "saved " + draft.savedAt.formatted(date: .abbreviated, time: .shortened)
        for block in draft.document.blocks {
            if case .patient(let p) = block.content {
                let name = [p.lastName, p.firstName]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                if !name.isEmpty { return "\(name) — \(saved)" }
            }
        }
        return saved
    }

    private func saveAsTemplate() {
        let trimmed = newTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Untitled Template" : trimmed
        templateStore.add(document.asTemplate(named: name))
        showingSavedConfirmation = true
    }
}

/// The on-screen keyboard's overlap with the screen, straight from UIKit's
/// keyboard-frame notifications. The editor subtree deliberately ignores
/// SwiftUI's keyboard safe area (it floats the pinned finish bar on
/// stale/phantom keyboard heights — see LESSONS), so the scroll inset that
/// keeps fields reachable above the keyboard is driven from here instead.
private final class KeyboardOverlapObserver: ObservableObject {
    @Published var overlap: CGFloat = 0
    /// Set while a modal covers the editor (the Preview sheet, and anything
    /// it presents — Print, Share, Save to Files). The overlap only shifts
    /// the editor's scroll spacer, which nobody can see then, so publishing
    /// it would rebuild the whole New Report hierarchy for nothing. That
    /// mattered: a share extension's own keyboard activity posts these
    /// notifications INTO this app, and each rebuild re-rendered the preview
    /// PDF on the main thread, which starved the extension's hardware-key
    /// input. The last value is kept, not zeroed, so dismissing the sheet
    /// restores the spacer it had.
    var isSuspended = false
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil, queue: .main) { [weak self] note in
                guard let self,
                      let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                let bounds = UIScreen.main.bounds
                let newOverlap = max(0, bounds.maxY - end.minY)
                // Defer to the next runloop tick: iOS can deliver this
                // notification DURING a SwiftUI view update (e.g. when focus
                // changes as the view re-renders), and publishing @Published
                // mid-update is the warning. async breaks out of that cycle.
                DispatchQueue.main.async {
                    // Publish only a REAL change: the shortcut bar alone
                    // posts a stream of same-height notifications, and each
                    // publish rebuilt the whole screen.
                    guard !self.isSuspended, self.overlap != newOverlap else { return }
                    self.overlap = newOverlap
                }
        })
        tokens.append(center.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, !self.isSuspended, self.overlap != 0 else { return }
                    self.overlap = 0
                }
        })
    }

    deinit {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

/// A one-shot, present-time snapshot of a parse plus the dry run of where its
/// values would land. `.sheet(item:)` on this guarantees the review sheet
/// shows that import, not a re-read of whatever state exists later.
private struct PatientReviewPayload: Identifiable {
    let id = UUID()
    let demographics: PatientDemographics
    let outcome: PatientImportOutcome
}

/// A one-shot, tap-time snapshot of the working document for the preview sheet.
/// Using `.sheet(item:)` with this payload guarantees the preview renders exactly
/// what was entered at the moment Preview was tapped, instead of an independently
/// re-read (and possibly stale) copy of `@State document`.
private struct PreviewPayload: Identifiable {
    let id = UUID()
    let document: ReportDocument
}

#Preview {
    NewReportView()
        .environmentObject(LetterheadStore())
        .environmentObject(TemplateStore())
        .environmentObject(PractitionerProfileStore())
        .environmentObject(DraftStore())
        .environmentObject(TabRouter())
        .environmentObject(ProviderStore())
        .environmentObject(PatientImportInbox())
}
