import SwiftUI
import UIKit

/// A pending caret placement request produced by a split or merge. `updateUIView`
/// on the matching `RichParagraphEditor` consumes it once (grabbing first
/// responder and positioning the caret at `offset`, a UTF-16 index) then clears
/// it, so it never re-fires on a later rebuild.
struct FocusRequest: Equatable {
    let id: UUID
    let offset: Int
}

/// The display-only leading glyph for a list paragraph. Never part of the field
/// text or the paragraph's `[Run]`.
private enum ParagraphMarker: Equatable {
    case none
    case bullet
    case number(Int)
}

struct ProseEditor: View {
    @Binding var content: ProseContent
    var focus: BlockFocusChain? = nil
    @StateObject private var formatting = ProseFormattingController()
    @State private var focusRequest: FocusRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormattingToolbar(controller: formatting)
                .frame(height: 32)
                .padding(.bottom, -10)
            if content.isAllFixed {
                // One consolidated box: Return = new line/paragraph in place, and a
                // multi-line selection can be turned into a list in one tap.
                // The whole box is ONE stop in the document tab chain.
                ZStack(alignment: .topLeading) {
                    ProseBlockEditor(content: $content, controller: formatting,
                                     focusKey: focus.key(FocusFields.prose),
                                     focusBinding: focus.binding,
                                     onTab: focus.tab(FocusFields.prose))
                        .frame(minHeight: max(standardFieldHeight, 60))
                    if isEffectivelyEmpty {
                        Text("Type subjective here")
                            .foregroundStyle(Color(UIColor.placeholderText))
                            .padding(.leading, 8)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                // Fallback for blocks with slots/tokens: per-paragraph editors, so
                // the slot pick-controls and read-only token paragraphs still work.
                ForEach(content.paragraphs) { paragraph in
                    ParagraphRow(
                        paragraph: binding(for: paragraph.id),
                        marker: marker(for: paragraph.id),
                        focusRequest: $focusRequest,
                        controller: formatting,
                        onSplit: { offset in split(id: paragraph.id, at: offset) },
                        onMergeBackward: { mergeBackward(id: paragraph.id) }
                    )
                }
            }
        }
    }

    // Routing between the consolidated box and the per-paragraph fallback uses
    // the shared `ProseContent.isAllFixed` (FocusChain.swift) — the same check
    // FocusOrder uses, so the tab chain always matches the mounted editor.

    /// A single blank paragraph (fresh block) — drives the placeholder overlay.
    private var isEffectivelyEmpty: Bool {
        content.paragraphs.count <= 1 && content.paragraphs.allSatisfy { para in
            para.runs.allSatisfy { if case .fixed(let s) = $0.content { return s.isEmpty }; return false }
        }
    }

    // MARK: id-based lookups (stale-index discipline — a row feeds a
    // UIViewRepresentable, and split/merge mutate the list underneath it).

    /// A binding to the paragraph identified by `id`, looked up by id every access
    /// so a removed paragraph can't crash "Index out of range."
    private func binding(for id: UUID) -> Binding<Paragraph> {
        Binding(
            get: { content.paragraphs.first(where: { $0.id == id }) ?? Paragraph(runs: [Run(.fixed(""))]) },
            set: { newValue in
                if let idx = content.paragraphs.firstIndex(where: { $0.id == id }) {
                    content.paragraphs[idx] = newValue
                }
            }
        )
    }

    /// The display marker for a paragraph. Numbering mirrors
    /// `ReportRenderer.numberedOrdinal`: N counts consecutive `.numbered`
    /// paragraphs ending at this one, so the editor marker equals the printed
    /// number.
    private func marker(for id: UUID) -> ParagraphMarker {
        guard let index = content.paragraphs.firstIndex(where: { $0.id == id }) else { return .none }
        switch content.paragraphs[index].style {
        case .bullet:
            return .bullet
        case .numbered:
            var n = 1
            var i = index - 1
            while i >= 0, case .numbered = content.paragraphs[i].style {
                n += 1
                i -= 1
            }
            return .number(n)
        default:
            return .none
        }
    }

    // MARK: Return-splits / Backspace-merges (owns content.paragraphs)

    /// The paragraph's plain `.fixed` text (RichParagraphEditor paragraphs are
    /// all-`.fixed`); used to detect an empty list item.
    private func fixedText(of paragraph: Paragraph) -> String {
        paragraph.runs.map { run -> String in
            if case .fixed(let s) = run.content { return s }
            return ""
        }.joined()
    }

