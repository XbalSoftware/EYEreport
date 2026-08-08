//
//  TemplatesView.swift
//  EYEreport
//
//  Saved templates list + export/import. Export shares ALL templates as one
//  named JSON file via the share sheet (templates carry no PHI — the
//  asTemplate path strips it); import reads such a file back, appending its
//  templates with fresh ids. The backup/restore path for an app reset.
//

import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

struct TemplatesView: View {
    @EnvironmentObject private var store: TemplateStore

    @State private var showingImporter = false
    @State private var importMessage: String?
    @State private var renamingTemplate: ReportDocument?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates Yet",
                        systemImage: "doc.on.doc",
                        description: Text("Saved templates will appear here.")
                    )
                } else {
                    List {
                        ForEach(store.templates) { template in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(template.templateName ?? "Untitled")
                                    Text(template.modifiedAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                // Rename lives ONLY on the pencil (generous
                                // padding for the tap target) — the rest of
                                // the row stays inert so drags/swipes own it.
                                Button {
                                    renameText = template.templateName ?? ""
                                    renamingTemplate = template
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .navigationTitle("Templates")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: TemplatesExportFile(templates: store.templates),
                                  preview: SharePreview(TemplatesExportFile.exportName)) {
                            Label("Export Templates", systemImage: "square.and.arrow.up")
                        }
                        .disabled(store.templates.isEmpty)

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import Templates…", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert(importMessage ?? "",
                   isPresented: Binding(
                       get: { importMessage != nil },
                       set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) { }
            }
            .alert("Rename Template",
                   isPresented: Binding(
                       get: { renamingTemplate != nil },
                       set: { if !$0 { renamingTemplate = nil } }),
                   presenting: renamingTemplate) { template in
                TextField("Template name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Empty would blank the name (and templateName must stay
                    // non-nil) — treat as no change.
                    if !trimmed.isEmpty {
                        store.rename(id: template.id, to: trimmed)
                    }
                }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            importMessage = "Import failed — the file couldn't be opened."
        case .success(let url):
            // Files outside our sandbox (Files app, iCloud Drive) need
            // security-scoped access for the read.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let imported = try? JSONDecoder().decode([ReportDocument].self, from: data),
                  !imported.isEmpty else {
                importMessage = "Import failed — that file doesn't contain EYEreport templates."
                return
            }
            store.importTemplates(imported)
            importMessage = imported.count == 1
                ? "Imported 1 template."
                : "Imported \(imported.count) templates."
        }
    }
}

// MARK: - Shareable export file

/// All templates as one named JSON file for the share sheet — same
/// FileRepresentation pattern as the PDF export (a real file so receivers
/// keep the name); written only when a share is committed. The JSON is the
/// store's own encoding, so an exported file round-trips through import
/// losslessly.
private struct TemplatesExportFile: Transferable {
    let templates: [ReportDocument]

    static var exportName: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "EYEreport Templates \(df.string(from: Date())).json"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(exportName)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export.templates)
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url, allowAccessingOriginalFile: false)
        }
    }
}

#Preview {
    TemplatesView()
        .environmentObject(LetterheadStore())
        .environmentObject(TemplateStore())
}
