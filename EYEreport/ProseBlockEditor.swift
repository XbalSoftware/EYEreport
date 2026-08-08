import SwiftUI
import UIKit

// MARK: - Custom attribute carrying a paragraph's list style

extension NSAttributedString.Key {
    /// Rides on a paragraph's characters (value "bullet" / "numbered") so the
    /// backing string stays free of marker glyphs — the marker is DRAWN in the
    /// gutter (see `ProseListTextView`), never inserted as text. Absent = body.
    static let proseListStyle = NSAttributedString.Key("proseListStyle")
}

// MARK: - [Paragraph] <-> NSAttributedString (whole prose block, all-`.fixed`)

/// Converts a whole `[Paragraph]` (all runs `.fixed`, any emphasis) to and from a
/// single NSAttributedString whose paragraphs are separated by "\n". Character
/// emphasis reuses `RichRunConversion`; each paragraph's `.body/.bullet/.numbered`
/// style is stored on `.proseListStyle` + a hanging indent, NOT as marker text.
enum ProseBlockConversion {
    static let listIndent: CGFloat = 22

    private static func listValue(for style: ParagraphStyle) -> String? {
        switch style {
        case .bullet:   return "bullet"
        case .numbered: return "numbered"
        default:        return nil
        }
    }

    private static func style(forListValue value: String?) -> ParagraphStyle {
        switch value {
        case "bullet":   return .bullet
        case "numbered": return .numbered
        default:         return .body
        }
    }

    /// Applies a paragraph's list style over `range` (which must include the
    /// paragraph's trailing "\n" so TextKit treats it as one paragraph). Empty
    /// ranges are skipped — attributes can't attach to zero characters.
    static func applyParagraphAttributes(_ s: NSMutableAttributedString,
                                         range: NSRange,
                                         listValue: String?) {
        guard range.length > 0 else { return }
        let ps = NSMutableParagraphStyle()
        if listValue != nil {
            ps.firstLineHeadIndent = listIndent
            ps.headIndent = listIndent
        }
        s.addAttribute(.paragraphStyle, value: ps, range: range)
        if let listValue {
            s.addAttribute(.proseListStyle, value: listValue, range: range)
        } else {
            s.removeAttribute(.proseListStyle, range: range)
        }
    }

    /// The parked ("pending") list style a paragraph list implies on load: a
    /// trailing EMPTY list paragraph (e.g. a seeded ready-to-type bullet) has
    /// no characters to carry its style as text attributes, so the editor
    /// re-derives it from the model whenever it (re)builds the text view.
    static func trailingEmptyListValue(_ paragraphs: [Paragraph]) -> String? {
        guard let last = paragraphs.last,
              last.runs.allSatisfy({ if case .fixed(let s) = $0.content { return s.isEmpty }; return false })
        else { return nil }
        return listValue(for: last.style)
    }

    static func attributedString(from paragraphs: [Paragraph]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let plainAttrs = RichRunConversion.attributes(for: (false, false, false))
        for (i, para) in paragraphs.enumerated() {
            let start = result.length
            result.append(RichRunConversion.attributedString(from: para.runs))
            if i < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: plainAttrs))
            }
            let range = NSRange(location: start, length: result.length - start)
            applyParagraphAttributes(result, range: range, listValue: listValue(for: para.style))
        }
        return result
    }

    static func paragraphs(from attributed: NSAttributedString) -> [Paragraph] {
        let ns = attributed.string as NSString
        guard ns.length > 0 else { return [Paragraph(runs: [Run(.fixed(""))])] }

        var result: [Paragraph] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byParagraphs]) { _, subRange, enclosing, _ in
            // Read the list style from any character in the paragraph (prefer the
            // body, fall back to the trailing "\n" for an empty line).
            let attrLoc = subRange.length > 0 ? subRange.location
                        : (enclosing.length > 0 ? enclosing.location : nil)
            var listValue: String?
            if let attrLoc {
                listValue = attributed.attribute(.proseListStyle, at: attrLoc, effectiveRange: nil) as? String
            }
            let runs = subRange.length > 0
                ? RichRunConversion.runs(from: attributed.attributedSubstring(from: subRange))
                : [Run(.fixed(""))]
            result.append(Paragraph(runs: runs, style: style(forListValue: listValue)))
        }

        // enumerateSubstrings does not emit a trailing empty line after a final
        // "\n"; preserve it as an empty paragraph inheriting the prior style, so a
        // fresh Return-created line survives the round-trip.
        if ns.character(at: ns.length - 1) == unichar(10) {
            let inherited = result.last?.style ?? .body
            result.append(Paragraph(runs: [Run(.fixed(""))], style: inherited))
        }
        return result.isEmpty ? [Paragraph(runs: [Run(.fixed(""))])] : result
    }
}