    /// Split the paragraph identified by `id` at UTF-16 offset `utf16Offset`:
    /// head runs stay, tail runs become a new paragraph inheriting this one's
    /// style, focus moves to the new paragraph at offset 0. An empty list item
    /// instead ends the list (style → `.body`, caret stays put).
    private func split(id: UUID, at utf16Offset: Int) {
        guard let index = content.paragraphs.firstIndex(where: { $0.id == id }) else { return }
        let para = content.paragraphs[index]

        let isList: Bool
        switch para.style {
        case .bullet, .numbered: isList = true
        default: isList = false
        }
        if isList && fixedText(of: para).isEmpty {
            content.paragraphs[index].style = .body
            focusRequest = FocusRequest(id: id, offset: 0)
            return
        }

        let (head, tail) = Self.splitRuns(para.runs, atUTF16: utf16Offset)
        content.paragraphs[index].runs = head.isEmpty ? [Run(.fixed(""))] : head
        let newParagraph = Paragraph(runs: tail.isEmpty ? [Run(.fixed(""))] : tail, style: para.style)
        content.paragraphs.insert(newParagraph, at: index + 1)
        focusRequest = FocusRequest(id: newParagraph.id, offset: 0)
    }

    /// Merge the paragraph identified by `id` into the previous one: append its
    /// runs onto the previous paragraph, remove it, and place the caret at the
    /// seam. First paragraph → no-op.
    private func mergeBackward(id: UUID) {
        guard let index = content.paragraphs.firstIndex(where: { $0.id == id }), index > 0 else { return }
        let prevIndex = index - 1
        let prevLength = (fixedText(of: content.paragraphs[prevIndex]) as NSString).length
        let tailRuns = content.paragraphs[index].runs
        content.paragraphs[prevIndex].runs.append(contentsOf: tailRuns)
        let prevID = content.paragraphs[prevIndex].id
        content.paragraphs.remove(at: index)
        focusRequest = FocusRequest(id: prevID, offset: prevLength)
    }

    /// Split `runs` at UTF-16 `offset`, preserving each run's emphasis. The run
    /// straddling the offset is split at the local index; an offset landing on a
    /// run boundary keeps whole runs on each side.
    static func splitRuns(_ runs: [Run], atUTF16 offset: Int) -> (head: [Run], tail: [Run]) {
        var head: [Run] = []
        var tail: [Run] = []
        var consumed = 0
        var didSplit = false
        for run in runs {
            if didSplit {
                tail.append(run)
                continue
            }
            guard case .fixed(let s) = run.content else {
                head.append(run)
                continue
            }
            let ns = s as NSString
            let length = ns.length
            if offset >= consumed + length {
                head.append(run)
                consumed += length
            } else {
                let local = offset - consumed
                let headStr = ns.substring(to: local)
                let tailStr = ns.substring(from: local)
                if !headStr.isEmpty { head.append(Run(.fixed(headStr), emphasis: run.emphasis)) }
                if !tailStr.isEmpty { tail.append(Run(.fixed(tailStr), emphasis: run.emphasis)) }
                didSplit = true
            }
        }
        return (head, tail)
    }
}

private struct ParagraphRow: View {
    @Binding var paragraph: Paragraph
    let marker: ParagraphMarker
    @Binding var focusRequest: FocusRequest?
    let controller: ProseFormattingController
    let onSplit: (Int) -> Void
    let onMergeBackward: () -> Void

    var isPlain: Bool {
        paragraph.runs.allSatisfy { run in
            if case .fixed = run.content { return true }
            return false
        }
    }

    var containsSlot: Bool {
        paragraph.runs.contains { run in
            if case .slot = run.content { return true }
            return false
        }
    }

    var plainText: String {
        paragraph.runs.map { run in
            if case .fixed(let s) = run.content { return s }
            return ""
        }.joined()
    }

    var displayText: String {
        paragraph.runs.map { run -> String in
            switch run.content {
            case .fixed(let s):
                return s
            case .token(let token):
                return "«\(tokenName(token))»"
            case .slot(let slot):
                if let freeText = slot.freeText, !freeText.isEmpty {
                    return freeText
                } else if let index = slot.selectedIndex {
                    return slot.options[index]
                } else {
                    return "[" + slot.options.joined(separator: " / ") + "]"
                }
            }
        }.joined()
    }

    private func tokenName(_ token: DataToken) -> String {
        switch token {
        case .patientFullName: return "Patient name"
        case .patientFirstName: return "Patient first name"
        case .patientLastName: return "Patient last name"
        case .patientDOB: return "Patient DOB"
        case .examDate: return "Exam date"
        case .practitionerName: return "Practitioner name"
        case .practitionerCredentials: return "Practitioner credentials"
        }
    }

