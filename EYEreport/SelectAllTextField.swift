import SwiftUI
import UIKit

// MARK: - Focusable UIKit subclasses (hardware-keyboard tab navigation)

/// UITextField that emits Tab / Shift-Tab as navigation commands instead of
/// inserting whitespace, but ONLY when `tabEnabled` is true (a focus contract
/// was supplied). Otherwise it is a plain UITextField.
///
/// Optional arrow/Return interception (nil by default — plain field): the
/// handlers return true when they CONSUMED the key (e.g. moving through the
/// recipient editor's provider suggestions), false to let the text system
/// have it (caret movement / default Return).
final class FocusableTextField: UITextField {
    var tabEnabled = false
    var onTabCommand: ((_ backward: Bool) -> Void)?
    var onArrowKey: ((_ down: Bool) -> Bool)?
    var onReturnKey: (() -> Bool)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let key = presses.first?.key {
            if tabEnabled, key.keyCode == .keyboardTab {
                onTabCommand?(key.modifierFlags.contains(.shift))
                return
            }
            if key.keyCode == .keyboardDownArrow, onArrowKey?(true) == true { return }
            if key.keyCode == .keyboardUpArrow, onArrowKey?(false) == true { return }
            if key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keypadEnter,
               onReturnKey?() == true { return }
        }
        super.pressesBegan(presses, with: event)
    }
}

final class FocusableTextView: UITextView {
    var tabEnabled = false
    var onTabCommand: ((_ backward: Bool) -> Void)?

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if tabEnabled, let key = presses.first?.key, key.keyCode == .keyboardTab {
            onTabCommand?(key.modifierFlags.contains(.shift))
            return
        }
        super.pressesBegan(presses, with: event)
    }
}

// MARK: - Single-line select-all field

/// Selects all existing text on focus so the user can type a replacement.
/// Opt-in focus contract: when `focusKey` + `focusBinding` are supplied the
/// field participates in an explicit ordered focus chain and `onTab` moves
/// focus. All three nil → behaves exactly as before (no key commands).
struct SelectAllTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var focusKey: String? = nil
    var focusBinding: Binding<String?>? = nil
    var onTab: ((_ backward: Bool) -> Void)? = nil
    /// Return true to consume the key (suggestion navigation); false/nil =
    /// normal text-field behavior.
    var onArrowKey: ((_ down: Bool) -> Bool)? = nil
    var onReturnKey: (() -> Bool)? = nil
    var onEndEditing: (() -> Void)? = nil
    var textColor: UIColor = .systemRed
    /// Opt-in red misspelling underline (off by default — most scalar fields
    /// are names/IDs/numbers where a squiggle is noise). Enabled for Subject.
    var spellCheck: Bool = false

    func makeUIView(context: Context) -> UITextField {
        let tf = FocusableTextField()
        tf.borderStyle = .none
        tf.backgroundColor = .secondarySystemBackground
        tf.layer.cornerRadius = 6
        tf.layer.borderWidth = 0.5
        tf.layer.borderColor = UIColor.separator.cgColor
        tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 6, height: 0))
        tf.leftViewMode = .always
        tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 6, height: 0))
        tf.rightViewMode = .always
        tf.placeholder = placeholder
        tf.keyboardType = keyboardType
        tf.textColor = textColor
        tf.autocorrectionType = .no
        tf.spellCheckingType = spellCheck ? .yes : .no
        tf.autocapitalizationType = .none
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.editingChanged(_:)),
                     for: .editingChanged)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text { uiView.text = text }

        if let tf = uiView as? FocusableTextField {
            tf.tabEnabled = (onTab != nil)
            tf.onTabCommand = { [weak coordinator = context.coordinator] backward in
                coordinator?.parent.onTab?(backward)
            }
            tf.onArrowKey = { [weak coordinator = context.coordinator] down in
                coordinator?.parent.onArrowKey?(down) ?? false
            }
            tf.onReturnKey = { [weak coordinator = context.coordinator] in
                coordinator?.parent.onReturnKey?() ?? false
            }
        }

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
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        fileprivate var isClaimingFocus = false
        init(_ parent: SelectAllTextField) { self.parent = parent }

        @objc func editingChanged(_ tf: UITextField) {
            parent.text = tf.text ?? ""
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            isClaimingFocus = false
            parent.focusBinding?.wrappedValue = parent.focusKey
            DispatchQueue.main.async { tf.selectAll(nil) }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            // Clear the shared focus key when THIS field resigns and still owns
            // it, so a later rebuild doesn't re-claim focus back to this cell.
            if parent.focusBinding?.wrappedValue == parent.focusKey {
                parent.focusBinding?.wrappedValue = nil
            }
            parent.onEndEditing?()
        }

        func textField(_ tf: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if string == "\t", let f = tf as? FocusableTextField, f.tabEnabled {
                return false
            }
            return true
        }
    }
}

