import SwiftUI
import UIKit
import Combine

// MARK: - ProseFormattingTarget

/// The formatting operations a focused prose field exposes to the shared toolbar.
/// Adopted by both editor coordinators: `ProseBlockEditor.Coordinator` (the
/// consolidated multi-paragraph box) and `RichParagraphEditor.Coordinator` (the
/// per-paragraph fallback for slot/token blocks).
protocol ProseFormattingTarget: AnyObject {
    func toggleBold()
    func toggleItalic()
    func toggleUnderline()
    func toggleBullet()
    func toggleNumbered()
}

// MARK: - ProseFormattingController

/// One controller per PROSE block. It points at whichever prose field currently
/// holds first responder and mirrors that field's selection/paragraph state into
/// published Bools, so a single top-of-block `FormattingToolbar` can drive it.
final class ProseFormattingController: ObservableObject {
    /// The prose field currently being edited, or `nil` when none is focused.
    weak var active: (any ProseFormattingTarget)?

    /// Identity check that works through the existential (`===` on `any`).
    func isActive(_ obj: AnyObject) -> Bool { (active as AnyObject?) === obj }

    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var isBullet = false
    @Published var isNumbered = false

    /// Pushes the active field's current traits/style into the published Bools.
    func refresh(bold: Bool, italic: Bool, underline: Bool, bullet: Bool, numbered: Bool) {
        isBold = bold
        isItalic = italic
        isUnderline = underline
        isBullet = bullet
        isNumbered = numbered
    }

    /// Drops the active field and greys the toolbar (no field focused).
    func clear() {
        active = nil
        isBold = false
        isItalic = false
        isUnderline = false
        isBullet = false
        isNumbered = false
    }
}

// MARK: - FormattingToolbar

/// A top-of-block formatting bar. It wraps the existing `FormattingAccessoryBar`
/// UIToolbar via `UIViewRepresentable` so the B/I/U/•/# controls are
/// `UIBarButtonItem`s — tapping them does NOT resign the focused paragraph's
/// first responder (a SwiftUI `Button` would). Taps are routed to the
/// controller's active coordinator; the button tints/enablement reflect the
/// controller's published state.
struct FormattingToolbar: UIViewRepresentable {
    @ObservedObject var controller: ProseFormattingController

    func makeUIView(context: Context) -> FormattingAccessoryBar {
        let bar = FormattingAccessoryBar()
        bar.boldButton.addTarget(context.coordinator, action: #selector(Coordinator.toggleBold), for: .touchUpInside)
        bar.italicButton.addTarget(context.coordinator, action: #selector(Coordinator.toggleItalic), for: .touchUpInside)
        bar.underlineButton.addTarget(context.coordinator, action: #selector(Coordinator.toggleUnderline), for: .touchUpInside)
        bar.bulletButton.addTarget(context.coordinator, action: #selector(Coordinator.toggleBullet), for: .touchUpInside)
        bar.numberedButton.addTarget(context.coordinator, action: #selector(Coordinator.toggleNumbered), for: .touchUpInside)
        return bar
    }

    func updateUIView(_ bar: FormattingAccessoryBar, context: Context) {
        context.coordinator.controller = controller
        bar.setEnabled(controller.active != nil)
        bar.setActive(bold: controller.isBold,
                      italic: controller.isItalic,
                      underline: controller.isUnderline)
        bar.setStyleActive(bullet: controller.isBullet, numbered: controller.isNumbered)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    final class Coordinator: NSObject {
        var controller: ProseFormattingController
        init(_ controller: ProseFormattingController) { self.controller = controller }

        @objc func toggleBold() { controller.active?.toggleBold() }
        @objc func toggleItalic() { controller.active?.toggleItalic() }
        @objc func toggleUnderline() { controller.active?.toggleUnderline() }
        @objc func toggleBullet() { controller.active?.toggleBullet() }
        @objc func toggleNumbered() { controller.active?.toggleNumbered() }
    }
}
