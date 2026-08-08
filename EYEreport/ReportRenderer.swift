//
//  ReportRenderer.swift
//  EYEreport — single-pass content-only PDF renderer
//
//  Turns a ReportDocument into a US-Letter PDF (no letterhead compositing).
//  The content rect is currently a fixed 72pt inset on all sides; this will
//  become the letterhead's safe-zone rect once Letterheads are implemented.

import UIKit
import PDFKit

enum ReportRenderer {

    static func renderToPDFData(
        _ document: ReportDocument,
        profile: PractitionerProfile = PractitionerProfile(),
        letterhead: Letterhead? = nil
    ) -> Data {
        let pageSize = CGSize(width: 612, height: 792)

        let contentRect: CGRect
        if let lh = letterhead {
            // safeZone is stored in UIKit-space normalized coords (y=0 at top); contentRect is already UIKit-space.
            contentRect = lh.contentRect(forPageSize: pageSize)
        } else {
            let margin: CGFloat = 72
            contentRect = CGRect(
                x: margin,
                y: margin,
                width: pageSize.width - margin * 2,
                height: pageSize.height - margin * 2
            )
        }

        // Every produced PDF carries its own structured source (see
        // EmbeddedReport) so exported reports can be reopened for editing.
        let format = UIGraphicsPDFRendererFormat()
        if let payload = EmbeddedReport.payload(for: document) {
            format.documentInfo = [EmbeddedReport.infoKey: payload]
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize),
                                             format: format)

        // Eagerly load the letterhead PDF page so every page can redraw it.
        let lhPage: PDFPage? = letterhead.flatMap { lh in
            PDFDocument(data: lh.pdfData)?.page(at: 0)
        }

        let context0 = RenderContext(document: document, profile: profile, contentRect: contentRect)
        let totalPages = countPages(context: context0)

        let data = renderer.pdfData { ctx in
            var currentPage = 0

            // Draws the letterhead background and page-number stamp on the current PDF page.
            func beginPage() {
                ctx.beginPage()
                currentPage += 1
                if let pdfPage = lhPage {
                    let cgCtx = UIGraphicsGetCurrentContext()!
                    cgCtx.saveGState()
                    cgCtx.translateBy(x: 0, y: pageSize.height)
                    cgCtx.scaleBy(x: 1, y: -1)
                    pdfPage.draw(with: .mediaBox, to: cgCtx)
                    cgCtx.restoreGState()
                }
                guard totalPages > 1 else { return }
                let stamp = "Page \(currentPage) of \(totalPages)"
                let stampAttrs = context0.attrs(size: 9, weight: .regular)
                let stampAS = NSAttributedString(string: stamp, attributes: stampAttrs)
                let stampSize = stampAS.boundingRect(
                    with: CGSize(width: 200, height: 20),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let origin: CGPoint
                if let lh = letterhead {
                    origin = lh.pageNumberPoint(forPageSize: pageSize)
                } else {
                    // Fallback: right-aligned near the bottom margin
                    origin = CGPoint(x: pageSize.width - 72 - stampSize.width, y: pageSize.height - 54)
                }
                stampAS.draw(in: CGRect(x: origin.x, y: origin.y, width: ceil(stampSize.width) + 2, height: 20))
            }

            beginPage()

            let blockGap: CGFloat = 12
            let context = RenderContext(document: document, profile: profile, contentRect: contentRect)
            let pageBottom = contentRect.maxY
            var y = contentRect.minY
            var pageIsEmpty = true

            for block in document.blocks {
                // Findings can SPLIT across pages: fill the current page with as
                // many whole rows as fit, then continue the rest on following
                // pages, repeating the OD/OS column headers + rule each time.
                if case .findings(let f) = block.content {
                    let includedRows = f.rows.filter { $0.included }

                    // No rows: just the header lead-in + column headers + rule.
                    // Paginate as a normal whole block (it cannot split).
                    if includedRows.isEmpty {
                        let h = measureFindings(f, context: context)
                        if h <= 0 { continue }
                        if (y + h) > pageBottom && !pageIsEmpty {
                            beginPage()
                            y = contentRect.minY
                            pageIsEmpty = true
                        }
                        let used = drawFindings(f, context: context, y: y)
                        if used > 0 {
                            y += used + blockGap
                            pageIsEmpty = false
                        }
                        continue
                    }

                    let layout = findingsLayout(f, context: context)
                    var startRow = 0
                    while startRow < includedRows.count {
                        // If the page already has content and not even one row
                        // fits after the headers + rule, move to a fresh page
                        // first (never leave a header-only orphan segment).
                        let preRows = findingsPreRowsHeight(f, startRow: startRow, context: context)
                        let firstRowH = findingsRowHeight(includedRows[startRow], layout: layout, context: context)
                        let oneRowFits = (preRows + firstRowH) <= (pageBottom - y)
                        if !pageIsEmpty && !oneRowFits {
                            beginPage()
                            y = contentRect.minY
                            pageIsEmpty = true
                        }

                        // forceAtLeastOneRow on an empty page is the infinite-loop
                        // guard: a pathologically tiny safe zone still advances by
                        // one (overflowing) row rather than producing zero-row pages.
                        let (h, next) = drawFindingsSegment(
                            f,
                            startRow: startRow,
                            availableHeight: pageBottom - y,
                            context: context,
                            y: y,
                            forceAtLeastOneRow: pageIsEmpty
                        )
                        y += h + blockGap
                        pageIsEmpty = false
                        startRow = next

                        // More rows remain — continue on a new page.
                        if startRow < includedRows.count {
                            beginPage()
                            y = contentRect.minY
                            pageIsEmpty = true
                        }
                    }
                    continue
                }

                // Prose can SPLIT across pages at TWO granularities (C2c):
                //  - between paragraphs: place whole paragraphs while they fit,
                //    continue the rest on the next page;
                //  - within a paragraph: a paragraph taller than a full page is
                //    broken mid-text at TextKit line boundaries, carrying the tail
                //    forward. Mirrors the findings sub-loop: a pre-check defers a
                //    too-tall whole paragraph to a fresh page first, and
                //    `forceProgress` on an empty page guarantees at least one line.
                // Boxed prose is EXCLUDED here: it moves whole (like the
                // Impressions/Plan box) through the generic block path below.
                if case .prose(let prose) = block.content, prose.boxed != true {
                    let count = prose.paragraphs.count
                    var paraIndex = 0
                    var pendingTail: NSAttributedString? = nil

                    while paraIndex < count || pendingTail != nil {
                        // The next unit is a carried-over tail, or the next fresh
                        // paragraph. If the page already has content and the whole
                        // unit will not fit in the remaining space, move to a fresh
                        // page first — it may then fit whole (or split on an empty
                        // page if it is taller than a full page).
                        let nextUnit = pendingTail
                            ?? buildParagraphAS(prose.paragraphs, at: paraIndex, context: context)
                        let fitsWhole = measureAttributedString(nextUnit, context: context) <= (pageBottom - y)
                        if !pageIsEmpty && !fitsWhole {
                            beginPage()
                            y = contentRect.minY
                            pageIsEmpty = true
                        }

                        // forceProgress on an empty page is the infinite-loop guard:
                        // a paragraph too tall for even a full empty page still
                        // advances by at least one line rather than looping.
                        let (h, nextIndex, newPending) = drawProseSegment(
                            prose,
                            startIndex: paraIndex,
                            pendingTail: pendingTail,
                            availableHeight: pageBottom - y,
                            context: context,
                            y: y,
                            forceProgress: pageIsEmpty
                        )
                        if h > 0 {
                            y += h + blockGap
                            pageIsEmpty = false
                        }
                        paraIndex = nextIndex
                        pendingTail = newPending

                        // More prose remains — continue on a new page.
                        if paraIndex < count || pendingTail != nil {
                            beginPage()
                            y = contentRect.minY
                            pageIsEmpty = true
                        }
                    }
                    continue
                }

                let blockHeight = measureBlock(block.content, context: context)
                if blockHeight <= 0 { continue }

                let fits = (y + blockHeight) <= pageBottom
                if !fits && !pageIsEmpty {
                    // Start a fresh page and reset cursor.
                    beginPage()
                    y = contentRect.minY
                    pageIsEmpty = true
                }
                // Draw — if blockHeight > full page height, draw anyway (overflow guard).
                let usedHeight = drawBlock(block.content, context: context, y: y)
                if usedHeight > 0 {
                    y += usedHeight + blockGap
                    pageIsEmpty = false
                }
            }
        }
        return ensuringEmbeddedSource(data, document: document)
    }