// MARK: - UITextView that draws list markers in the gutter

/// A non-scrolling UITextView that draws a "•" or "N." marker in the left gutter
/// for each paragraph carrying `.proseListStyle`. Numbering is derived here (count
/// of consecutive numbered paragraphs), matching `ReportRenderer.numberedOrdinal`,
/// so the editor marker equals the printed number.
final class ProseListTextView: UITextView {
    /// The list style ("bullet"/"numbered") of the caret's EMPTY line — an
    /// empty box, or the trailing line a Return just created. A zero-length
    /// paragraph has no characters to carry `.proseListStyle`, so the
    /// coordinator parks the style here: `draw` previews its marker, and the
    /// first character typed materializes it (via typing attributes).
    var pendingListValue: String?

    /// Same Tab contract as FocusableTextField/-TextView in
    /// SelectAllTextField.swift: when a focus chain is attached, Tab /
    /// Shift-Tab become navigation commands instead of inserting whitespace.
    /// (The coordinator's shouldChangeTextIn blocks the "\t" character itself.)
    var tabEnabled = false
    var onTabCommand: ((_ backward: Bool) -> Void)?

    /// ⌘B / ⌘I / ⌘U routed to the coordinator's toggle methods (the same ones
    /// the FormattingToolbar buttons call), so the emphasis lands in the app's
    /// Run model rather than UITextView's built-in `toggleBoldface:` (which
    /// applies system-font attributes and needs `allowsEditingTextAttributes`).
    var onBoldCommand: (() -> Void)?
    var onItalicCommand: (() -> Void)?
    var onUnderlineCommand: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(handleBoldCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(handleItalicCommand)),
            UIKeyCommand(input: "u", modifierFlags: .command, action: #selector(handleUnderlineCommand)),
        ]
    }

    @objc private func handleBoldCommand() { onBoldCommand?() }
    @objc private func handleItalicCommand() { onItalicCommand?() }
    @objc private func handleUnderlineCommand() { onUnderlineCommand?() }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if tabEnabled, let key = presses.first?.key, key.keyCode == .keyboardTab {
            onTabCommand?(key.modifierFlags.contains(.shift))
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let ns = attributedText.string as NSString
        let lm = layoutManager
        let markerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.systemRed
        ]

        var number = 0
        if ns.length > 0 {
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                                   options: [.byParagraphs]) { _, subRange, enclosing, _ in
                let attrLoc = subRange.length > 0 ? subRange.location
                            : (enclosing.length > 0 ? enclosing.location : nil)
                var listValue: String?
                if let attrLoc {
                    listValue = self.attributedText.attribute(.proseListStyle, at: attrLoc, effectiveRange: nil) as? String
                }

                let marker: String?
                switch listValue {
                case "bullet":   number = 0; marker = "•"
                case "numbered": number += 1; marker = "\(number)."
                default:         number = 0; marker = nil
                }
                guard let marker, enclosing.length > 0 else { return }

                let glyphRange = lm.glyphRange(forCharacterRange: enclosing, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { return }
                let lineRect = lm.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                let point = CGPoint(x: self.textContainerInset.left,
                                    y: lineRect.minY + self.textContainerInset.top)
                (marker as NSString).draw(at: point, withAttributes: markerAttrs)
            }
        }

        // The empty caret line has no characters, so its marker comes from the
        // parked pending style. `number` still holds the length of a trailing
        // numbered run, so the previewed number is the one typing will produce.
        // TextKit's "extra line fragment" is exactly this empty last line.
        if let pending = pendingListValue,
           ns.length == 0 || ns.character(at: ns.length - 1) == unichar(10) {
            let marker = pending == "numbered" ? "\(number + 1)." : "•"
            let point = CGPoint(x: textContainerInset.left,
                                y: lm.extraLineFragmentUsedRect.minY + textContainerInset.top)
            (marker as NSString).draw(at: point, withAttributes: markerAttrs)
        }
    }
}

