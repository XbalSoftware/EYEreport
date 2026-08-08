//
//  SafeZoneEditorView.swift
//  EYEreport
//

import SwiftUI
import UIKit
import PDFKit

struct SafeZoneEditorView: View {
    let letterhead: Letterhead
    @ObservedObject var store: LetterheadStore
    @Environment(\.dismiss) private var dismiss

    @State private var normalizedRect: CGRect
    @State private var normalizedPageNumberPoint: CGPoint
    @State private var pageImage: UIImage?
    /// Captured at the start of an interior-move drag so translation is applied to the original rect.
    @State private var moveStartRect: CGRect?

    /// Named coordinate space so every gesture reports its location in the same canvas frame,
    /// regardless of which (offset) subview the gesture is attached to.
    private let canvasSpace = "safeZoneCanvas"

    /// The eight resize handles on the safe-zone rectangle.
    private enum Handle: CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        case topMid, bottomMid, leftMid, rightMid
        var id: Self { self }
    }

    /// Minimum normalized width/height — the rect can't collapse or invert below this.
    private let minNormalizedSize: CGFloat = 0.05
    private let handleHitSize: CGFloat = 30
    private let handleDotSize: CGFloat = 12

    init(letterhead: Letterhead, store: LetterheadStore) {
        self.letterhead = letterhead
        self.store = store
        _normalizedRect = State(initialValue: letterhead.safeZone)
        _normalizedPageNumberPoint = State(initialValue: letterhead.pageNumberOrigin)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if let image = pageImage {
                    let fitted = fittedRect(imageSize: image.size, in: geo.size)
                    let viewRect = toViewRect(normalizedRect, fitted: fitted)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                        // Bare background no longer creates a rectangle — it does nothing.

                        // Safe-zone rectangle. Its interior is a MOVE target (lowest priority).
                        Rectangle()
                            .fill(Color.blue.opacity(0.15))
                            .overlay(
                                Rectangle()
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                            .frame(width: viewRect.width, height: viewRect.height)
                            .offset(x: viewRect.minX, y: viewRect.minY)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
                                    .onChanged { value in
                                        let start = moveStartRect ?? normalizedRect
                                        if moveStartRect == nil { moveStartRect = normalizedRect }
                                        let deltaN = CGSize(
                                            width: value.translation.width / fitted.width,
                                            height: value.translation.height / fitted.height
                                        )
                                        normalizedRect = moved(start, byNormalized: deltaN)
                                    }
                                    .onEnded { _ in moveStartRect = nil }
                            )

                        // Eight resize handles — drawn on top of the interior so they win hit-testing.
                        ForEach(Handle.allCases) { handle in
                            let p = handlePoint(handle, viewRect: viewRect)
                            Circle()
                                .fill(Color.white)
                                .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                                .frame(width: handleDotSize, height: handleDotSize)
                                .frame(width: handleHitSize, height: handleHitSize)
                                .contentShape(Rectangle())
                                .offset(x: p.x - handleHitSize / 2, y: p.y - handleHitSize / 2)
                                .gesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
                                        .onChanged { value in
                                            let pn = toNormalizedPoint(value.location, fitted: fitted)
                                            normalizedRect = resized(normalizedRect, handle: handle, toNormalized: pn)
                                        }
                                )
                        }

                        // Page-number pin — its own drag, independent and on top of everything.
                        let pinViewPoint = toViewPoint(normalizedPageNumberPoint, fitted: fitted)
                        PageNumberPin(label: "Page 1 of 3")
                            .offset(x: pinViewPoint.x, y: pinViewPoint.y)
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasSpace))
                                    .onChanged { value in
                                        let clamped = clamp(value.location, to: fitted)
                                        normalizedPageNumberPoint = toNormalizedPoint(clamped, fitted: fitted)
                                    }
                            )
                    }
                    .coordinateSpace(name: canvasSpace)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Set Safe Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        var updated = letterhead
                        updated.safeZone = clamped(normalizedRect)
                        updated.pageNumberOrigin = clampedPoint(normalizedPageNumberPoint)
                        store.update(updated)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to Default") {
                        normalizedRect = Letterhead.defaultSafeZone
                        normalizedPageNumberPoint = Letterhead.defaultPageNumberOrigin
                    }
                }
            }
            .onAppear { renderPage() }
        }
    }

    // MARK: - Page rendering

    private func renderPage() {
        guard let doc = PDFDocument(data: letterhead.pdfData),
              let page = doc.page(at: 0) else { return }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        pageImage = renderer.image { ctx in
            ctx.cgContext.saveGState()
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            // PDFKit draws with y-up; flip to y-down
            ctx.cgContext.translateBy(x: 0, y: bounds.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }

    // MARK: - Coordinate helpers

    /// The actual on-screen rect where the aspect-fit image is drawn inside `containerSize`.
    private func fittedRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        let fitWidth: CGFloat
        let fitHeight: CGFloat
        if imageAspect > containerAspect {
            fitWidth = containerSize.width
            fitHeight = containerSize.width / imageAspect
        } else {
            fitHeight = containerSize.height
            fitWidth = containerSize.height * imageAspect
        }
        let originX = (containerSize.width - fitWidth) / 2
        let originY = (containerSize.height - fitHeight) / 2
        return CGRect(x: originX, y: originY, width: fitWidth, height: fitHeight)
    }

    private func toViewRect(_ n: CGRect, fitted: CGRect) -> CGRect {
        CGRect(
            x: fitted.minX + n.minX * fitted.width,
            y: fitted.minY + n.minY * fitted.height,
            width: n.width * fitted.width,
            height: n.height * fitted.height
        )
    }

    private func toViewPoint(_ n: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: fitted.minX + n.x * fitted.width,
            y: fitted.minY + n.y * fitted.height
        )
    }

    private func toNormalizedPoint(_ viewPoint: CGPoint, fitted: CGRect) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - fitted.minX) / fitted.width,
            y: (viewPoint.y - fitted.minY) / fitted.height
        )
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func clamped(_ r: CGRect) -> CGRect {
        let x = min(max(r.minX, 0), 1)
        let y = min(max(r.minY, 0), 1)
        let maxX = min(max(r.maxX, 0), 1)
        let maxY = min(max(r.maxY, 0), 1)
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private func clampedPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, 0), 1),
            y: min(max(p.y, 0), 1)
        )
    }

    // MARK: - Handle geometry

    /// View-space position of a handle, derived from the rectangle's view rect.
    private func handlePoint(_ handle: Handle, viewRect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft:     return CGPoint(x: viewRect.minX, y: viewRect.minY)
        case .topRight:    return CGPoint(x: viewRect.maxX, y: viewRect.minY)
        case .bottomLeft:  return CGPoint(x: viewRect.minX, y: viewRect.maxY)
        case .bottomRight: return CGPoint(x: viewRect.maxX, y: viewRect.maxY)
        case .topMid:      return CGPoint(x: viewRect.midX, y: viewRect.minY)
        case .bottomMid:   return CGPoint(x: viewRect.midX, y: viewRect.maxY)
        case .leftMid:     return CGPoint(x: viewRect.minX, y: viewRect.midY)
        case .rightMid:    return CGPoint(x: viewRect.maxX, y: viewRect.midY)
        }
    }

    /// Resize `rect` (normalized) by moving the side/corner owned by `handle` toward `p`.
    /// The opposite side(s) stay fixed; result is clamped to 0...1 and to the minimum size,
    /// so an edge can never cross or close on its opposite.
    private func resized(_ rect: CGRect, handle: Handle, toNormalized p: CGPoint) -> CGRect {
        let m = minNormalizedSize
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        let px = min(max(p.x, 0), 1)
        let py = min(max(p.y, 0), 1)

        switch handle {
        case .topLeft:
            minX = min(px, maxX - m)
            minY = min(py, maxY - m)
        case .topRight:
            maxX = max(px, minX + m)
            minY = min(py, maxY - m)
        case .bottomLeft:
            minX = min(px, maxX - m)
            maxY = max(py, minY + m)
        case .bottomRight:
            maxX = max(px, minX + m)
            maxY = max(py, minY + m)
        case .topMid:
            minY = min(py, maxY - m)
        case .bottomMid:
            maxY = max(py, minY + m)
        case .leftMid:
            minX = min(px, maxX - m)
        case .rightMid:
            maxX = max(px, minX + m)
        }

        // px/py are already within 0...1, so the moving edge stays on-page; this guards
        // against any fixed edge that was previously stored slightly out of range.
        minX = max(minX, 0); minY = max(minY, 0)
        maxX = min(maxX, 1); maxY = min(maxY, 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Translate `rect` (normalized) by a normalized delta, preserving size and keeping the
    /// whole rect within 0...1.
    private func moved(_ rect: CGRect, byNormalized delta: CGSize) -> CGRect {
        let x = min(max(rect.minX + delta.width, 0), 1 - rect.width)
        let y = min(max(rect.minY + delta.height, 0), 1 - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}

// MARK: - Page Number Pin

/// A draggable handle that shows a preview of the page-number stamp.
/// The label is left-anchored at the pin origin, matching how the renderer draws the stamp.
private struct PageNumberPin: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.orange, lineWidth: 1)
                        )
                )
            // Small downward pin indicator
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
        }
        // Align the top-left of the label with the origin, matching renderer's left-anchor
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fixedSize()
    }
}

// MARK: - Preview

#Preview {
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { ctx in
        ctx.beginPage()
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
        UIColor.systemGray4.setStroke()
        let path = UIBezierPath(rect: CGRect(x: 36, y: 36, width: 540, height: 90))
        path.lineWidth = 1
        path.stroke()
    }
    let letterhead = Letterhead(name: "Sample Office", pdfData: data)
    return SafeZoneEditorView(letterhead: letterhead, store: LetterheadStore())
}