    /// Guarantees the embedded source (EmbeddedReport) is actually IN the
    /// produced bytes. UIGraphicsPDFRenderer SHOULD write it via
    /// `documentInfo`, but a device build produced a PDF with no Keywords
    /// entry at all — so if the payload is absent, re-serialize ONCE through
    /// PDFKit, which sets the Keywords attribute directly (verified: a
    /// 120KB payload written this way reads back intact via CGPDFDocument,
    /// page content preserved). Both writers target the same key, so the
    /// importer needs no knowledge of which one ran.
    private static func ensuringEmbeddedSource(_ data: Data, document: ReportDocument) -> Data {
        if EmbeddedReport.document(from: data) != nil { return data }
        guard let payload = EmbeddedReport.payload(for: document),
              let pdf = PDFDocument(data: data) else { return data }
        var attrs = pdf.documentAttributes ?? [:]
        attrs[PDFDocumentAttribute.keywordsAttribute] = payload
        pdf.documentAttributes = attrs
        return pdf.dataRepresentation() ?? data
    }

    // MARK: - Page count (dry run — same measure/break logic, no drawing)

    /// Runs the same page-break decisions as renderToPDFData but without any
    /// drawing, returning the total number of pages the document will produce.
    /// Must stay in sync with the layout loop above — if the fit math changes
    /// there, change it here too.
    private static func countPages(context: RenderContext) -> Int {
        let pageBottom = context.contentRect.maxY
        let blockGap: CGFloat = 12
        var y = context.contentRect.minY
        var pageIsEmpty = true
        var pages = 1

        func newPage() {
            pages += 1
            y = context.contentRect.minY
            pageIsEmpty = true
        }

        for block in context.document.blocks {
            if case .findings(let f) = block.content {
                let includedRows = f.rows.filter { $0.included }
                if includedRows.isEmpty {
                    let h = measureFindings(f, context: context)
                    if h <= 0 { continue }
                    if (y + h) > pageBottom && !pageIsEmpty { newPage() }
                    y += h + blockGap
                    pageIsEmpty = false
                    continue
                }

                let layout = findingsLayout(f, context: context)
                var startRow = 0
                while startRow < includedRows.count {
                    let preRows = findingsPreRowsHeight(f, startRow: startRow, context: context)
                    let firstRowH = findingsRowHeight(includedRows[startRow], layout: layout, context: context)
                    let oneRowFits = (preRows + firstRowH) <= (pageBottom - y)
                    if !pageIsEmpty && !oneRowFits { newPage() }

                    // Count how many rows fit (mirrors drawFindingsSegment, forceAtLeastOneRow on empty page)
                    var segH = findingsPreRowsHeight(f, startRow: startRow, context: context)
                    var rowIndex = startRow
                    while rowIndex < includedRows.count {
                        let rowH = findingsRowHeight(includedRows[rowIndex], layout: layout, context: context)
                        let fits = (segH + rowH) <= (pageBottom - y)
                        let mustDraw = (rowIndex == startRow && pageIsEmpty)
                        if !fits && !mustDraw { break }
                        segH += rowH
                        rowIndex += 1
                    }
                    y += segH + blockGap
                    pageIsEmpty = false
                    startRow = rowIndex
                    if startRow < includedRows.count { newPage() }
                }
                continue
            }

            // Boxed prose is EXCLUDED here too (mirrors the draw loop): it
            // moves whole through the generic measureBlock path below.
            if case .prose(let prose) = block.content, prose.boxed != true {
                let count = prose.paragraphs.count
                var paraIndex = 0
                var pendingTail: NSAttributedString? = nil

                while paraIndex < count || pendingTail != nil {
                    let nextUnit = pendingTail
                        ?? buildParagraphAS(prose.paragraphs, at: paraIndex, context: context)
                    let fitsWhole = measureAttributedString(nextUnit, context: context) <= (pageBottom - y)
                    if !pageIsEmpty && !fitsWhole { newPage() }

                    let unitH = measureAttributedString(nextUnit, context: context)
                    let available = pageBottom - y

                    if unitH <= available {
                        y += unitH + proseParagraphGap
                        pageIsEmpty = false
                        if pendingTail != nil { pendingTail = nil } else { paraIndex += 1 }
                    } else {
                        // Split: at least one line is placed on this page (forceProgress when empty)
                        let (head, rest) = splitAttributedString(
                            nextUnit,
                            width: context.contentRect.width,
                            availableHeight: max(available, 0),
                            context: context
                        )
                        let headH = measureAttributedString(head, context: context)
                        y += headH
                        pageIsEmpty = false
                        if pendingTail != nil { pendingTail = rest } else { paraIndex += 1; pendingTail = rest }
                        if paraIndex < count || pendingTail != nil { newPage() }
                    }

                    if paraIndex < count || pendingTail != nil {
                        // more to place — will loop; page break happens next iteration if needed
                        if y >= pageBottom && !pageIsEmpty { newPage() }
                    }
                }
                continue
            }

            let blockHeight = measureBlock(block.content, context: context)
            if blockHeight <= 0 { continue }
            if (y + blockHeight) > pageBottom && !pageIsEmpty { newPage() }
            y += blockHeight + blockGap
            pageIsEmpty = false
        }

        return pages
    }

    // MARK: - Block measurement (no drawing)

    private static func measureBlock(_ content: BlockContent, context: RenderContext) -> CGFloat {
        switch content {
        case .recipient(let r):
            switch r {
            case .none: return 0
            case .freeform(let s):
                return measureString(s, attrs: context.body, context: context)
            case .providerFax(let name, let fax):
                return measureAttributedString(
                    recipientProviderLine(name: name, fax: fax, context: context),
                    context: context)
            }
        case .title(let t):
            return measureString(t.text, attrs: context.attrs(size: context.titleSize, weight: .bold), context: context)
        case .date(let d):
            let label = d.label
            let dateStr = d.date.map { dateFormatter.string(from: $0) } ?? ""
            let full: NSAttributedString
            if label.isEmpty {
                full = NSAttributedString(string: dateStr, attributes: context.body)
            } else {
                let as1 = NSMutableAttributedString(string: label + " ", attributes: context.boldBody)
                as1.append(NSAttributedString(string: dateStr, attributes: context.body))
                full = as1
            }
            return measureAttributedString(full, context: context)
        case .subject(let s):
            return measureString(s.text, attrs: context.boldBody, context: context)
        case .salutation(let s):
            let text: String
            switch s {
            case .dearDoctor(let name, _): text = name.isEmpty ? "Dear," : "Dear \(name),"
            case .toWhomItMayConcern:   text = "To Whom it May Concern:"
            case .custom(let c):        text = c
            }
            return measureString(text, attrs: context.body, context: context)
        case .patient(let p):
            // Same layout functions the draw path uses — see the Patient MARK.
            switch p.renderStyle {
            case .inlineLabels:
                var total: CGFloat = 0
                for f in p.resolvedFieldOrder where p.includedFields.contains(f) {
                    let line = patientComposedLine(p, f, style: .inlineLabels, context: context)
                    total += measureAttributedString(line, context: context) + 2
                }
                return total
            case .reducedBox, .fullBox:
                let layout = patientBoxLayout(p, style: p.renderStyle, context: context)
                return layout.rows.isEmpty ? 0 : layout.boxH
            }
        case .prose(let prose):
            if prose.boxed == true {
                return boxedProseHeight(prose, context: context)
            }
            var total: CGFloat = 0
            for i in prose.paragraphs.indices {
                let as_ = buildParagraphAS(prose.paragraphs, at: i, context: context)
                total += measureAttributedString(as_, context: context) + proseParagraphGap
            }
            return total
        case .findings(let f):
            return measureFindings(f, context: context)
        case .impressionsPlan(let ip):
            return impressionsPlanLayout(ip, context: context).totalH
        case .closing(let c):
            let text: String
            switch c {
            case .sharingInCare:  text = "Thank you for sharing in the care of this patient."
            case .contactOffice:  text = "Please contact my office if further information is required."
            case .custom(let s):  text = s
            }
            return measureString(text, attrs: context.body, context: context)
        case .signature(let s):
            var dy: CGFloat = 0
            dy += measureString(s.valediction, attrs: context.body, context: context) + 2
            dy += signatureGap(context) // signature image gap (shared with draw)
            dy += 16 // name + ID line
            return dy
        case .spacer(let s):
            return spacerHeight(s, context: context)
        }
    }

