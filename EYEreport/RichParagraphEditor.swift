import SwiftUI
import UIKit

// MARK: - Emphasis <-> (bold, italic, underline) bijection

func emphasisToTraits(_ emphasis: Emphasis) -> (bold: Bool, italic: Bool, underline: Bool) {
    switch emphasis {
    case .regular:              return (false, false, false)
    case .bold:                 return (true,  false, false)
    case .italic:               return (false, true,  false)
    case .boldItalic:           return (true,  true,  false)
    case .underline:            return (false, false, true)
    case .boldUnderline:        return (true,  false, true)
    case .italicUnderline:      return (false, true,  true)
    case .boldItalicUnderline:  return (true,  true,  true)
    }
}

func traitsToEmphasis(_ traits: (bold: Bool, italic: Bool, underline: Bool)) -> Emphasis {
    switch (traits.bold, traits.italic, traits.underline) {
    case (false, false, false): return .regular
    case (true,  false, false): return .bold
    case (false, true,  false): return .italic
    case (true,  true,  false): return .boldItalic
    case (false, false, true):  return .underline
    case (true,  false, true):  return .boldUnderline
    case (false, true,  true):  return .italicUnderline
    case (true,  true,  true):  return .boldItalicUnderline
    }
}

// MARK: - [Run] <-> NSAttributedString (all-`.fixed` runs only)

enum RichRunConversion {
    static func attributedString(from runs: [Run]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            guard case .fixed(let string) = run.content else { continue }
            let traits = emphasisToTraits(run.emphasis)
            result.append(NSAttributedString(string: string, attributes: attributes(for: traits)))
        }
        return result
    }

    static func attributes(for traits: (bold: Bool, italic: Bool, underline: Bool)) -> [NSAttributedString.Key: Any] {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        var symbolicTraits: UIFontDescriptor.SymbolicTraits = []
        if traits.bold { symbolicTraits.insert(.traitBold) }
        if traits.italic { symbolicTraits.insert(.traitItalic) }
        let font: UIFont
        if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(symbolicTraits) {
            font = UIFont(descriptor: descriptor, size: baseFont.pointSize)
        } else {
            font = baseFont
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemRed
        ]
        if traits.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    static func runs(from attributedString: NSAttributedString) -> [Run] {
        let fullText = attributedString.string
        guard !fullText.isEmpty else {
            return [Run(.fixed(""))]
        }

        var result: [Run] = []
        var pendingText = ""
        var pendingTraits: (bold: Bool, italic: Bool, underline: Bool)?

        attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length)) { attrs, range, _ in
            let substring = (fullText as NSString).substring(with: range)
            let font = attrs[.font] as? UIFont
            let symbolicTraits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = symbolicTraits.contains(.traitBold)
            let italic = symbolicTraits.contains(.traitItalic)
            let underlineValue = attrs[.underlineStyle] as? Int ?? 0
            let underline = underlineValue != 0
            let traits = (bold, italic, underline)

            if let current = pendingTraits, current == traits {
                pendingText += substring
            } else {
                if let current = pendingTraits {
                    result.append(Run(.fixed(pendingText), emphasis: traitsToEmphasis(current)))
                }
                pendingText = substring
                pendingTraits = traits
            }
        }

        if let current = pendingTraits {
            result.append(Run(.fixed(pendingText), emphasis: traitsToEmphasis(current)))
        }

        return result.isEmpty ? [Run(.fixed(""))] : result
    }
}

private func == (lhs: (bold: Bool, italic: Bool, underline: Bool), rhs: (bold: Bool, italic: Bool, underline: Bool)) -> Bool {
    lhs.bold == rhs.bold && lhs.italic == rhs.italic && lhs.underline == rhs.underline
}

// MARK: - Keyboard accessory bar (Bold / Italic / Underline toggles)

/// A compact row of five rounded-rectangle formatting buttons (blue glyph on a
/// subtle gray fill; filled blue with a white glyph when active), clustered at
/// the trailing edge and pinned to the bottom of the bar so they cling to the
/// text field below. Custom `UIButton`s — not `UIBarButtonItem`s — are used for
/// this look, and like bar-button items they do NOT resign the focused text
/// field's first responder on tap.
final class FormattingAccessoryBar: UIView {
    let boldButton = FormattingAccessoryBar.makeButton(systemName: "bold")
    let italicButton = FormattingAccessoryBar.makeButton(systemName: "italic")
    let underlineButton = FormattingAccessoryBar.makeButton(systemName: "underline")
    let bulletButton = FormattingAccessoryBar.makeButton(systemName: "list.bullet")
    let numberedButton = FormattingAccessoryBar.makeButton(systemName: "list.number")

