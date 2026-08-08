//
//  SignaturePad.swift
//  EYEreport
//
//  Draw-to-sign capture for the practitioner profile. Hand-rolled (a Canvas +
//  DragGesture, not PencilKit) so it behaves identically with a finger or
//  Apple Pencil on iPad and a mouse on Mac (Designed for iPad), with no
//  system tool-picker chrome. One smoothing/path function is shared by the
//  on-screen preview and the exported image, so what you see is what prints.
//  Export: strokes cropped to their bounding box, black ink on a TRANSPARENT
//  PNG at 3× — stamped over the letterhead paper by the renderer.
//

import SwiftUI
import UIKit

/// Modal sheet: a fixed (non-scrolling) drawing surface — so drags always ink,
/// never scroll — with Clear / Cancel / Save.
struct SignatureCaptureView: View {
    /// Receives the cropped transparent PNG on Save.
    var onSave: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    private var isEmpty: Bool { strokes.isEmpty && currentStroke.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Sign with your finger, pencil, or mouse.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // White "paper" regardless of appearance — the exported ink is
                // black, so the pad must show black-on-white in dark mode too.
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 1)
                    Canvas { context, _ in
                        for stroke in strokes + [currentStroke] {
                            context.stroke(Path(SignatureInk.path(for: stroke).cgPath),
                                           with: .color(.black),
                                           style: SignatureInk.strokeStyle)
                        }
                    }
                    if isEmpty {
                        Text("Sign here")
                            .font(.largeTitle)
                            .foregroundStyle(Color(.systemGray4))
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 260)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentStroke.append(value.location)
                        }
                        .onEnded { _ in
                            if !currentStroke.isEmpty {
                                strokes.append(currentStroke)
                                currentStroke = []
                            }
                        }
                )

                Button("Clear") {
                    strokes = []
                    currentStroke = []
                }
                .disabled(isEmpty)
            }
            .padding()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let data = SignatureInk.imageData(strokes: strokes) {
                            onSave(data)
                        }
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
    }
}

/// The single source for signature geometry: the smoothed stroke path (drawn
/// on screen AND exported) and the cropped-PNG export.
enum SignatureInk {
    static let lineWidth: CGFloat = 2.5

    static var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    }

    /// Midpoint-smoothed path through a stroke's points (quad curves through
    /// segment midpoints — the standard freehand-ink smoothing).
    static func path(for points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count < 3 {
            for p in points.dropFirst() { path.addLine(to: p) }
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                              y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, controlPoint: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// Black ink on transparent, cropped to the strokes' bounding box (plus
    /// breathing room), rendered at 3× for print quality.
    static func imageData(strokes: [[CGPoint]]) -> Data? {
        let allPoints = strokes.flatMap { $0 }
        guard !allPoints.isEmpty else { return nil }

        var minX = allPoints[0].x, maxX = allPoints[0].x
        var minY = allPoints[0].y, maxY = allPoints[0].y
        for p in allPoints {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let inset = lineWidth * 2
        let bbox = CGRect(x: minX - inset, y: minY - inset,
                          width: max(maxX - minX + inset * 2, 1),
                          height: max(maxY - minY + inset * 2, 1))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bbox.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -bbox.minX, y: -bbox.minY)
            UIColor.black.setStroke()
            for stroke in strokes {
                let p = path(for: stroke)
                p.lineWidth = lineWidth
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.stroke()
            }
        }
        return image.pngData()
    }
}

#Preview {
    SignatureCaptureView { _ in }
}