    var body: some View {
        if isPlain {
            HStack(alignment: .top, spacing: 6) {
                markerView
                ZStack(alignment: .leading) {
                    RichParagraphEditor(
                        paragraphID: paragraph.id,
                        runs: $paragraph.runs,
                        style: $paragraph.style,
                        controller: controller,
                        focusRequest: $focusRequest,
                        onSplit: onSplit,
                        onMergeBackward: onMergeBackward
                    )
                    .frame(minHeight: max(standardFieldHeight, 60))
                    if plainText.isEmpty {
                        Text("Type subjective here")
                            .foregroundStyle(Color(UIColor.placeholderText))
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
            }
        } else if containsSlot {
            slotFillRow
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayText)
                Text("Formatted text — inline editing coming in a later step")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// The display-only list glyph shown to the left of the field. Body
    /// paragraphs show nothing.
    @ViewBuilder private var markerView: some View {
        switch marker {
        case .none:
            EmptyView()
        case .bullet:
            Text("•").padding(.top, 8)
        case .number(let n):
            Text("\(n).").padding(.top, 8)
        }
    }

    /// Lays out the paragraph's runs top-to-bottom: adjacent `.fixed` runs are
    /// merged into a single `Text` for readability, and each `.slot` run gets
    /// its own `SlotFillControl`. A true inline wrap is deferred polish.
    private var slotFillRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(runSegments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .fixed(let string):
                    Text(string)
                case .slot(let index):
                    SlotFillControl(slot: slotBinding(at: index))
                }
            }
        }
    }

    /// A segment is either a merged block of adjacent fixed/token text, or a
    /// single slot identified by its index in `paragraph.runs`.
    private enum RunSegment {
        case fixed(String)
        case slot(Int)
    }

    private var runSegments: [RunSegment] {
        var segments: [RunSegment] = []
        var pending = ""
        func flush() {
            if !pending.isEmpty {
                segments.append(.fixed(pending))
                pending = ""
            }
        }
        for (index, run) in paragraph.runs.enumerated() {
            switch run.content {
            case .fixed(let s):
                pending += s
            case .token(let token):
                pending += "«\(tokenName(token))»"
            case .slot:
                flush()
                segments.append(.slot(index))
            }
        }
        flush()
        return segments
    }

    /// Builds a two-way binding to the `Slot` stored in `paragraph.runs[index]`,
    /// preserving that run's emphasis and only replacing its content.
    private func slotBinding(at index: Int) -> Binding<Slot> {
        Binding(
            get: {
                if case .slot(let slot) = paragraph.runs[index].content {
                    return slot
                }
                return Slot(options: [])
            },
            set: { newValue in
                paragraph.runs[index].content = .slot(newValue)
            }
        )
    }
}

private struct SlotFillControl: View {
    @Binding var slot: Slot

    private var selectionIndex: Binding<Int> {
        Binding(
            get: { slot.selectedIndex ?? -1 },
            set: { newValue in
                if newValue == -1 {
                    slot.selectedIndex = nil
                } else {
                    slot.selectedIndex = newValue
                }
            }
        )
    }

    private var freeTextBinding: Binding<String> {
        Binding(
            get: { slot.freeText ?? "" },
            set: { newValue in
                slot.freeText = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var resolvedValue: String {
        if let freeText = slot.freeText, !freeText.isEmpty {
            return freeText
        } else if let index = slot.selectedIndex {
            return slot.options[index]
        } else {
            return "(unfilled)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Choose", selection: selectionIndex) {
                Text("—").tag(-1)
                ForEach(slot.options.indices, id: \.self) { i in
                    Text(slot.options[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)

            SelectAllTextField(placeholder: "or type your own", text: freeTextBinding)

            Text(resolvedValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var content = ProseContent(paragraphs: [
            Paragraph(runs: [
                Run(.fixed("This patient was seen today for screening. All testing today was within normal limits."))
            ]),
            Paragraph(runs: [
                Run(.fixed("In my professional opinion, the requirements are met."), emphasis: .bold)
            ]),
            Paragraph(runs: [
                Run(.fixed("The patient's unaided vision has since improved ")),
                Run(.slot(Slot(options: [
                    "following cataract surgery",
                    "following laser refractive surgery",
                    "as a result of a refractive shift"
                ]))),
                Run(.fixed(". Acuity is now 20/20 OU."))
            ])
        ])
        var body: some View {
            ScrollView { ProseEditor(content: $content).padding() }
        }
    }
    return Demo()
}
