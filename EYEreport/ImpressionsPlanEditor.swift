import SwiftUI
import UIKit

/// Editor for the Impressions / Plan block. Edits exactly the sections the
/// block carries (normally "Impressions:" and "Plan:") — sections are not added
/// or removed here. Each section's body is free prose in a consolidated
/// rich-text box (the same surface as the Prose block): bold/italic/underline
/// on selections, bullet/numbered lists from the shared toolbar, Return = a new
/// line in the same box. One toolbar drives both boxes — it follows whichever
/// box holds focus. Section labels stay behind the "Edit fields" toggle.
///
/// The rectangular box around the block is drawn by ReportRenderer at output
/// time (ImpressionsPlanContent.boxed), NOT here. List markers in the boxes'
/// gutters are edit-time chrome drawn by ProseListTextView; the renderer draws
/// its own at print, so there is no double marker.
struct ImpressionsPlanEditor: View {
    @Binding var content: ImpressionsPlanContent
    var focus: BlockFocusChain? = nil
    @StateObject private var formatting = ProseFormattingController()
    @State private var isEditingFields = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Edit fields", isOn: $isEditingFields)
                .toggleStyle(.switch)

            FormattingToolbar(controller: formatting)
                .frame(height: 32)
                .padding(.bottom, -10)

            // Sections are fixed (never added/removed here), so ForEach element
            // bindings are safe — the last-element-deleted crash needs deletion.
            ForEach($content.sections) { $section in
                sectionView($section)
            }
        }
        .onAppear { normalizeSections() }
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionView(_ section: Binding<LabeledSection>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingFields {
                // The label is rich content: same box, same toolbar as the
                // bodies. Bold "Impressions:" is the seeded default, not a
                // render-time constant, so it can be restyled here.
                ZStack(alignment: .topLeading) {
                    ProseBlockEditor(content: section.label, controller: formatting)
                        .frame(minHeight: standardFieldHeight)
                    if isEffectivelyEmpty(section.label.wrappedValue) {
                        Text("Section label")
                            .foregroundStyle(Color(UIColor.placeholderText))
                            .padding(.leading, 8)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: 240)
            } else {
                Text(styledPreview(of: section.label.wrappedValue))
            }

            if section.body.wrappedValue.isAllFixed {
                // Each body box is ONE stop in the document tab chain, keyed by
                // section id (the labels stay chain-free — they're behind the
                // "Edit fields" toggle, structural not data entry).
                ZStack(alignment: .topLeading) {
                    ProseBlockEditor(content: section.body, controller: formatting,
                                     focusKey: focus.key(FocusFields.impressionsPlanBody(section.wrappedValue.id)),
                                     focusBinding: focus.binding,
                                     onTab: focus.tab(FocusFields.impressionsPlanBody(section.wrappedValue.id)))
                        .frame(minHeight: max(standardFieldHeight, 60))
                    if isEffectivelyEmpty(section.body.wrappedValue) {
                        Text(placeholder(for: plainText(of: section.label.wrappedValue)))
                            .foregroundStyle(Color(UIColor.placeholderText))
                            .padding(.leading, 8)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                // A body containing slot/token runs can't go through the
                // consolidated box (its conversion silently drops non-fixed
                // runs). No current template puts slots here, so a read-only
                // view is enough if one ever appears.
                Text(plainText(of: section.body.wrappedValue))
                Text("Contains a slot/token — not editable here")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Body inspection (mirrors ProseEditor's routing checks)
    // Consolidated-box routing uses the shared `ProseContent.isAllFixed`
    // (FocusChain.swift) — the same check FocusOrder uses for the tab chain.

    /// A single blank paragraph (fresh section) — drives the placeholder overlay.
    private func isEffectivelyEmpty(_ body: ProseContent) -> Bool {
        body.paragraphs.count <= 1 && body.paragraphs.allSatisfy { para in
            para.runs.allSatisfy { if case .fixed(let s) = $0.content { return s.isEmpty }; return false }
        }
    }

    private func plainText(of body: ProseContent) -> String {
        body.paragraphs.map { para in
            para.runs.map { run in
                if case .fixed(let s) = run.content { return s }
                return "…"
            }.joined()
        }.joined(separator: "\n")
    }

    private func placeholder(for label: String) -> String {
        let trimmed = label.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).lowercased()
        return trimmed.isEmpty ? "Type here" : "Type \(trimmed) here"
    }

    /// Read-only display of a rich label with its emphasis applied (bold /
    /// italic / underline), so the styled label reads true with "Edit fields"
    /// off. Paragraph list styles aren't reflected here — a label is
    /// conventionally a single line. Base size is .headline (user-tuned;
    /// .subheadline was too small, .title2 too big). The font is set ONLY
    /// here, per piece — no outer .font() on the Text; see LESSONS on
    /// chained .font.
    private func styledPreview(of content: ProseContent) -> AttributedString {
        var result = AttributedString()
        for (i, para) in content.paragraphs.enumerated() {
            if i > 0 { result += AttributedString("\n") }
            for run in para.runs {
                guard case .fixed(let s) = run.content else { continue }
                var piece = AttributedString(s)
                var font: Font = .headline
                switch run.emphasis {
                case .bold, .boldUnderline:               font = font.bold()
                case .italic, .italicUnderline:           font = font.italic()
                case .boldItalic, .boldItalicUnderline:   font = font.bold().italic()
                default: break
                }
                piece.font = font
                switch run.emphasis {
                case .underline, .boldUnderline, .italicUnderline, .boldItalicUnderline:
                    piece.underlineStyle = .single
                default: break
                }
                result += piece
            }
        }
        return result
    }

    // MARK: - Seeding

    /// Seed the two standard sections when the block arrives empty, and give any
    /// section with no paragraphs one blank BULLET paragraph — the box opens
    /// with a ready-to-type bullet (deletable, or Return-Return to end the
    /// list), since bulleted entries are the overwhelmingly common case here.
    /// Existing sections and their content are otherwise left untouched.
    private func normalizeSections() {
        if content.sections.isEmpty {
            content.sections = [
                LabeledSection(label: "Impressions:", body: singleBlankBullet()),
                LabeledSection(label: "Plan:", body: singleBlankBullet()),
            ]
            return
        }
        for i in content.sections.indices where content.sections[i].body.paragraphs.isEmpty {
            content.sections[i].body = singleBlankBullet()
        }
    }

    private func singleBlankBullet() -> ProseContent {
        ProseContent(paragraphs: [Paragraph(runs: [Run(.fixed(""))], style: .bullet)])
    }
}

#Preview {
    struct Demo: View {
        @State private var content = ImpressionsPlanContent(sections: [
            LabeledSection(label: "Impressions:", body: ProseContent(paragraphs: [
                Paragraph(runs: [Run(.fixed("Mild dry eye, both eyes"))], style: .bullet),
                Paragraph(runs: [Run(.fixed("No diabetic retinopathy"))], style: .bullet),
            ])),
            LabeledSection(label: "Plan:", body: ProseContent(paragraphs: [
                Paragraph(runs: [Run(.fixed("Preservative-free artificial tears QID"))], style: .bullet),
                Paragraph(runs: [Run(.fixed("Review in 6 months"))], style: .bullet),
            ])),
        ])
        var body: some View {
            ScrollView { ImpressionsPlanEditor(content: $content).padding() }
        }
    }
    return Demo()
}