// MARK: - Multi-line wrapping variant (same select-all + focus contract)

struct SelectAllTextView: UIViewRepresentable {
    @Binding var text: String

    var focusKey: String? = nil
    var focusBinding: Binding<String?>? = nil
    var onTab: ((_ backward: Bool) -> Void)? = nil
    var selectAllOnFocus: Bool = true

    func makeUIView(context: Context) -> UITextView {
        let tv = FocusableTextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textColor = .systemRed
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        tv.backgroundColor = UIColor.secondarySystemBackground
        tv.layer.cornerRadius = 6
        tv.layer.borderWidth = 0.5
        tv.layer.borderColor = UIColor.separator.cgColor
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.delegate = context.coordinator
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultHigh, for: .vertical)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
            uiView.invalidateIntrinsicContentSize()
        }

        if let tv = uiView as? FocusableTextView {
            tv.tabEnabled = (onTab != nil)
            tv.onTabCommand = { [weak coordinator = context.coordinator] backward in
                coordinator?.parent.onTab?(backward)
            }
        }

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
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? UIView.layoutFittingExpandedSize.width
        let size = uiView.sizeThatFits(CGSize(width: width,
                                              height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectAllTextView
        fileprivate var isClaimingFocus = false
        init(_ parent: SelectAllTextView) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            tv.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            isClaimingFocus = false
            parent.focusBinding?.wrappedValue = parent.focusKey
            if parent.selectAllOnFocus {
                DispatchQueue.main.async { tv.selectAll(nil) }
            } else {
                DispatchQueue.main.async {
                    tv.selectedTextRange = tv.textRange(from: tv.endOfDocument, to: tv.endOfDocument)
                }
            }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.focusBinding?.wrappedValue == parent.focusKey {
                parent.focusBinding?.wrappedValue = nil
            }
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\t", let v = textView as? FocusableTextView, v.tabEnabled {
                return false
            }
            return true
        }
    }
}

// MARK: - Preview (self-verifies the focus contract)

#Preview {
    struct Demo: View {
        @State private var a = "Alpha"
        @State private var b = "Bravo"
        @State private var c = "A longer wrapping value for the middle field"
        @State private var focused: String? = nil
        private let order = ["k0", "k1", "k2"]

        private func move(from key: String, backward: Bool) {
            guard let i = order.firstIndex(of: key) else { return }
            let j = backward ? i - 1 : i + 1
            if order.indices.contains(j) { focused = order[j] }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SelectAllTextField(placeholder: "A", text: $a,
                    focusKey: "k0", focusBinding: $focused,
                    onTab: { move(from: "k0", backward: $0) })
                SelectAllTextView(text: $c,
                    focusKey: "k1", focusBinding: $focused,
                    onTab: { move(from: "k1", backward: $0) })
                    .frame(width: 240)
                SelectAllTextField(placeholder: "B", text: $b,
                    focusKey: "k2", focusBinding: $focused,
                    onTab: { move(from: "k2", backward: $0) })
                Text("focused: \(focused ?? "nil")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
}