    init() {
        super.init(frame: .zero)
        let stack = UIStackView(arrangedSubviews: [boldButton, italicButton, underlineButton, bulletButton, numberedButton])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func makeButton(systemName: String) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: systemName,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
        config.cornerStyle = .medium
        config.baseForegroundColor = .systemBlue
        config.baseBackgroundColor = .secondarySystemFill
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        return UIButton(configuration: config)
    }

    func setActive(bold: Bool, italic: Bool, underline: Bool) {
        apply(boldButton, active: bold)
        apply(italicButton, active: italic)
        apply(underlineButton, active: underline)
    }

    func setStyleActive(bullet: Bool, numbered: Bool) {
        apply(bulletButton, active: bullet)
        apply(numberedButton, active: numbered)
    }

    func setEnabled(_ enabled: Bool) {
        [boldButton, italicButton, underlineButton, bulletButton, numberedButton].forEach { $0.isEnabled = enabled }
    }

    private func apply(_ button: UIButton, active: Bool) {
        var config = button.configuration
        config?.baseBackgroundColor = active ? .systemBlue : .secondarySystemFill
        config?.baseForegroundColor = active ? .white : .systemBlue
        button.configuration = config
    }
}

// MARK: - UITextView with ⌘B/⌘I/⌘U key commands

/// Routes ⌘B / ⌘I / ⌘U to the coordinator's toggle methods (same as the
/// FormattingToolbar buttons), so the slot/token fallback editor gets the same
/// keyboard shortcuts as the consolidated ProseBlockEditor.
final class RichKeyCommandTextView: UITextView {
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
}

// MARK: - RichParagraphEditor

