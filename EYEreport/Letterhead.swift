//
//  Letterhead.swift
//  EYEreport
//

import Foundation
import CoreGraphics
import PDFKit

struct Letterhead: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var pdfData: Data
    /// Normalized (0–1) in UIKit/top-left space: y is measured down from the top of the page.
    var safeZone: CGRect
    /// Normalized (0–1) in UIKit/top-left space: y is measured down from the top of the page.
    var pageNumberOrigin: CGPoint
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // US Letter dimensions in points
    private static let letterWidth: CGFloat = 612
    private static let letterHeight: CGFloat = 792
    private static let margin: CGFloat = 72

    static let defaultSafeZone: CGRect = {
        let x = margin / letterWidth
        let y = margin / letterHeight
        let w = (letterWidth - 2 * margin) / letterWidth
        let h = (letterHeight - 2 * margin) / letterHeight
        return CGRect(x: x, y: y, width: w, height: h)
    }()

    static let defaultPageNumberOrigin = CGPoint(x: 0.85, y: 0.93)

    init(name: String, pdfData: Data) {
        self.name = name
        self.pdfData = pdfData
        self.safeZone = Letterhead.defaultSafeZone
        self.pageNumberOrigin = Letterhead.defaultPageNumberOrigin
    }

    var pageSize: CGSize? {
        guard let doc = PDFDocument(data: pdfData),
              let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        return bounds.size
    }

    /// Returns the safe zone scaled to `size`, in UIKit space (top-left origin, y-down).
    func contentRect(forPageSize size: CGSize) -> CGRect {
        CGRect(
            x: safeZone.origin.x * size.width,
            y: safeZone.origin.y * size.height,
            width: safeZone.width * size.width,
            height: safeZone.height * size.height
        )
    }

    /// Returns the page-number origin scaled to `size`, in UIKit space (top-left origin, y-down).
    func pageNumberPoint(forPageSize size: CGSize) -> CGPoint {
        CGPoint(
            x: pageNumberOrigin.x * size.width,
            y: pageNumberOrigin.y * size.height
        )
    }
}
