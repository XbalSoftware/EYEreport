//
//  PreviewView.swift
//  EYEreport
//
//  Read-only preview of the working report: rendered to PDF by ReportRenderer
//  and composited onto a chosen letterhead. Letterhead choice is orthogonal to
//  the document (any report prints on any letterhead); "None (plain)" uses the
//  renderer's plain 72pt-inset fallback path.
//
//  Practitioner identity (name, credentials, ID, signature image) comes from
//  the stored profile (PractitionerProfileStore / Settings tab).
//

import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers

struct PreviewView: View {
    let document: ReportDocument
    /// Reports the text-size choice back to the OWNER's working document —
    /// `document` here is a tap-time snapshot, so without this the choice
    /// would die with the sheet. nil (previews) = preview-only.
    var onFontSizeChange: ((Double?) -> Void)? = nil

    @EnvironmentObject private var letterheadStore: LetterheadStore
    @EnvironmentObject private var profileStore: PractitionerProfileStore
    @Environment(\.dismiss) private var dismiss

    /// nil = no letterhead (plain fallback). Seeded to the first stored
    /// letterhead on appear, if any exist.
    @State private var selectedLetterheadID: Letterhead.ID?
    @State private var didSeedSelection = false
    /// Body text size; nil = default 11pt. Seeded from the document.
    @State private var fontSize: Double?
    @State private var savingToFiles = false

    /// The rendered bytes, held in state rather than recomputed from a
    /// computed property. `renderToPDFData` is EXPENSIVE (full pagination,
    /// letterhead compositing, plus the embedded-source read-back and
    /// possible PDFKit re-serialization), and a computed property ran it
    /// once for the PDF view and AGAIN for the file-exporter document on
    /// EVERY body pass. Any rebuild of the owning view — including one
    /// caused by a keyboard-frame notification while a share extension is
    /// on screen — therefore stalled the main thread with two full renders,
    /// which starved the extension's hardware-key input. Render only when
    /// the inputs actually change (`renderKey`).
    @State private var renderedPDF = Data()
    @State private var renderKey = ""

    private var selectedLetterhead: Letterhead? {
        guard let id = selectedLetterheadID else { return nil }
        return letterheadStore.letterheads.first { $0.id == id }
    }

    /// The current rendering, re-rendered only when the letterhead or text
    /// size has actually changed. `document` is a tap-time snapshot and never
    /// changes for the life of this sheet, so those two are the whole input
    /// set. Returns the bytes as well as caching them, so Print and Share get
    /// the right data without depending on a same-tick `@State` read-back.
    @discardableResult
    private func currentPDFData() -> Data {
        let key = "\(selectedLetterheadID?.uuidString ?? "plain")|\(fontSize ?? 11)"
        if key == renderKey, !renderedPDF.isEmpty { return renderedPDF }
        var doc = document
        doc.bodyFontSize = fontSize
        let data = ReportRenderer.renderToPDFData(doc,
                                                  profile: profileStore.profile,
                                                  letterhead: selectedLetterhead)
        renderedPDF = data
        renderKey = key
        return data
    }