    /// A blank block's height: `lines` × one body line. Single source for
    /// measure AND draw. `drawSpacer` draws nothing; it just advances y.
    private static func spacerHeight(_ s: SpacerContent, context: RenderContext) -> CGFloat {
        let oneLine = measureString("X", attrs: context.body, context: context)
        return CGFloat(max(0, s.lines)) * oneLine
    }

    private static func measureString(_ s: String, attrs: [NSAttributedString.Key: Any], context: RenderContext) -> CGFloat {
        measureAttributedString(NSAttributedString(string: s, attributes: attrs), context: context)
    }

    private static func measureAttributedString(_ as_: NSAttributedString, context: RenderContext) -> CGFloat {
        guard as_.length > 0 else { return 0 }
        let bounds = as_.boundingRect(
            with: CGSize(width: context.contentRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return bounds.height
    }

    // MARK: - Block dispatch

    private static func drawBlock(_ content: BlockContent, context: RenderContext, y: CGFloat) -> CGFloat {
        switch content {
        case .recipient(let r):  return drawRecipient(r, context: context, y: y)
        case .title(let t):      return drawTitle(t, context: context, y: y)
        case .date(let d):       return drawDate(d, context: context, y: y)
        case .patient(let p):    return drawPatient(p, context: context, y: y)
        case .subject(let s):    return drawSubject(s, context: context, y: y)
        case .salutation(let s): return drawSalutation(s, context: context, y: y)
        case .prose(let p):      return drawProse(p, context: context, y: y)
        case .findings(let f):   return drawFindings(f, context: context, y: y)
        case .impressionsPlan(let ip): return drawImpressionsPlan(ip, context: context, y: y)
        case .closing(let c):    return drawClosing(c, context: context, y: y)
        case .signature(let s):  return drawSignature(s, context: context, y: y)
        case .spacer(let s):     return spacerHeight(s, context: context) // blank gap
        }
    }

    // MARK: - Recipient

    private static func drawRecipient(_ r: RecipientContent, context: RenderContext, y: CGFloat) -> CGFloat {
        switch r {
        case .none:
            return 0
        case .freeform(let s):
            return drawString(s, attrs: context.body, rect: context.lineRect(y: y), context: context)
        case .providerFax(let name, let fax):
            return drawAttributedString(
                recipientProviderLine(name: name, fax: fax, context: context),
                rect: context.lineRect(y: y), context: context)
        }
    }

    /// "To: Dr. Jane Smith   Fax: (403) 555-0100" — ONE line, bold labels,
    /// "Fax:" omitted entirely when there is no fax, "To:" always printed.
    /// Single source for measure AND draw (lockstep rule). The empty-name
    /// placeholder remains an unfilled-prompt issue for the deferred
    /// output-vs-placeholder cleanup.
    private static func recipientProviderLine(name: String, fax: String,
                                              context: RenderContext) -> NSAttributedString {
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "To: ", attributes: context.boldBody))
        line.append(NSAttributedString(string: name.isEmpty ? "DOCTOR NAME" : name,
                                       attributes: context.body))
        if !fax.isEmpty {
            line.append(NSAttributedString(string: "   ", attributes: context.body))
            line.append(NSAttributedString(string: "Fax: ", attributes: context.boldBody))
            line.append(NSAttributedString(string: fax, attributes: context.body))
        }
        return line
    }

    // MARK: - Title

    private static func drawTitle(_ t: TitleContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let attrs = context.attrs(size: context.titleSize, weight: .bold)
        return drawString(t.text, attrs: attrs, rect: context.lineRect(y: y), context: context)
    }

    // MARK: - Date

    private static func drawDate(_ d: DateContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let label = d.label
        let dateStr = d.date.map { Self.dateFormatter.string(from: $0) } ?? ""
        let full: NSAttributedString
        if label.isEmpty {
            full = NSAttributedString(string: dateStr, attributes: context.body)
        } else {
            let as1 = NSMutableAttributedString(string: label + " ", attributes: context.boldBody)
            as1.append(NSAttributedString(string: dateStr, attributes: context.body))
            full = as1
        }
        return drawAttributedString(full, rect: context.lineRect(y: y), context: context)
    }

    // MARK: - Subject

    private static func drawSubject(_ s: SubjectContent, context: RenderContext, y: CGFloat) -> CGFloat {
        drawString(s.text, attrs: context.boldBody, rect: context.lineRect(y: y), context: context)
    }

    // MARK: - Salutation

    private static func drawSalutation(_ s: SalutationContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let text: String
        switch s {
        case .dearDoctor(let name, _): text = name.isEmpty ? "Dear," : "Dear \(name),"
        case .toWhomItMayConcern:   text = "To Whom it May Concern:"
        case .custom(let c):        text = c
        }
        return drawString(text, attrs: context.body, rect: context.lineRect(y: y), context: context)
    }

    // MARK: - Patient

    // Patient layout is SINGLE-SOURCE: `patientBoxRows` / `patientBoxLayout` /
    // `patientComposedLine` are consumed by BOTH the measure path
    // (measureBlock, above) and the draw path (drawPatient, below), so the
    // block's measured height always equals its drawn height. Field order,
    // presence, and labels come from the model (`resolvedFieldOrder`,
    // `customLabel(for:)`).

    /// Full-width patient fields: address carries long content and takes a
    /// whole row across both columns in the boxed styles (like a findings
    /// spanning row).
    private static func patientFieldSpans(_ f: PatientField) -> Bool { f == .address }

    private enum PatientBoxRow {
        case cells(left: PatientField, right: PatientField?)
        case spanning(PatientField)
    }

    /// Reading-order rows for the boxed styles: two fields per row; a
    /// spanning field flushes any half-filled row and takes a full row. With
    /// the default order this reproduces the historical fullBox columns
    /// (left: Patient/AHC, right: DOB/Phone) with Address now full-width.
    private static func patientBoxRows(_ p: PatientContent) -> [PatientBoxRow] {
        var rows: [PatientBoxRow] = []
        var pendingLeft: PatientField?
        for f in p.resolvedFieldOrder where p.includedFields.contains(f) {
            if patientFieldSpans(f) {
                if let left = pendingLeft {
                    rows.append(.cells(left: left, right: nil))
                    pendingLeft = nil
                }
                rows.append(.spanning(f))
            } else if let left = pendingLeft {
                rows.append(.cells(left: left, right: f))
                pendingLeft = nil
            } else {
                pendingLeft = f
            }
        }
        if let left = pendingLeft { rows.append(.cells(left: left, right: nil)) }
        return rows
    }

    private static func patientValue(_ p: PatientContent, _ f: PatientField) -> String {
        switch f {
        case .name:
            return p.lastName.isEmpty && p.firstName.isEmpty
                ? "PATIENT NAME"
                : "\(p.lastName.uppercased()), \(p.firstName)"
        case .dob:     return dobString(from: p.dob)
        case .ahc:     return p.ahc
        case .phone:   return p.phone
        case .address: return p.address
        }
    }

