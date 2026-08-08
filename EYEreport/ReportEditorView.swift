import SwiftUI
import UniformTypeIdentifiers

// The drag payload type for block reordering. A private custom type — NOT
// plain text — so nothing else can claim the drop: a plain-text payload was
// being accepted by UITextViews, which pasted the payload string into the
// prose and swallowed the drop our delegates needed to end the drag.
private let blockDragType = UTType(exportedAs: "com.eyereport.block-drag")

struct ReportEditorView: View {
    @Binding var document: ReportDocument
    /// The document as this editing session STARTED (template copy or blank).
    /// Drives the delete-modified-text warning; nil (previews) = no warnings.
    var baseline: ReportDocument? = nil
    @State private var isArranging = false
    @State private var draggedBlockID: UUID?
    @State private var blockPendingDeletion: Block?
    // The ONE document-wide focused-field key (see FocusChain.swift). Every
    // bridged field in every block editor reads and claims this via the
    // BlockFocusChain threaded through BlockContentEditor.
    @State private var focusedKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isArranging {
                        insertBlockButton(afterBlockID: nil)
                    }
                    ForEach(document.blocks) { block in
                        blockRow(block)
                        if isArranging {
                            insertBlockButton(afterBlockID: block.id)
                        } else {
                            Divider()
                        }
                    }
                }
                .padding()
                .padding(.bottom, 60)
            }
            // Catch-all for a block drag released over a gap (no row under the
            // drop point): end the drag session cleanly.
            .onDrop(of: [blockDragType], isTargeted: nil) { providers in
                draggedBlockID = nil
                consumeDragItems(providers)
                return true
            }
            .alert("Delete this block?",
                   isPresented: Binding(
                       get: { blockPendingDeletion != nil },
                       set: { if !$0 { blockPendingDeletion = nil } }),
                   presenting: blockPendingDeletion) { block in
                Button("Delete", role: .destructive) { removeBlock(block.id) }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("You are about to delete text that has been modified. Changes will be lost.")
            }
            .toolbar {
                // (+) sits beside Arrange (both are structure-editing moves);
                // Start Over keeps the leading corner to itself.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        ForEach(NewBlockKind.allCases, id: \.self) { kind in
                            Button(kind.title) {
                                document.blocks.append(Block(kind.makeContent()))
                            }
                        }
                    } label: {
                        Label("Add Block", systemImage: "plus")
                    }
                    Button(isArranging ? "Done" : "Arrange") {
                        withAnimation {
                            isArranging.toggle()
                            draggedBlockID = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row assembly

    /// Content binding by ID with a safe fallback — never a ForEach element
    /// binding: a bridged field inside a deleted block can update once more
    /// against the stale index (the documented last-element-delete crash).
    private func contentBinding(for id: UUID) -> Binding<BlockContent> {
        Binding(
            get: {
                document.blocks.first(where: { $0.id == id })?.content
                    ?? .title(TitleContent(text: ""))
            },
            set: { newValue in
                if let index = document.blocks.firstIndex(where: { $0.id == id }) {
                    document.blocks[index].content = newValue
                }
            }
        )
    }

    private func blockRow(_ block: Block) -> some View {
        let id = block.id
        return VStack(alignment: .leading, spacing: 4) {
            blockHeader(for: block)
            BlockContentEditor(content: contentBinding(for: id),
                               focus: BlockFocusChain(blockID: id,
                                                      binding: $focusedKey,
                                                      move: moveFocus(from:backward:)),
                               recipientName: mirroredRecipientName)
        }
        .padding(isArranging ? 8 : 0)
        .overlay {
            if isArranging {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.blue, lineWidth: 2)
            }
        }
        .onDrop(of: [blockDragType], delegate: BlockReorderDropDelegate(
            targetID: id,
            blocks: $document.blocks,
            draggedID: $draggedBlockID,
            isActive: isArranging))
    }

    // The header is the ONLY drag source, and only while arranging — a drag
    // gesture anywhere lower would fight the editors' text views.
    @ViewBuilder
    private func blockHeader(for block: Block) -> some View {
        let header = HStack {
            if isArranging {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }
            Text(blockTypeName(block.content))
                .blockTitleStyle()
            Spacer()
            if isArranging {
                Button(role: .destructive) {
                    deleteBlock(block.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())

        if isArranging {
            header.onDrag {
                draggedBlockID = block.id
                // The payload carries no data — the dragged block is tracked
                // in draggedBlockID; the provider exists only to give the
                // session our private type.
                let provider = NSItemProvider()
                provider.registerDataRepresentation(for: blockDragType,
                                                    visibility: .ownProcess) { completion in
                    completion(Data(), nil)
                    return nil
                }
                return provider
            }
        } else {
            header
        }
    }

    private func insertBlockButton(afterBlockID id: UUID?) -> some View {
        Menu {
            ForEach(NewBlockKind.allCases, id: \.self) { kind in
                Button(kind.title) {
                    insertBlock(kind, afterBlockID: id)
                }
            }
        } label: {
            Label("Add block here", systemImage: "plus")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity)
    }

    /// The doctor name a mirroring salutation follows: the FIRST provider+fax
    /// recipient block in the document (nil when there isn't one).
    private var mirroredRecipientName: String? {
        for block in document.blocks {
            if case .recipient(.providerFax(let name, _)) = block.content { return name }
        }
        return nil
    }

    // MARK: - Tab focus chain (document-wide)

    /// Moves focus to the next/previous field in the document-ordered chain.
    /// The order is recomputed from the live document at every Tab press, so
    /// rearranged blocks tab in their new visual order. Stops at the ends
    /// (no wrap-around).
    private func moveFocus(from key: String, backward: Bool) {
        let keys = FocusOrder.orderedKeys(for: document)
        guard let index = keys.firstIndex(of: key) else { return }
        let next = backward ? index - 1 : index + 1
        guard keys.indices.contains(next) else { return }
        focusedKey = keys[next]
    }

    // MARK: - Block operations (pure UI over document.blocks)

    private func insertBlock(_ kind: NewBlockKind, afterBlockID id: UUID?) {
        var index = 0
        if let id, let i = document.blocks.firstIndex(where: { $0.id == id }) {
            index = i + 1
        }
        withAnimation {
            document.blocks.insert(Block(kind.makeContent()), at: index)
        }
    }

    /// Deletes immediately when nothing typed would be lost; otherwise asks.
    private func deleteBlock(_ id: UUID) {
        guard let block = document.blocks.first(where: { $0.id == id }) else { return }
        if let baseline, ModifiedText.isModified(block, against: baseline) {
            blockPendingDeletion = block
        } else {
            removeBlock(id)
        }
    }

    private func removeBlock(_ id: UUID) {
        withAnimation { document.blocks.removeAll { $0.id == id } }
    }

    private func blockTypeName(_ content: BlockContent) -> String {
        switch content {
        case .subject:        return "SUBJECT"
        case .recipient:      return "RECIPIENT"
        case .date:           return "DATE"
        case .patient:        return "PATIENT"
        case .salutation:     return "SALUTATION"
        case .prose(let p):   return p.boxed == true ? "BOXED PROSE" : "PROSE"
        case .findings:       return "FINDINGS"
        case .impressionsPlan: return "IMPRESSIONS / PLAN"
        case .closing:        return "CLOSING"
        case .title:          return "TITLE"
        case .signature:      return "SIGNATURE"
        case .spacer:         return "BLANK SPACE"
        }
    }
}

// Reorders live while the dragged block hovers over another block's row; the
// drop itself just ends the drag. Inert (validateDrop false) outside Arrange
// mode and for anything that isn't one of our block drags — e.g. text dragged
// within an editor.
private struct BlockReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var blocks: [Block]
    @Binding var draggedID: UUID?
    let isActive: Bool

    func validateDrop(info: DropInfo) -> Bool {
        isActive && draggedID != nil
    }

    func dropEntered(info: DropInfo) {
        guard isActive,
              let draggedID,
              draggedID != targetID,
              let from = blocks.firstIndex(where: { $0.id == draggedID }),
              let to = blocks.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation {
            blocks.move(fromOffsets: IndexSet(integer: from),
                        toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        consumeDragItems(info.itemProviders(for: [blockDragType]))
        return true
    }
}

// Reading the dragged item's data lets UIKit finish the drag session at once.
// An accepted drop whose NSItemProvider is never read keeps the session — and
// the source row's dimmed "lift" appearance — alive until it times out
// (observed ~20 s). The payload is empty and unused; reordering already
// happened via dropEntered.
private func consumeDragItems(_ providers: [NSItemProvider]) {
    for provider in providers {
        _ = provider.loadDataRepresentation(for: blockDragType) { _, _ in }
    }
}

// The block types offerable from the "+" menu, each with a display title and
// a minimally-seeded empty content value. Pure UI over the existing model —
// every constructor below is an existing initializer in ReportModel.swift.
private enum NewBlockKind: CaseIterable {
    case recipient, title, date, patient, subject, salutation,
         prose, boxedProse, findings, impressionsPlan, closing, signature, spacer

    var title: String {
        switch self {
        case .recipient:       return "Recipient"
        case .title:           return "Title"
        case .date:            return "Date"
        case .patient:         return "Patient"
        case .subject:         return "Subject"
        case .salutation:      return "Salutation"
        case .prose:           return "Prose"
        case .boxedProse:      return "Boxed Prose"
        case .findings:        return "Findings"
        case .impressionsPlan: return "Impressions / Plan"
        case .closing:         return "Closing"
        case .signature:       return "Signature"
        case .spacer:          return "Blank space"
        }
    }

    func makeContent() -> BlockContent {
        switch self {
        case .recipient:
            return .recipient(.none)
        case .title:
            return .title(TitleContent(text: ""))
        case .date:
            return .date(DateContent(label: "", date: nil))
        case .patient:
            return .patient(PatientContent())
        case .subject:
            return .subject(SubjectContent(text: ""))
        case .salutation:
            return .salutation(.dearDoctor(name: "", mirrorsRecipient: true))
        case .prose:
            return .prose(ProseContent(paragraphs: [Paragraph(runs: [Run(.fixed(""))])]))
        case .boxedProse:
            return .prose(ProseContent(paragraphs: [Paragraph(runs: [Run(.fixed(""))])], boxed: true))
        case .findings:
            // The full standard clinical grid, ready to fill — not a lone
            // blank row (single source shared with the referral preset).
            return .findings(Presets.standardFindings)
        case .impressionsPlan:
            return .impressionsPlan(ImpressionsPlanContent())
        case .closing:
            return .closing(.sharingInCare)
        case .signature:
            return .signature(SignatureContent())
        case .spacer:
            return .spacer(SpacerContent())
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var document = Presets.standardReferral
        var body: some View {
            ReportEditorView(document: $document)
        }
    }
    // The referral preset contains signature + recipient blocks, whose
    // editors read the profile store, tab router, and provider store.
    return Demo()
        .environmentObject(PractitionerProfileStore())
        .environmentObject(TabRouter())
        .environmentObject(ProviderStore())
}