    /// "DOE, Jane 2026-07-07" — patient (when present) + today, sanitized.
    /// Receivers (Files, print jobs, EMR imports) all show this name, so it
    /// matches how the report itself prints the patient: surname upper-cased
    /// (done here, not assumed of the stored value, so hand-typed names look
    /// the same as imported ones) and comma-separated.
    private var exportBasename: String {
        var parts: [String] = []
        if let p = document.patient {
            let name = [p.lastName.uppercased(), p.firstName]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !name.isEmpty { parts.append(name) }
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        parts.append(df.string(from: Date()))
        let joined = parts.joined(separator: " ")
        let sanitized = joined
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined()
        return sanitized.isEmpty ? "EYEreport" : sanitized
    }

    private var exportFilename: String { "\(exportBasename).pdf" }

    var body: some View {
        NavigationStack {
            PDFKitView(data: renderedPDF)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        // The two everyday outputs as first-class buttons;
                        // the share sheet stays as the overflow (EMR share
                        // extensions, Messages, AirDrop, …). All three feed
                        // the CURRENT rendering (letterhead + text size).
                        Button {
                            printPDF()
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        Button {
                            savingToFiles = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                        }
                        Button {
                            sharePDF()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        // Body text size — re-renders live; the choice is
                        // pushed back to the working document (persists, and
                        // rides into save-as-template).
                        Menu {
                            Picker("Text size", selection: $fontSize) {
                                ForEach([9.0, 10.0], id: \.self) { size in
                                    Text("\(Int(size)) pt").tag(Double?.some(size))
                                }
                                Text("11 pt (default)").tag(Double?.none)
                                ForEach([12.0, 13.0], id: \.self) { size in
                                    Text("\(Int(size)) pt").tag(Double?.some(size))
                                }
                            }
                        } label: {
                            Label("\(Int(fontSize ?? 11)) pt", systemImage: "textformat.size")
                        }
                        .onChange(of: fontSize) {
                            onFontSizeChange?(fontSize)
                            currentPDFData()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Picker("Letterhead", selection: $selectedLetterheadID) {
                                Text("None (plain)").tag(Letterhead.ID?.none)
                                ForEach(letterheadStore.letterheads) { lh in
                                    Text(lh.name).tag(Letterhead.ID?.some(lh.id))
                                }
                            }
                        } label: {
                            Label(selectedLetterhead?.name ?? "None (plain)",
                                  systemImage: "doc.richtext")
                        }
                        // Sticky: every pick (including "None") becomes the
                        // app-wide active selection, so the next Preview
                        // opens on the same letterhead.
                        .onChange(of: selectedLetterheadID) {
                            letterheadStore.activeSelection =
                                selectedLetterheadID.map { .letterhead($0) } ?? .plain
                            currentPDFData()
                        }
                    }
                }
        }
        .fileExporter(isPresented: $savingToFiles,
                      document: PDFExportDocument(data: renderedPDF),
                      contentType: .pdf,
                      defaultFilename: exportBasename) { _ in }
        .onAppear {
            guard !didSeedSelection else { return }
            // The sticky app-wide selection; never-chosen falls back to the
            // first stored letterhead (the historical default).
            switch letterheadStore.activeSelection {
            case .plain:
                selectedLetterheadID = nil
            case .letterhead(let id) where letterheadStore.letterheads.contains(where: { $0.id == id }):
                selectedLetterheadID = id
            default:
                selectedLetterheadID = letterheadStore.letterheads.first?.id
            }
            fontSize = document.bodyFontSize
            didSeedSelection = true
            // Seeded values are already visible to this read, so this is the
            // one render the sheet needs on open; the onChange handlers above
            // are no-ops afterwards because the key is unchanged.
            currentPDFData()
        }
    }

    /// System print dialog fed the current rendering. On iPad the controller
    /// needs an anchor rect — the top-trailing corner of the key window sits
    /// under the toolbar's Print button; iPhone-style plain presentation is
    /// the fallback.
    private func printPDF() {
        let data = currentPDFData()
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = exportFilename
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data

        if let window = Self.keyWindow {
            controller.present(from: Self.topTrailingAnchor(in: window), in: window,
                               animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    /// Share sheet fed a CONCRETE temp-file URL, not a Transferable file
    /// promise: iDoc's EMR share extension (and likely others) can't load
    /// the promise ShareLink hands over — its import button stayed grayed
    /// out — but handles a real file URL exactly as it does when sharing
    /// from the Files app. The temp file is written at tap time and left
    /// for the system to purge (PHI briefly in tmp is inherent to
    /// exporting; the next share of the same report overwrites it).
    private func sharePDF() {
        let data = currentPDFData()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFilename)
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        let controller = UIActivityViewController(activityItems: [url],
                                                  applicationActivities: nil)
        guard let window = Self.keyWindow,
              let presenter = Self.topViewController(in: window) else { return }
        // iPad presents the share sheet as a popover — anchor it where the
        // toolbar buttons live, same as Print.
        controller.popoverPresentationController?.sourceView = window
        controller.popoverPresentationController?.sourceRect = Self.topTrailingAnchor(in: window)
        presenter.present(controller, animated: true)
    }

    // MARK: UIKit presentation plumbing (shared by Print and Share)

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            .flatMap { scene in
                scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
            }
    }

    /// The frontmost presented controller — PreviewView itself is a sheet,
    /// so presenting from the root would fail.
    private static func topViewController(in window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private static func topTrailingAnchor(in window: UIWindow) -> CGRect {
        CGRect(x: window.bounds.maxX - 60, y: 60, width: 1, height: 1)
    }
}

// MARK: - Save-to-Files document

/// Minimal FileDocument wrapper so `.fileExporter` can write the rendered
/// PDF bytes; reading back is never used (the exporter requires the
/// conformance).
private struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}


// MARK: - PDFView wrapper

/// Displays PDF `Data` as vertically-scrolling pages. Reassigns the document on
/// update so a letterhead change re-renders in place.
private struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    /// Rebuild the PDFDocument ONLY when the bytes actually changed. An
    /// unconditional rebuild re-parsed the whole document (and reset the
    /// scroll position) on every SwiftUI update — including updates arriving
    /// while a share extension is on screen, where main-thread work costs
    /// the extension its hardware-key input.
    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.displayMode = .singlePageContinuous
        uiView.displayDirection = .vertical
        guard context.coordinator.lastData != data else { return }
        context.coordinator.lastData = data
        uiView.document = PDFDocument(data: data)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastData: Data?
    }
}

#Preview {
    PreviewView(document: Presets.standardReferral)
        .environmentObject(LetterheadStore())
        .environmentObject(PractitionerProfileStore())
}