    /// The printed label for a field: the custom label + ":" when set,
    /// otherwise the style's historical default. reducedBox is the NO-LABELS
    /// box ("Box — no labels" in the editor) — every field prints its bare
    /// value, custom labels included; historically only the name was
    /// unlabeled there, which the user flagged as broken.
    private static func patientPrintLabel(_ p: PatientContent, _ f: PatientField,
                                          style: PatientRenderStyle) -> String? {
        if style == .reducedBox { return nil }
        if let custom = p.customLabel(for: f) { return custom + ":" }
        switch f {
        case .name:    return "Patient:"
        case .dob:     return style == .inlineLabels ? "Date of Birth:" : "DOB:"
        case .ahc:     return "AHC:"
        case .phone:   return "Phone:"
        case .address: return "Address:"
        }
    }

    /// "Label: value" as one attributed string — the inlineLabels line and
    /// the reducedBox cell (whose label sits flush against its value).
    private static func patientComposedLine(_ p: PatientContent, _ f: PatientField,
                                            style: PatientRenderStyle,
                                            context: RenderContext) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let label = patientPrintLabel(p, f, style: style) {
            result.append(NSAttributedString(string: label + " ", attributes: context.boldBody))
        }
        result.append(NSAttributedString(string: patientValue(p, f), attributes: context.body))
        return result
    }

    private struct PatientBoxLayout {
        let rows: [(row: PatientBoxRow, height: CGFloat)]
        let labelWidth: CGFloat
        let lineH: CGFloat
        let pad: CGFloat
        var boxH: CGFloat { rows.reduce(0) { $0 + $1.height } + pad * 2 }
    }

    /// Row heights + label column for a boxed patient block. Paired rows are
    /// fixed-height; a spanning row grows to its wrapped value (measure and
    /// draw both read the height computed HERE).
    private static func patientBoxLayout(_ p: PatientContent, style: PatientRenderStyle,
                                         context: RenderContext) -> PatientBoxLayout {
        let lineH: CGFloat = style == .reducedBox ? 24 : 16
        let pad: CGFloat = 4
        // fullBox label column: widest label in use (historical 60pt floor).
        var labelWidth: CGFloat = 60
        for f in p.resolvedFieldOrder where p.includedFields.contains(f) {
            if let label = patientPrintLabel(p, f, style: style) {
                let w = ceil((label as NSString).size(withAttributes: context.boldBody).width) + 6
                labelWidth = max(labelWidth, w)
            }
        }
        let inner = context.contentRect.width - pad * 2
        var rows: [(row: PatientBoxRow, height: CGFloat)] = []
        for row in patientBoxRows(p) {
            switch row {
            case .cells:
                rows.append((row, lineH))
            case .spanning(let f):
                let h: CGFloat
                if style == .fullBox {
                    let value = patientValue(p, f)
                    if value.isEmpty {
                        h = lineH
                    } else {
                        let bounds = (value as NSString).boundingRect(
                            with: CGSize(width: inner - labelWidth, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                            attributes: context.body, context: nil)
                        h = max(lineH, ceil(bounds.height) + 2)
                    }
                } else {
                    let line = patientComposedLine(p, f, style: style, context: context)
                    let bounds = line.boundingRect(
                        with: CGSize(width: inner, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    h = max(lineH, ceil(bounds.height) + 2)
                }
                rows.append((row, h))
            }
        }
        return PatientBoxLayout(rows: rows, labelWidth: labelWidth, lineH: lineH, pad: pad)
    }

    private static func drawPatient(_ p: PatientContent, context: RenderContext, y: CGFloat) -> CGFloat {
        switch p.renderStyle {
        case .inlineLabels:
            var totalH: CGFloat = 0
            var rowY = y
            for f in p.resolvedFieldOrder where p.includedFields.contains(f) {
                let line = patientComposedLine(p, f, style: .inlineLabels, context: context)
                let h = drawAttributedString(line, rect: context.lineRect(y: rowY), context: context)
                rowY += h + 2; totalH += h + 2
            }
            return totalH

        case .reducedBox, .fullBox:
            let layout = patientBoxLayout(p, style: p.renderStyle, context: context)
            guard !layout.rows.isEmpty else { return 0 }
            let boxH = layout.boxH
            let boxRect = CGRect(x: context.contentRect.minX, y: y,
                                 width: context.contentRect.width, height: boxH)
            UIColor.black.setStroke()
            UIBezierPath(rect: boxRect).stroke()

            let pad = layout.pad
            let colWidth = context.contentRect.width / 2
            let leftX = context.contentRect.minX + pad
            let rightX = context.contentRect.minX + colWidth + pad
            let inner = context.contentRect.width - pad * 2
            var rowY = y + pad

            for (row, h) in layout.rows {
                switch row {
                case .cells(let left, let right):
                    drawPatientCell(p, left, x: leftX, width: colWidth - pad * 2,
                                    y: rowY, height: h, layout: layout, context: context)
                    if let right {
                        drawPatientCell(p, right, x: rightX, width: colWidth - pad * 2,
                                        y: rowY, height: h, layout: layout, context: context)
                    }
                case .spanning(let f):
                    if p.renderStyle == .fullBox {
                        if let label = patientPrintLabel(p, f, style: .fullBox) {
                            NSAttributedString(string: label, attributes: context.boldBody)
                                .draw(in: CGRect(x: leftX, y: rowY,
                                                 width: layout.labelWidth, height: layout.lineH))
                        }
                        (patientValue(p, f) as NSString).draw(
                            in: CGRect(x: leftX + layout.labelWidth, y: rowY,
                                       width: inner - layout.labelWidth, height: h),
                            withAttributes: context.body)
                    } else {
                        patientComposedLine(p, f, style: .reducedBox, context: context)
                            .draw(in: CGRect(x: leftX, y: rowY, width: inner, height: h))
                    }
                }
                rowY += h
            }
            return boxH
        }
    }

    /// One half-width cell in a boxed patient row. fullBox aligns values in a
    /// shared label column; reducedBox draws label and value contiguously
    /// (its historical look — bare name + "DOB: value").
    private static func drawPatientCell(_ p: PatientContent, _ f: PatientField,
                                        x: CGFloat, width: CGFloat,
                                        y: CGFloat, height: CGFloat,
                                        layout: PatientBoxLayout, context: RenderContext) {
        if p.renderStyle == .fullBox {
            if let label = patientPrintLabel(p, f, style: .fullBox) {
                NSAttributedString(string: label, attributes: context.boldBody)
                    .draw(in: CGRect(x: x, y: y, width: layout.labelWidth, height: layout.lineH))
            }
            drawString(patientValue(p, f), attrs: context.body,
                       rect: CGRect(x: x + layout.labelWidth, y: y,
                                    width: width - layout.labelWidth, height: layout.lineH),
                       context: context)
        } else {
            patientComposedLine(p, f, style: .reducedBox, context: context)
                .draw(in: CGRect(x: x, y: y, width: width, height: height))
        }
    }

    // MARK: - Prose

    // Single source of truth for the inter-paragraph gap. The measure path
    // (`measureBlock`), the whole-block draw (`drawProse`), and the splitting
    // segment (`drawProseSegment`) all consume this — any disagreement would
    // split prose at the wrong paragraph.
    private static let proseParagraphGap: CGFloat = 3

    /// Whole-block convenience: draw an entire prose block on one page. Used by
    /// the `drawBlock` dispatch; the paginating page loop drives prose through
    /// `drawProseSegment` instead. A block that fits renders identically either
    /// way (the segment is a single pass over the same attributed strings).
    private static func drawProse(_ prose: ProseContent, context: RenderContext, y: CGFloat) -> CGFloat {
        if prose.boxed == true {
            return drawBoxedProse(prose, context: context, y: y)
        }
        var totalH: CGFloat = 0
        for i in prose.paragraphs.indices {
            let as_ = buildParagraphAS(prose.paragraphs, at: i, context: context)
            let rect = context.lineRect(y: y + totalH)
            let h = drawAttributedString(as_, rect: rect, context: context)
            totalH += h + proseParagraphGap
        }
        return totalH
    }

    // MARK: - Boxed prose (prose.boxed == true)

    /// Total height of a boxed prose block: the body inset by `pad` on all
    /// sides — the same box geometry as Impressions/Plan. The SINGLE source
    /// for the boxed block's measure (`measureBlock`) and draw
    /// (`drawBoxedProse`); the paginating loops exclude boxed prose from
    /// splitting, so it moves whole on this one number.
    private static func boxedProseHeight(_ prose: ProseContent, context: RenderContext) -> CGFloat {
        let pad: CGFloat = 6
        let bodyAS = buildProseAS(prose, context: context)
        guard bodyAS.length > 0 else { return pad * 2 + 20 } // empty-box placeholder height
        let bounds = bodyAS.boundingRect(
            with: CGSize(width: context.contentRect.width - pad * 2, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return bounds.height + pad * 2
    }

    private static func drawBoxedProse(_ prose: ProseContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let pad: CGFloat = 6
        let contentH = boxedProseHeight(prose, context: context)

        let boxRect = CGRect(x: context.contentRect.minX, y: y, width: context.contentRect.width, height: contentH)
        UIColor.black.setStroke()
        UIBezierPath(rect: boxRect).stroke()

        let bodyAS = buildProseAS(prose, context: context)
        if bodyAS.length > 0 {
            let bodyWidth = context.contentRect.width - pad * 2
            let bounds = bodyAS.boundingRect(
                with: CGSize(width: bodyWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            bodyAS.draw(in: CGRect(x: context.contentRect.minX + pad, y: y + pad,
                                   width: bodyWidth, height: bounds.height))
        }
        return contentH
    }

    /// Draw a (possibly partial) prose block, starting from `startIndex` (or a
    /// carried-over `pendingTail`), placing whole paragraphs that fit within
    /// `availableHeight`. Returns the height drawn, the index of the first
    /// paragraph NOT yet started, and the un-drawn remainder of a paragraph that
    /// had to be split mid-text (nil when no split is pending).
    ///
    /// Granularity:
    ///  - A whole paragraph (or pending tail) is placed only if it fits in the
    ///    space still left in this segment.
    ///  - When the next unit does not fit and the segment has NOT yet drawn
    ///    anything AND `forceProgress` is set (an empty page), the unit is split
    ///    mid-text at a TextKit line boundary: the head is drawn here and the
    ///    tail is returned to continue on the next page. This guarantees at least
    ///    one line per page — the within-paragraph infinite-loop guard.
    ///  - When the next unit does not fit but the segment already has content (or
    ///    `forceProgress` is not set), drawing stops with state unchanged so the
    ///    page loop can break the page and retry the unit whole on a fresh page.
    ///
    /// The attributed string is built once (`buildParagraphAS`) and the RESOLVED
    /// string is what gets split, so per-run emphasis (bold/italic) and already-
    /// inserted token/slot text survive the seam intact.
    private static func drawProseSegment(
        _ prose: ProseContent,
        startIndex: Int,
        pendingTail: NSAttributedString?,
        availableHeight: CGFloat,
        context: RenderContext,
        y: CGFloat,
        forceProgress: Bool
    ) -> (heightDrawn: CGFloat, nextIndex: Int, pendingTail: NSAttributedString?) {
        var dy: CGFloat = 0
        var index = startIndex
        var tail = pendingTail

        while tail != nil || index < prose.paragraphs.count {
            // A carried-over tail takes priority over the next fresh paragraph.
            let unit: NSAttributedString
            let unitIsTail: Bool
            if let t = tail {
                unit = t; unitIsTail = true
            } else {
                unit = buildParagraphAS(prose.paragraphs, at: index, context: context)
                unitIsTail = false
            }

            let unitH = measureAttributedString(unit, context: context)
            let remaining = availableHeight - dy
            let isFirstUnit = (dy == 0)

            if unitH <= remaining {
                // Whole unit fits in the space left this segment.
                _ = drawAttributedString(unit, rect: context.lineRect(y: y + dy), context: context)
                dy += unitH + proseParagraphGap
                if unitIsTail { tail = nil } else { index += 1 }
                continue
            }

            // Does not fit. Unless this is the first unit on an empty page, defer
            // to a page break: return with state unchanged so the page loop can
            // retry this unit whole on a fresh page.
            guard isFirstUnit && forceProgress else {
                return (dy, index, tail)
            }

            // Fresh/empty page and still too tall: split mid-text. Guarantees at
            // least one line so the page is never left with zero lines drawn.
            let (head, rest) = splitAttributedString(
                unit,
                width: context.contentRect.width,
                availableHeight: remaining,
                context: context
            )
            _ = drawAttributedString(head, rect: context.lineRect(y: y + dy), context: context)
            dy += measureAttributedString(head, context: context)
            if !unitIsTail { index += 1 } // this paragraph is consumed; its remainder is carried as the tail
            return (dy, index, rest)
        }

        return (dy, index, nil)
    }

    /// Split a resolved attributed string at the TextKit line-fragment boundary
    /// that fits within `availableHeight` at `width`. Returns the head (drawable
    /// in the available space) and the tail to carry forward (nil if everything
    /// fit). Always yields at least one line in the head — if not even one line
    /// fits, one line is taken anyway (overflow guard against zero-line pages).
    /// Attributes are preserved by slicing the SAME attributed string, so bold/
    /// italic spans and inserted token text survive the break.
    private static func splitAttributedString(
        _ as_: NSAttributedString,
        width: CGFloat,
        availableHeight: CGFloat,
        context: RenderContext
    ) -> (head: NSAttributedString, tail: NSAttributedString?) {
        guard as_.length > 0 else { return (as_, nil) }

        // Lay the string into a container of the available height; the glyphs the
        // layout manager places there are exactly those that fit.
        let storage = NSTextStorage(attributedString: as_)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: max(availableHeight, 0)))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let glyphRange = layout.glyphRange(for: container)
        var charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Infinite-loop guard: if not even one line fit, force the first line.
        if charRange.length == 0 {
            let oneStorage = NSTextStorage(attributedString: as_)
            let oneLayout = NSLayoutManager()
            oneStorage.addLayoutManager(oneLayout)
            let oneContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
            oneContainer.lineFragmentPadding = 0
            oneContainer.maximumNumberOfLines = 1
            oneLayout.addTextContainer(oneContainer)
            oneLayout.ensureLayout(for: oneContainer)
            let oneGlyphRange = oneLayout.glyphRange(for: oneContainer)
            charRange = oneLayout.characterRange(forGlyphRange: oneGlyphRange, actualGlyphRange: nil)
            if charRange.length == 0 {
                charRange = NSRange(location: 0, length: min(1, as_.length)) // absolute fallback
            }
        }

        let headLen = charRange.length
        guard headLen < as_.length else { return (as_, nil) } // everything fit
        let head = as_.attributedSubstring(from: NSRange(location: 0, length: headLen))
        let tail = NSMutableAttributedString(
            attributedString: as_.attributedSubstring(from: NSRange(location: headLen, length: as_.length - headLen))
        )
        // The tail starts mid-paragraph, so its first drawn line is a
        // CONTINUATION: it must sit at the hanging indent (headIndent), not the
        // paragraph's first-line indent — otherwise a wrapped list item split
        // across a page snaps back to the margin on the next page. Both the
        // draw pass and countPages obtain tails through this one function, and
        // both measure the mutated tail, so measure/draw/count stay in lockstep.
        tail.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: tail.length)) { value, range, _ in
            guard let ps = value as? NSParagraphStyle, ps.firstLineHeadIndent != ps.headIndent else { return }
            let continued = ps.mutableCopy() as! NSMutableParagraphStyle
            continued.firstLineHeadIndent = continued.headIndent
            tail.addAttribute(.paragraphStyle, value: continued, range: range)
        }
        return (head, tail)
    }

    /// Builds the fully-resolved attributed string for the paragraph at `index`
    /// of `paragraphs`. A `.numbered` paragraph's "N." marker comes from
    /// `numberedOrdinal`; every item in a numbered run shares ONE text column
    /// sized to the run's WIDEST marker (`numberedRunMax`), so "1." and "10."
    /// items start their text — and wrap — at the same x. The marker and a tab
    /// to that column are baked into this one attributed string — exactly as
    /// the bullet marker is — keeping measure/split/draw/count in lockstep
    /// automatically.
    private static func buildParagraphAS(_ paragraphs: [Paragraph], at index: Int, context: RenderContext) -> NSAttributedString {
        let para = paragraphs[index]
        let result = NSMutableAttributedString()

        // Resolve the runs first: an EMPTY list paragraph (e.g. the trailing
        // blank line the editor leaves while typing) prints NO marker — a bare
        // "12." or "•" with no text must not appear in output. It renders like
        // an empty body paragraph instead: a blank line.
        let resolvedRuns: [(text: String, emphasis: Emphasis)] = para.runs.map {
            (resolveRun($0, context: context), $0.emphasis)
        }
        let hasText = resolvedRuns.contains { !$0.text.isEmpty }

        let indentLevel: CGFloat
        let listPrefix: String
        switch para.style {
        case .body:
            indentLevel = 0; listPrefix = ""
        case .bullet:
            indentLevel = 0; listPrefix = hasText ? "•\t" : ""
        case .indented(let level):
            indentLevel = CGFloat(level) * 24; listPrefix = ""
        case .numbered:
            indentLevel = 0; listPrefix = hasText ? "\(numberedOrdinal(paragraphs, at: index) ?? 1).\t" : ""
        }

        if !listPrefix.isEmpty {
            result.append(NSAttributedString(string: listPrefix, attributes: context.body))
        }

        for (text, emphasis) in resolvedRuns {
            result.append(NSAttributedString(string: text, attributes: context.attrs(for: emphasis)))
        }

        // One text column for the whole list: the marker's tab jumps to a stop
        // sized by the list's widest marker ("11. " beats "1. "), so every
        // item's text starts at the same x, and headIndent puts wrapped lines
        // directly under it. An empty list paragraph has no marker (above), so
        // it gets no column either.
        let textColumn: CGFloat
        switch para.style {
        case .bullet where hasText:
            textColumn = ("• " as NSString).size(withAttributes: context.body).width
        case .numbered where hasText:
            let widestMarker = "\(numberedRunMax(paragraphs, at: index) ?? 1). "
            textColumn = (widestMarker as NSString).size(withAttributes: context.body).width
        default:
            textColumn = 0
        }

        if indentLevel > 0 || textColumn > 0 {
            let ps = NSMutableParagraphStyle()
            ps.headIndent = indentLevel + textColumn
            ps.firstLineHeadIndent = indentLevel
            if textColumn > 0 {
                ps.tabStops = [NSTextTab(textAlignment: .left, location: indentLevel + textColumn)]
            }
            result.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: result.length))
        }

        return result
    }

    /// The highest ordinal in the run of consecutive `.numbered` paragraphs
    /// containing `index` — sizes the common text column for the whole run.
    /// Like `numberedOrdinal`, computed from the FULL paragraph list so the
    /// column stays identical across a page split. Nil when the paragraph at
    /// `index` isn't numbered.
    private static func numberedRunMax(_ paragraphs: [Paragraph], at index: Int) -> Int? {
        guard var n = numberedOrdinal(paragraphs, at: index) else { return nil }
        var i = index + 1
        while i < paragraphs.count, case .numbered = paragraphs[i].style {
            n += 1
            i += 1
        }
        return n
    }

    /// The 1-based marker for a `.numbered` paragraph, derived from its position
    /// within the run of consecutive `.numbered` paragraphs it belongs to. Nil
    /// when the paragraph at `index` isn't numbered. Computed from the FULL
    /// paragraph list (independent of pagination) so a numbered list split across
    /// a page break resumes at the correct number.
    private static func numberedOrdinal(_ paragraphs: [Paragraph], at index: Int) -> Int? {
        guard paragraphs.indices.contains(index),
              case .numbered = paragraphs[index].style else { return nil }
        var n = 1
        var i = index - 1
        while i >= 0, case .numbered = paragraphs[i].style {
            n += 1
            i -= 1
        }
        return n
    }

    private static func resolveRun(_ run: Run, context: RenderContext) -> String {
        switch run.content {
        case .fixed(let s):
            return s
        case .token(let t):
            return resolveToken(t, context: context)
        case .slot(let slot):
            if slot.isFilled {
                if let free = slot.freeText, !free.isEmpty { return free }
                if let idx = slot.selectedIndex, idx < slot.options.count { return slot.options[idx] }
            }
            return "[" + slot.options.joined(separator: " / ") + "]"
        }
    }

    private static func resolveToken(_ token: DataToken, context: RenderContext) -> String {
        let p = context.document.patient
        let profile = context.profile
        switch token {
        case .patientFullName:
            guard let pat = p else { return "" }
            return "\(pat.lastName), \(pat.firstName)"
        case .patientFirstName:  return p?.firstName ?? ""
        case .patientLastName:   return p?.lastName ?? ""
        case .patientDOB:        return dobString(from: p?.dob)
        case .examDate:
            for block in context.document.blocks {
                if case .date(let d) = block.content, let date = d.date {
                    return Self.dateFormatter.string(from: date)
                }
            }
            return ""
        case .practitionerName:        return profile.name
        case .practitionerCredentials: return profile.credentials
        }
    }

    // MARK: - Findings

    // Single source of truth for findings geometry. The split logic, the
    // measurement, and the actual drawing all consume these — any disagreement
    // would split the grid at the wrong row.
    private static let findingsRowH: CGFloat = 16     // column-header row; FLOOR for data rows
    private static let findingsHeaderGap: CGFloat = 4 // gap below the lead-in header line
    private static let findingsRuleGap: CGFloat = 2   // horizontal rule under the column headers
    private static let findingsColumnGap: CGFloat = 8 // between label/OD/OS columns

    /// Content-driven column geometry for one findings grid: the label column
    /// hugs the widest included label (60pt floor, capped at 40% of the
    /// content width so a runaway label can't crush the values), and the
    /// remaining width splits evenly between OD and OS. Spanning rows run
    /// from the OD column to the right edge.
    private struct FindingsLayout {
        let labelWidth: CGFloat
        let odX: CGFloat
        let osX: CGFloat
        let colWidth: CGFloat
        let spanWidth: CGFloat
    }

    private static func findingsLayout(_ f: FindingsContent, context: RenderContext) -> FindingsLayout {
        let cx = context.contentRect.minX
        let maxX = context.contentRect.maxX
        var labelWidth: CGFloat = 60
        for row in f.rows where row.included {
            let w = ceil((row.label as NSString).size(withAttributes: context.body).width) + 8
            labelWidth = max(labelWidth, w)
        }
        labelWidth = min(labelWidth, floor(context.contentRect.width * 0.4))
        let odX = cx + labelWidth + findingsColumnGap
        let colWidth = floor((maxX - odX - findingsColumnGap) / 2)
        let osX = odX + colWidth + findingsColumnGap
        return FindingsLayout(labelWidth: labelWidth, odX: odX, osX: osX,
                              colWidth: colWidth, spanWidth: maxX - odX)
    }

    /// A data row's height: the tallest wrapped cell (label / OD / OS or the
    /// spanning value) in its column width, floored at `findingsRowH` so
    /// single-line rows keep the historical 16pt. Measure, split, count, and
    /// draw ALL read row heights from here.
    private static func findingsRowHeight(_ row: FindingRow, layout: FindingsLayout,
                                          context: RenderContext) -> CGFloat {
        func cellHeight(_ s: String, width: CGFloat) -> CGFloat {
            guard !s.isEmpty, width > 0 else { return 0 }
            let bounds = (s as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: context.body, context: nil)
            return ceil(bounds.height)
        }
        var h = cellHeight(row.label, width: layout.labelWidth)
        switch row.value {
        case .paired(let od, let os):
            h = max(h, cellHeight(applyAffordance(od, row.affordance), width: layout.colWidth))
            h = max(h, cellHeight(applyAffordance(os, row.affordance), width: layout.colWidth))
        case .spanning(let s):
            h = max(h, cellHeight(s, width: layout.spanWidth))
        }
        return max(findingsRowH, h + 2)
    }

    /// Height consumed before any data rows for a segment starting at `startRow`:
    /// the lead-in header (first page only) + the OD/OS column headers + the rule.
    private static func findingsPreRowsHeight(_ f: FindingsContent, startRow: Int, context: RenderContext) -> CGFloat {
        var h: CGFloat = 0
        if startRow == 0, let header = f.header, !header.isEmpty {
            h += measureString(header, attrs: context.body, context: context) + findingsHeaderGap
        }
        h += findingsRowH      // column headers
        h += findingsRuleGap   // rule
        return h
    }

    /// Full height of a findings block if drawn on a single page.
    private static func measureFindings(_ f: FindingsContent, context: RenderContext) -> CGFloat {
        let includedRows = f.rows.filter { $0.included }
        let layout = findingsLayout(f, context: context)
        return findingsPreRowsHeight(f, startRow: 0, context: context)
            + includedRows.reduce(0) { $0 + findingsRowHeight($1, layout: layout, context: context) }
    }

    /// Whole-block convenience: draw the entire grid on one page (used by the
    /// drawBlock dispatch and the no-rows path).
    private static func drawFindings(_ f: FindingsContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let (h, _) = drawFindingsSegment(
            f,
            startRow: 0,
            availableHeight: .greatestFiniteMagnitude,
            context: context,
            y: y,
            forceAtLeastOneRow: true
        )
        return h
    }

    /// Draw a (possibly partial) findings grid starting at `startRow`, placing
    /// only whole rows that fit within `availableHeight`. Returns the height
    /// drawn and the index of the first row NOT yet drawn (== included row count
    /// when the grid is finished).
    ///
    /// - The lead-in header line renders ONLY when `startRow == 0` (it belongs to
    ///   the grid's first page, not continuations).
    /// - The OD/OS column headers + rule render on EVERY page the grid spans.
    /// - `forceAtLeastOneRow` draws one row even if it overflows, to guarantee
    ///   forward progress on an empty page with a pathologically tiny safe zone.
    private static func drawFindingsSegment(
        _ f: FindingsContent,
        startRow: Int,
        availableHeight: CGFloat,
        context: RenderContext,
        y: CGFloat,
        forceAtLeastOneRow: Bool
    ) -> (heightDrawn: CGFloat, nextRowIndex: Int) {
        var totalH: CGFloat = 0
        let cx = context.contentRect.minX
        let layout = findingsLayout(f, context: context)
        let odX = layout.odX
        let osX = layout.osX

        // Lead-in header — first page of the grid only.
        if startRow == 0, let header = f.header, !header.isEmpty {
            let h = drawString(header, attrs: context.body, rect: context.lineRect(y: y + totalH), context: context)
            totalH += h + findingsHeaderGap
        }

        // Column headers — repeated atop every page the grid spans.
        drawString("OD", attrs: context.boldBody, rect: CGRect(x: odX, y: y + totalH, width: layout.colWidth, height: findingsRowH), context: context)
        drawString("OS", attrs: context.boldBody, rect: CGRect(x: osX, y: y + totalH, width: layout.colWidth, height: findingsRowH), context: context)
        totalH += findingsRowH

        // Horizontal rule under the headers — also repeated on every page.
        let rulePath = UIBezierPath()
        rulePath.move(to: CGPoint(x: cx, y: y + totalH))
        rulePath.addLine(to: CGPoint(x: context.contentRect.maxX, y: y + totalH))
        UIColor.black.setStroke()
        rulePath.stroke()
        totalH += findingsRuleGap

        // Whole rows only, from startRow, until vertical space runs out.
        let includedRows = f.rows.filter { $0.included }
        var rowIndex = startRow
        while rowIndex < includedRows.count {
            let row = includedRows[rowIndex]
            let rowH = findingsRowHeight(row, layout: layout, context: context)
            let fits = (totalH + rowH) <= availableHeight
            let mustDrawAtLeastOne = (rowIndex == startRow && forceAtLeastOneRow)
            if !fits && !mustDrawAtLeastOne { break }

            let rowY = y + totalH
            drawString(row.label, attrs: context.body,
                       rect: CGRect(x: cx, y: rowY, width: layout.labelWidth, height: rowH), context: context)
            let aff = row.affordance
            switch row.value {
            case .paired(let od, let os):
                let odStr = applyAffordance(od, aff)
                let osStr = applyAffordance(os, aff)
                drawString(odStr, attrs: context.body, rect: CGRect(x: odX, y: rowY, width: layout.colWidth, height: rowH), context: context)
                drawString(osStr, attrs: context.body, rect: CGRect(x: osX, y: rowY, width: layout.colWidth, height: rowH), context: context)
            case .spanning(let s):
                drawString(s, attrs: context.body, rect: CGRect(x: odX, y: rowY, width: layout.spanWidth, height: rowH), context: context)
            }
            totalH += rowH
            rowIndex += 1
        }
        return (totalH, rowIndex)
    }

    private static func applyAffordance(_ value: String, _ aff: FieldAffordance?) -> String {
        guard let aff else { return value }
        if value.isEmpty { return "" }
        return (aff.prefix ?? "") + value + (aff.suffix ?? "")
    }

    // MARK: - Impressions / Plan

    /// Pre-measured layout for the Impressions/Plan block — the SINGLE source
    /// consumed by both `measureBlock` and `drawImpressionsPlan`, so the box
    /// height and page-fit decisions can't drift from what is drawn. Labels are
    /// rich content (emphasis comes from their runs — bold by convention, no
    /// longer hardcoded) and take their measured height; an empty label takes
    /// no height at all.
    private struct IPSectionLayout {
        let labelAS: NSAttributedString
        let labelH: CGFloat
        let bodyAS: NSAttributedString
        let bodyH: CGFloat
    }

    private static let ipPad: CGFloat = 6

    private static func impressionsPlanLayout(_ ip: ImpressionsPlanContent, context: RenderContext) -> (sections: [IPSectionLayout], totalH: CGFloat) {
        let innerWidth = context.contentRect.width - ipPad * 2
        let unbounded = CGSize(width: innerWidth, height: .greatestFiniteMagnitude)
        var sections: [IPSectionLayout] = []
        var contentH: CGFloat = ipPad
        for section in ip.sections {
            let labelAS = buildProseAS(section.label, context: context)
            let labelH: CGFloat = labelAS.length > 0
                ? labelAS.boundingRect(with: unbounded, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height + 3
                : 0
            let bodyAS = buildProseAS(section.body, context: context)
            let bodyH: CGFloat = bodyAS.length > 0
                ? bodyAS.boundingRect(with: unbounded, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height + 4
                : 20 // empty section placeholder height
            contentH += labelH + bodyH
            sections.append(IPSectionLayout(labelAS: labelAS, labelH: labelH, bodyAS: bodyAS, bodyH: bodyH))
        }
        contentH += ipPad
        return (sections, contentH)
    }

    private static func drawImpressionsPlan(_ ip: ImpressionsPlanContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let layout = impressionsPlanLayout(ip, context: context)
        let innerX = context.contentRect.minX + ipPad
        let innerWidth = context.contentRect.width - ipPad * 2

        if ip.boxed {
            let boxRect = CGRect(x: context.contentRect.minX, y: y, width: context.contentRect.width, height: layout.totalH)
            UIColor.black.setStroke()
            UIBezierPath(rect: boxRect).stroke()
        }

        var dy: CGFloat = ipPad
        for section in layout.sections {
            if section.labelAS.length > 0 {
                section.labelAS.draw(in: CGRect(x: innerX, y: y + dy, width: innerWidth, height: section.labelH))
            }
            dy += section.labelH
            if section.bodyAS.length > 0 {
                section.bodyAS.draw(in: CGRect(x: innerX, y: y + dy, width: innerWidth, height: section.bodyH))
            }
            dy += section.bodyH
        }

        return layout.totalH
    }

    private static func buildProseAS(_ prose: ProseContent, context: RenderContext) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for i in prose.paragraphs.indices {
            result.append(buildParagraphAS(prose.paragraphs, at: i, context: context))
            if i < prose.paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: context.body))
            }
        }
        return result
    }

    // MARK: - Closing

    private static func drawClosing(_ c: ClosingContent, context: RenderContext, y: CGFloat) -> CGFloat {
        let text: String
        switch c {
        case .sharingInCare:  text = "Thank you for sharing in the care of this patient."
        case .contactOffice:  text = "Please contact my office if further information is required."
        case .custom(let s):  text = s
        }
        return drawString(text, attrs: context.body, rect: context.lineRect(y: y), context: context)
    }

    // MARK: - Signature

    /// Vertical space reserved between the valediction and the name line —
    /// SINGLE SOURCE for measure AND draw (lockstep). Snug when a signature
    /// image will be stamped (29pt cap + margins); the full historical 50pt
    /// when there is none, so a printed letter keeps room to sign by hand.
    private static func signatureGap(_ context: RenderContext) -> CGFloat {
        context.profile.signatureImageData == nil ? 50 : 36
    }

    private static func drawSignature(_ s: SignatureContent, context: RenderContext, y: CGFloat) -> CGFloat {
        var dy: CGFloat = 0
        // Valediction
        dy += drawString(s.valediction, attrs: context.body, rect: context.lineRect(y: y + dy), context: context) + 2
        // Handwritten signature: stamped INSIDE the reserved gap (see
        // signatureGap — snug 36pt with an image so "Regards," sits close;
        // full 50pt without one, preserving wet-signing room). Bottom-aligned
        // just above the name line, aspect preserved.
        let gap = signatureGap(context)
        if let data = context.profile.signatureImageData, let image = UIImage(data: data) {
            // 65% of the original 44/220 caps — full size printed too bulky.
            // Applies to ALL reports (a per-block size slider was tried and
            // rejected in favour of one global size).
            let maxH: CGFloat = 29
            let maxW: CGFloat = 143
            let scale = min(maxH / image.size.height, maxW / image.size.width)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: context.contentRect.minX,
                                  y: y + dy + (gap - drawSize.height - 3),
                                  width: drawSize.width,
                                  height: drawSize.height))
        }
        dy += gap
        // Name + credentials (left) and practitioner ID (right); empty parts
        // are suppressed rather than printing dangling separators.
        let creds = s.credentialsOverride ?? context.profile.credentials
        let nameStr = creds.isEmpty ? context.profile.name
                                    : "\(context.profile.name), \(creds)"

        NSAttributedString(string: nameStr, attributes: context.body)
            .draw(in: CGRect(x: context.contentRect.minX, y: y + dy, width: 250, height: 16))

        if !context.profile.practitionerID.isEmpty {
            let idStr = "Practitioner ID: \(context.profile.practitionerID)"
            let idAS = NSAttributedString(string: idStr, attributes: context.body)
            let idW = idAS.boundingRect(with: CGSize(width: 300, height: 16), options: .usesLineFragmentOrigin, context: nil).width
            idAS.draw(in: CGRect(x: context.contentRect.maxX - idW, y: y + dy, width: idW, height: 16))
        }
        dy += 16

        return dy
    }

    // MARK: - Drawing helpers

    @discardableResult
    private static func drawString(_ s: String, attrs: [NSAttributedString.Key: Any], rect: CGRect, context: RenderContext) -> CGFloat {
        drawAttributedString(NSAttributedString(string: s, attributes: attrs), rect: rect, context: context)
    }

    @discardableResult
    private static func drawAttributedString(_ as_: NSAttributedString, rect: CGRect, context: RenderContext) -> CGFloat {
        if as_.length == 0 { return 0 }
        let unbounded = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: .greatestFiniteMagnitude)
        let bounds = as_.boundingRect(with: unbounded.size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let drawRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bounds.height)
        as_.draw(in: drawRect)
        return bounds.height
    }

    // MARK: - Utilities

    /// "9 AUG 2026" — the ALL-CAPS three-letter month, everywhere a date
    /// prints (date block, DOB, tokens). en_US_POSIX pins the symbols so the
    /// device locale can't reintroduce lowercase or periods; the editor-side
    /// `MonthFormat.abbreviations` (EditorStyle.swift) mirrors this list and
    /// must stay in step.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy"
        f.shortMonthSymbols = f.shortMonthSymbols.map { $0.uppercased() }
        return f
    }()

    private static func dobString(from comps: DateComponents?) -> String {
        guard let comps else { return "" }
        guard comps.year != nil, comps.month != nil, comps.day != nil else { return "" }
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return "" }
        return Self.dateFormatter.string(from: date)
    }
}