/// Edits one paragraph's `[Run]` (all `.fixed`, any emphasis) as an
/// NSAttributedString via a UITextView. Formatting (B/I/U/•/#) is driven by the
/// shared, block-level `ProseFormattingController` and its top-of-block
/// `FormattingToolbar` — this field registers itself as the controller's active
/// field on begin-editing. Mirrors `SelectAllTextView`'s visual conventions but
/// does not participate in the shared focus chain.
struct RichParagraphEditor: UIViewRepresentable {
    let paragraphID: UUID
    @Binding var runs: [Run]
    @Binding var style: ParagraphStyle
    let controller: ProseFormattingController
    /// A shared, block-level pending caret placement. This field consumes it when
    /// its `paragraphID` matches (see `updateUIView`).
    @Binding var focusRequest: FocusRequest?
    /// Return pressed: split this paragraph at the caret's UTF-16 offset.
    let onSplit: (Int) -> Void
    /// Backspace at offset 0: merge this paragraph into the previous one.
    let onMergeBackward: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = RichKeyCommandTextView()
        tv.onBoldCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleBold()
        }
        tv.onItalicCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleItalic()
        }
        tv.onUnderlineCommand = { [weak coordinator = context.coordinator] in
            coordinator?.toggleUnderline()
        }
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        tv.backgroundColor = UIColor.secondarySystemBackground
        tv.layer.cornerRadius = 6
        tv.layer.borderWidth = 0.5
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.autocorrectionType = .no
        // Red misspelling underline WITHOUT autocorrect (see ProseBlockEditor).
        tv.spellCheckingType = .yes
        tv.autocapitalizationType = .none
        tv.delegate = context.coordinator
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)

        context.coordinator.textView = tv
        tv.attributedText = RichRunConversion.attributedString(from: runs)
        context.coordinator.lastRuns = runs
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.runsEqual(runs, context.coordinator.lastRuns) {
            uiView.attributedText = RichRunConversion.attributedString(from: runs)
            context.coordinator.lastRuns = runs
            uiView.invalidateIntrinsicContentSize()
        }
        consumeFocusRequestIfNeeded(uiView)
    }

    /// If a split/merge left a caret request addressed to this paragraph, grab
    /// first responder and position the caret. Dispatched async so it runs after
    /// the rebuilt paragraph list settles, and cleared once consumed so it does
    /// not yank focus on a later rebuild (same one-shot discipline as the focus
    /// guards in `SelectAllTextField`).
    private func consumeFocusRequestIfNeeded(_ uiView: UITextView) {
        guard let request = focusRequest, request.id == paragraphID else { return }
        DispatchQueue.main.async {
            guard self.focusRequest == request else { return }
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
            let length = (uiView.text as NSString).length
            let location = max(0, min(request.offset, length))
            uiView.selectedRange = NSRange(location: location, length: 0)
            self.focusRequest = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate, ProseFormattingTarget {
        var parent: RichParagraphEditor
        weak var textView: UITextView?
        var lastRuns: [Run] = []

        init(_ parent: RichParagraphEditor) { self.parent = parent }

        func runsEqual(_ a: [Run], _ b: [Run]) -> Bool {
            guard a.count == b.count else { return false }
            for (r1, r2) in zip(a, b) {
                guard r1.emphasis == r2.emphasis else { return false }
                guard case .fixed(let s1) = r1.content, case .fixed(let s2) = r2.content, s1 == s2 else { return false }
            }
            return true
        }

        /// Intercepts Return (split this paragraph) and Backspace-at-start (merge
        /// into the previous paragraph). Everything else types normally.
        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onSplit(range.location)
                return false
            }
            if text.isEmpty, range.location == 0, range.length == 0 {
                parent.onMergeBackward()
                return false
            }
            return true
        }

        func textViewDidChange(_ tv: UITextView) {
            let newRuns = RichRunConversion.runs(from: tv.attributedText)
            lastRuns = newRuns
            parent.runs = newRuns
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.controller.active = self
            refreshController(for: tv)
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.controller.isActive(self) {
                parent.controller.clear()
            }
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            if parent.controller.isActive(self) {
                refreshController(for: tv)
            }
        }

        private func currentTraits(for tv: UITextView) -> (bold: Bool, italic: Bool, underline: Bool) {
            let range = tv.selectedRange
            var attrs: [NSAttributedString.Key: Any]
            if range.length > 0, tv.attributedText.length > 0 {
                let clampedRange = NSRange(location: min(range.location, tv.attributedText.length - 1), length: 0)
                attrs = tv.attributedText.attributes(at: clampedRange.location, effectiveRange: nil)
            } else {
                attrs = tv.typingAttributes
            }
            let font = attrs[.font] as? UIFont
            let symbolicTraits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = symbolicTraits.contains(.traitBold)
            let italic = symbolicTraits.contains(.traitItalic)
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            return (bold, italic, underline)
        }

        private func refreshController(for tv: UITextView) {
            let traits = currentTraits(for: tv)
            parent.controller.refresh(bold: traits.bold,
                                      italic: traits.italic,
                                      underline: traits.underline,
                                      bullet: parent.style.isBullet,
                                      numbered: parent.style.isNumbered)
        }

        @objc func toggleBold() { toggle { ($0.bold.toggled(), $0.italic, $0.underline) } }
        @objc func toggleItalic() { toggle { ($0.bold, $0.italic.toggled(), $0.underline) } }
        @objc func toggleUnderline() { toggle { ($0.bold, $0.italic, $0.underline.toggled()) } }

        @objc func toggleBullet() {
            parent.style = parent.style.isBullet ? .body : .bullet
            if let tv = textView { refreshController(for: tv) }
        }

        @objc func toggleNumbered() {
            parent.style = parent.style.isNumbered ? .body : .numbered
            if let tv = textView { refreshController(for: tv) }
        }

        private func toggle(_ transform: (( bold: Bool, italic: Bool, underline: Bool)) -> (bold: Bool, italic: Bool, underline: Bool)) {
            guard let tv = textView else { return }
            let selectedRange = tv.selectedRange

            if selectedRange.length > 0 {
                let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
                let currentTraits = self.currentTraits(for: tv)
                let newTraits = transform(currentTraits)
                mutable.setAttributes(RichRunConversion.attributes(for: newTraits), range: selectedRange)
                tv.attributedText = mutable
                tv.selectedRange = selectedRange
                let newRuns = RichRunConversion.runs(from: tv.attributedText)
                lastRuns = newRuns
                parent.runs = newRuns
            } else {
                let currentTraits = self.currentTraits(for: tv)
                let newTraits = transform(currentTraits)
                tv.typingAttributes = RichRunConversion.attributes(for: newTraits)
            }
            refreshController(for: tv)
        }
    }
}

private extension Bool {
    func toggled() -> Bool { !self }
}

private extension ParagraphStyle {
    var isBullet: Bool {
        if case .bullet = self { return true }
        return false
    }
    var isNumbered: Bool {
        if case .numbered = self { return true }
        return false
    }
}

#Preview {
    struct Demo: View {
        @State private var runs: [Run] = [
            Run(.fixed("This is "), emphasis: .regular),
            Run(.fixed("bold"), emphasis: .bold),
            Run(.fixed(" and this is "), emphasis: .regular),
            Run(.fixed("underlined"), emphasis: .underline),
            Run(.fixed("."), emphasis: .regular)
        ]
        @State private var style: ParagraphStyle = .body
        @State private var focusRequest: FocusRequest?
        @StateObject private var formatting = ProseFormattingController()
        var body: some View {
            ScrollView {
                VStack {
                    FormattingToolbar(controller: formatting).frame(height: 32)
                    RichParagraphEditor(
                        paragraphID: UUID(),
                        runs: $runs,
                        style: $style,
                        controller: formatting,
                        focusRequest: $focusRequest,
                        onSplit: { _ in },
                        onMergeBackward: { }
                    )
                }
                .padding()
            }
        }
    }
    return Demo()
}