// MARK: - ProseBlockEditor

/// The consolidated Prose editor: ONE text box editing every paragraph of a
/// `ProseContent`. Return makes a new line/paragraph in the same box; a selection
/// spanning several lines can be turned into a bullet/numbered list in one tap.
/// Formatting is driven by the shared `ProseFormattingController` + top-of-block
/// `FormattingToolbar`. Used only when every paragraph is all-`.fixed`; blocks
/// containing slots/tokens fall back to the per-paragraph editor.
struct ProseBlockEditor: UIViewRepresentable {
    @Binding var content: ProseContent
    let controller: ProseFormattingController

    // Optional focus-chain contract, same shape as SelectAllTextField's: the
    // whole box is ONE tab stop. All nil (the default) = not in any chain.
    var focusKey: String? = nil
    var focusBinding: Binding<String?>? = nil
    var onTab: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> ProseListTextView {
        let tv = ProseListTextView()
        _ = tv.layoutManager // force TextKit 1 (reliable gutter drawing)
        tv.isScrollEnabled = false
        tv.contentMode = .redraw
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        tv.backgroundColor = UIColor.secondarySystemBackground
        tv.layer.cornerRadius = 6
        tv.layer.borderWidth = 0.5
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.autocorrectionType = .no
        // Red misspelling underline WITHOUT autocorrect: spellchecking is
        // independent of autocorrection, but iOS's `.default` only enables it
        // alongside autocorrect — so force it on explicitly.
        tv.spellCheckingType = .yes
        tv.autocapitalizationType = .none
        tv.typingAttributes = RichRunConversion.attributes(for: (false, false, false))
        tv.delegate = context.coordinator
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)