// MARK: - Render context (shared state for a single render pass)

private struct RenderContext {
    let document: ReportDocument
    let profile: PractitionerProfile
    let contentRect: CGRect

    func lineRect(y: CGFloat) -> CGRect {
        CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: .greatestFiniteMagnitude)
    }

    /// Body size from the document (nil = the historical 11pt). Every text
    /// attribute below derives from this, so measure/split/draw scale in
    /// lockstep automatically.
    var bodySize: CGFloat {
        CGFloat(document.bodyFontSize ?? 11)
    }

    /// Title blocks: body + 2 (historically 13 over 11).
    var titleSize: CGFloat { bodySize + 2 }

    var body: [NSAttributedString.Key: Any] {
        attrs(size: bodySize, weight: .regular)
    }

    var boldBody: [NSAttributedString.Key: Any] {
        attrs(size: bodySize, weight: .bold)
    }

    func attrs(for emphasis: Emphasis) -> [NSAttributedString.Key: Any] {
        switch emphasis {
        case .regular:             return attrs(size: bodySize, weight: .regular)
        case .bold:                return attrs(size: bodySize, weight: .bold)
        case .italic:              return attrs(size: bodySize, weight: .regular, italic: true)
        case .boldItalic:          return attrs(size: bodySize, weight: .bold, italic: true)
        case .underline:           return attrs(size: bodySize, weight: .regular, underline: true)
        case .boldUnderline:       return attrs(size: bodySize, weight: .bold, underline: true)
        case .italicUnderline:     return attrs(size: bodySize, weight: .regular, italic: true, underline: true)
        case .boldItalicUnderline: return attrs(size: bodySize, weight: .bold, italic: true, underline: true)
        }
    }

    func attrs(size: CGFloat, weight: UIFont.Weight, italic: Bool = false, underline: Bool = false) -> [NSAttributedString.Key: Any] {
        // Reports print in HELVETICA (user choice — the system font read as
        // "modern app", not "letter"). This is the ONE place render fonts
        // are built, so measure/split/draw/countPages all stay in lockstep
        // through the swap. Only regular/bold are used app-wide; the four
        // bundled Helvetica faces cover the emphasis grid. Fallback to the
        // system font only if the face were ever missing.
        let name: String
        switch (weight == .bold, italic) {
        case (false, false): name = "Helvetica"
        case (true,  false): name = "Helvetica-Bold"
        case (false, true):  name = "Helvetica-Oblique"
        case (true,  true):  name = "Helvetica-BoldOblique"
        }
        let font = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
        var result: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        // Underline is a text attribute, not a font trait, and doesn't change
        // line metrics — so measure/split/draw stay in lockstep with no other
        // change than adding the attribute here.
        if underline {
            result[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return result
    }
}