        context.coordinator.textView = tv
        tv.attributedText = ProseBlockConversion.attributedString(from: content.paragraphs)
        tv.pendingListValue = ProseBlockConversion.trailingEmptyListValue(content.paragraphs)
        context.coordinator.lastParagraphs = content.paragraphs
        return tv
    }

    func updateUIView(_ uiView: ProseListTextView, context: Context) {
        context.coordinator.parent = self
        uiView.tabEnabled = (onTab != nil)
        uiView.onTabCommand = { [weak coordinator = context.coordinator] backward in
            coordinator?.parent.onTab?(backward)
        }
        uiView.onBoldCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleBold()
        }
        uiView.onItalicCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleItalic()
        }
        uiView.onUnderlineCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleUnderline()
        }
        // Claim first responder when the document-wide focus chain points at
        // this box (Tab arriving from another field).
        if let key = focusKey,
           let binding = focusBinding,
           binding.wrappedValue == key,
           !uiView.isFirstResponder,
           !context.coordinator.isClaimingFocus {
            context.coordinator.isClaimingFocus = true
            DispatchQueue.main.async { [weak uiView] in
                uiView?.becomeFirstResponder()
            }
        }
        // While the box has focus, the text view IS the source of truth. With a
        // deeper binding chain (block enum → sections element → body, as in
        // ImpressionsPlanEditor) SwiftUI can deliver a STALE echo of an
        // in-flight keystroke here, and rebuilding from it yanks the caret
        // backward a character. Nothing in the app mutates prose externally
        // while the user is typing in it, so skip rebuilds until focus leaves.
        guard !uiView.isFirstResponder else { return }
        if !context.coordinator.paragraphsEqual(content.paragraphs, context.coordinator.lastParagraphs) {
            let sel = uiView.selectedRange
            uiView.attributedText = ProseBlockConversion.attributedString(from: content.paragraphs)
            uiView.pendingListValue = ProseBlockConversion.trailingEmptyListValue(content.paragraphs)
            uiView.selectedRange = NSRange(location: min(sel.location, uiView.textStorage.length), length: 0)
            context.coordinator.lastParagraphs = content.paragraphs
            uiView.invalidateIntrinsicContentSize()
            uiView.setNeedsDisplay()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: ProseListTextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(size.height, standardFieldHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate, ProseFormattingTarget {
        var parent: ProseBlockEditor
        weak var textView: ProseListTextView?
        var lastParagraphs: [Paragraph] = []
        fileprivate var isClaimingFocus = false

        init(_ parent: ProseBlockEditor) { self.parent = parent }

        func paragraphsEqual(_ a: [Paragraph], _ b: [Paragraph]) -> Bool {
            guard a.count == b.count else { return false }
            for (p1, p2) in zip(a, b) {
                guard styleEqual(p1.style, p2.style), p1.runs.count == p2.runs.count else { return false }
                for (r1, r2) in zip(p1.runs, p2.runs) {
                    guard r1.emphasis == r2.emphasis,
                          case .fixed(let s1) = r1.content,
                          case .fixed(let s2) = r2.content, s1 == s2 else { return false }
                }
            }
            return true
        }

        /// `ParagraphStyle` carries an associated value (`.indented`), so it is not
        /// auto-`Equatable`; compare structurally without touching the model.
        private func styleEqual(_ a: ParagraphStyle, _ b: ParagraphStyle) -> Bool {
            switch (a, b) {
            case (.body, .body), (.bullet, .bullet), (.numbered, .numbered): return true
            case let (.indented(l1), .indented(l2)): return l1 == l2
            default: return false
            }
        }

        // MARK: Return — end the list on an empty item, continue it on a full one

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let listTV = tv as? ProseListTextView

            // Tab is focus navigation when a chain is attached — never text.
            if text == "\t", listTV?.tabEnabled == true { return false }

            // A deletion that reaches the very end of the text consumes the
            // trailing empty line — retire its parked style with it, so
            // materializePendingIfNeeded doesn't stamp it onto whatever
            // paragraph becomes last.
            if text.isEmpty, range.length > 0, listTV?.pendingListValue != nil,
               range.location + range.length == (tv.attributedText.string as NSString).length {
                listTV?.pendingListValue = nil
            }

            guard text == "\n" else { return true }
            let ns = tv.attributedText.string as NSString
            let para = ns.paragraphRange(for: range)
            let bodyRange = NSRange(location: para.location,
                                    length: max(0, para.length - (para.length > 0 && ns.character(at: para.location + para.length - 1) == unichar(10) ? 1 : 0)))
            let isEmpty = bodyRange.length == 0
            // A zero-length paragraph (trailing empty line / empty box) keeps its
            // style parked on the view rather than on characters.
            let listValue = para.length > 0
                ? tv.attributedText.attribute(.proseListStyle, at: para.location, effectiveRange: nil) as? String
                : listTV?.pendingListValue
            if isEmpty, listValue != nil {
                // Convert this empty list item back to body instead of adding
                // another empty bullet/number (standard list UX).
                let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
                ProseBlockConversion.applyParagraphAttributes(mutable, range: para, listValue: nil)
                tv.attributedText = mutable
                tv.selectedRange = NSRange(location: para.location, length: 0)
                listTV?.pendingListValue = nil
                applyListToTypingAttributes(tv, listValue: nil)
                pushParagraphs(tv)
                tv.setNeedsDisplay()
                refreshController(tv)
                return false
            }

            // Return on a NON-empty list item continues the list: the new line
            // has no characters yet, so park its style — the marker previews it
            // and the first typed character materializes it. (A Return landing
            // mid-document puts real attributed characters in the new paragraph
            // instead, and syncCaretState clears the parked style right away.)
            listTV?.pendingListValue = isEmpty ? nil : listValue
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            materializePendingIfNeeded(tv)
            pushParagraphs(tv)
            tv.invalidateIntrinsicContentSize()
            tv.setNeedsDisplay()
        }

        /// The moment the trailing (previously empty) line gains its first
        /// characters, stamp the parked pending style onto that paragraph as
        /// REAL attributes and retire the parked copy. Deterministic — does not
        /// depend on UIKit having kept the custom key in typingAttributes.
        private func materializePendingIfNeeded(_ tv: UITextView) {
            guard let listTV = tv as? ProseListTextView, let pending = listTV.pendingListValue else { return }
            let ns = tv.attributedText.string as NSString
            // Doc still empty, or still ends with "\n": the trailing line is
            // still empty — the style stays parked.
            guard ns.length > 0, ns.character(at: ns.length - 1) != unichar(10) else { return }
            let para = ns.paragraphRange(for: NSRange(location: ns.length, length: 0))
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            ProseBlockConversion.applyParagraphAttributes(mutable, range: para, listValue: pending)
            let sel = tv.selectedRange
            tv.attributedText = mutable
            tv.selectedRange = sel
            listTV.pendingListValue = nil
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            isClaimingFocus = false
            parent.focusBinding?.wrappedValue = parent.focusKey
            parent.controller.active = self
            // Typing attributes must reflect a parked style BEFORE the first
            // keystroke — focus-in does not reliably fire a selection change.
            syncCaretState(tv)
            refreshController(tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            // Clear the shared focus key when THIS box resigns and still owns
            // it, so a later rebuild doesn't re-claim focus back here.
            if parent.focusBinding?.wrappedValue == parent.focusKey {
                parent.focusBinding?.wrappedValue = nil
            }
            if parent.controller.isActive(self) { parent.controller.clear() }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            syncCaretState(tv)
            if parent.controller.isActive(self) { refreshController(tv) }
        }

        /// Keeps the caret's typing attributes in step with the paragraph under
        /// the caret. UIKit re-derives typing attributes across a paragraph
        /// boundary WITHOUT custom keys — the paragraph indent survives a
        /// Return but `.proseListStyle` does not — so both are re-derived here
        /// from the caret's own paragraph (or from the parked pending style
        /// when the caret sits on the empty trailing line). The parked style is
        /// NOT cleared here: it belongs to the trailing empty line, not the
        /// caret, and survives caret moves and focus changes until that line
        /// gains text (materialize), is deleted, or its list is ended.
        private func syncCaretState(_ tv: UITextView) {
            let ns = tv.attributedText.string as NSString
            let caret = NSRange(location: min(tv.selectedRange.location, ns.length), length: 0)
            let para = ns.paragraphRange(for: caret)
            let listValue: String?
            if para.length > 0 {
                listValue = tv.attributedText.attribute(.proseListStyle, at: para.location, effectiveRange: nil) as? String
            } else {
                listValue = (tv as? ProseListTextView)?.pendingListValue
            }
            applyListToTypingAttributes(tv, listValue: listValue)
        }

        /// Sets/clears the list attributes on the typing attributes, preserving
        /// the current B/I/U font traits.
        private func applyListToTypingAttributes(_ tv: UITextView, listValue: String?) {
            var typing = tv.typingAttributes
            let ps = NSMutableParagraphStyle()
            if listValue != nil {
                ps.firstLineHeadIndent = ProseBlockConversion.listIndent
                ps.headIndent = ProseBlockConversion.listIndent
            }
            typing[.paragraphStyle] = ps
            if let listValue {
                typing[.proseListStyle] = listValue
            } else {
                typing.removeValue(forKey: .proseListStyle)
            }
            tv.typingAttributes = typing
        }

        private func pushParagraphs(_ tv: UITextView) {
            var paras = ProseBlockConversion.paragraphs(from: tv.attributedText)
            // The trailing empty paragraph can't carry attributes in the text
            // view, so its style is whatever is parked as pending — not what
            // the conversion's inherit rule guessed. Keep the model honest.
            if let last = paras.last, isEmptyParagraph(last) {
                let style: ParagraphStyle
                switch (tv as? ProseListTextView)?.pendingListValue {
                case "bullet":   style = .bullet
                case "numbered": style = .numbered
                default:         style = .body
                }
                paras[paras.count - 1] = Paragraph(runs: last.runs, style: style)
            }
            lastParagraphs = paras
            parent.content.paragraphs = paras
        }

        private func isEmptyParagraph(_ p: Paragraph) -> Bool {
            p.runs.allSatisfy {
                if case .fixed(let s) = $0.content { return s.isEmpty }
                return false
            }
        }

        // MARK: Formatting — B/I/U on the selection

        private func currentTraits(_ tv: UITextView) -> (bold: Bool, italic: Bool, underline: Bool) {
            let range = tv.selectedRange
            let attrs: [NSAttributedString.Key: Any]
            if range.length > 0, tv.attributedText.length > 0 {
                attrs = tv.attributedText.attributes(at: min(range.location, tv.attributedText.length - 1), effectiveRange: nil)
            } else {
                attrs = tv.typingAttributes
            }
            let symbolic = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            return (symbolic.contains(.traitBold),
                    symbolic.contains(.traitItalic),
                    ((attrs[.underlineStyle] as? Int) ?? 0) != 0)
        }

        private func currentListValue(_ tv: UITextView) -> String? {
            let ns = tv.attributedText.string as NSString
            guard ns.length > 0 else { return (tv as? ProseListTextView)?.pendingListValue }
            let para = ns.paragraphRange(for: tv.selectedRange)
            guard para.length > 0 else { return (tv as? ProseListTextView)?.pendingListValue }
            return tv.attributedText.attribute(.proseListStyle, at: para.location, effectiveRange: nil) as? String
        }

        private func refreshController(_ tv: UITextView) {
            let traits = currentTraits(tv)
            let list = currentListValue(tv)
            parent.controller.refresh(bold: traits.bold,
                                      italic: traits.italic,
                                      underline: traits.underline,
                                      bullet: list == "bullet",
                                      numbered: list == "numbered")
        }

        func toggleBold() { toggleTrait { (!$0.bold, $0.italic, $0.underline) } }
        func toggleItalic() { toggleTrait { ($0.bold, !$0.italic, $0.underline) } }
        func toggleUnderline() { toggleTrait { ($0.bold, $0.italic, !$0.underline) } }

        private func toggleTrait(_ transform: ((bold: Bool, italic: Bool, underline: Bool)) -> (bold: Bool, italic: Bool, underline: Bool)) {
            guard let tv = textView else { return }
            let sel = tv.selectedRange
            let newTraits = transform(currentTraits(tv))
            if sel.length > 0 {
                let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
                // Preserve each character's paragraph style / list attribute; only
                // swap the emphasis-bearing attributes over the selection.
                if !newTraits.underline { mutable.removeAttribute(.underlineStyle, range: sel) }
                mutable.addAttributes(RichRunConversion.attributes(for: newTraits), range: sel)
                tv.attributedText = mutable
                tv.selectedRange = sel
                pushParagraphs(tv)
                tv.setNeedsDisplay()
            } else {
                var typing = tv.typingAttributes
                for (k, v) in RichRunConversion.attributes(for: newTraits) { typing[k] = v }
                if !newTraits.underline { typing[.underlineStyle] = nil }
                tv.typingAttributes = typing
            }
            refreshController(tv)
        }

        // MARK: Formatting — bullet/numbered across the selected paragraphs

        func toggleBullet() { applyList("bullet") }
        func toggleNumbered() { applyList("numbered") }

        private func applyList(_ target: String) {
            guard let tv = textView else { return }
            let ns = tv.attributedText.string as NSString

            // A zero-length caret paragraph (empty box, or the trailing line a
            // Return just created) has no characters to attribute — park the
            // style on the view instead: the gutter previews the marker, and
            // the first typed character materializes it.
            let caretPara = ns.paragraphRange(for: NSRange(location: min(tv.selectedRange.location, ns.length), length: 0))
            if tv.selectedRange.length == 0, caretPara.length == 0 {
                tv.pendingListValue = (tv.pendingListValue == target) ? nil : target
                applyListToTypingAttributes(tv, listValue: tv.pendingListValue)
                pushParagraphs(tv)
                tv.setNeedsDisplay()
                refreshController(tv)
                return
            }

            let ranges = paragraphRanges(ns, intersecting: tv.selectedRange)
            guard !ranges.isEmpty else { return }
            let allTarget = ranges.allSatisfy { r in
                r.length > 0 && (tv.attributedText.attribute(.proseListStyle, at: r.location, effectiveRange: nil) as? String) == target
            }
            let newValue: String? = allTarget ? nil : target
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            for r in ranges {
                ProseBlockConversion.applyParagraphAttributes(mutable, range: r, listValue: newValue)
            }
            let sel = tv.selectedRange
            tv.attributedText = mutable
            tv.selectedRange = sel
            pushParagraphs(tv)
            tv.setNeedsDisplay()
            syncCaretState(tv)
            refreshController(tv)
        }

        /// The enclosing (newline-inclusive) ranges of every paragraph the
        /// selection touches; for a caret, just its own paragraph.
        private func paragraphRanges(_ ns: NSString, intersecting sel: NSRange) -> [NSRange] {
            guard ns.length > 0 else { return [] }
            var ranges: [NSRange] = []
            let selEnd = sel.location + sel.length
            var loc = min(sel.location, ns.length)
            // Walk paragraph by paragraph across the selection (just the caret's own
            // paragraph when the selection is empty).
            repeat {
                let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
                ranges.append(para)
                let next = para.location + para.length
                if next >= ns.length { break }
                loc = next
            } while sel.length > 0 && loc < selEnd
            return ranges
        }
    }
}
