# EYEreport — Clinical Report Composer

Standing context: design, conventions, and hard-won lessons. Read this AND
`PROJECT_STATE.md` (current status, next step, session log, and the numbered
Standing decisions table) before making changes. The conventions here are
deliberate decisions, not defaults — follow them unless explicitly told
otherwise.

## What this app is

A composer for clinician-to-clinician correspondence: referral letters, exam
reports, agency letters (driver's-licence vision confirmations), screening
reports. The user fills a template, adjusts a few fields, and generates a PDF
stamped onto an office letterhead, then prints or faxes it. Any letter type is
just a different ORDER of the same typed blocks — never new layout code.

This is **not** EYEbrary (the user's patient-facing diagnostic-report app).
Different audience, different lifecycle, different data model — do not import
its assumptions. If a truly shared utility emerges, factor it as a small Swift
package rather than coupling the two apps.

## Working method

**Claude Code works directly in this repo.** At the start of a session, read
`CLAUDE.md` and `PROJECT_STATE.md`, then continue from the "NEXT SESSION —
START HERE" pointer or the user's request. The earlier workflow (an Opus
planning chat emitting scoped "brick" prompts for a smaller model) is
RETIRED; a separate planning conversation remains an option at genuinely
crucial points (e.g. scoping the vault), at the user's call.

- **Model/renderer changes are allowed but must be flagged.** Any change to
  `ReportModel.swift` or `ReportRenderer.swift` gets called out in the
  stop-report: what changed, why, and how existing saved JSON keeps decoding.
  Additive, zero-migration changes are the norm (optional fields with nil
  defaults; custom decoders for type changes). When a task reveals the model
  is missing something, say so — don't invent a parallel structure.
- **Execute, then stop — do not build or test.** The command-line build is not
  authoritative: SourceKit "cannot find in scope" / "No such module"
  diagnostics from the CLI path are FALSE POSITIVES. The user builds in Xcode
  (the source of truth), verifies visually (the Simulator is authoritative for
  gesture/tap behavior; the Preview canvas is not), and reports back; fixes
  continue in the same session.
- **End every piece of work with a compact stop-report:** files changed, one
  line each, anything flagged or uncertain, and exactly what the user should
  check after building.
- **Keep tasks small and bounded.** The block model's boundaries draw the
  seams. The user commits between verified chunks; suggest a commit when an
  arc completes and is verified.
- The user is a clinician — competent but not fluent in software jargon.
  Explicit step-by-step instructions, explain terms the first time they
  matter, direct and spare, no flattery.
- The user never edits these two .md files by hand. When asked (or when an
  arc completes), update them surgically and keep `PROJECT_STATE.md`'s
  "NEXT SESSION — START HERE" pointer current.

## No patient data in the repo — including as examples

**The GitHub repo is PUBLIC** (`XbalSoftware/EYEreport`). Nothing that
identifies a real patient may enter it: not in code, not in comments, not in
test fixtures, not in these .md files, not in a commit message. Treat every
line written here as permanently public the moment it is committed.

- **Placeholder names must be self-evidently fake.** Use `PATIENT, Pretend`,
  `Dr. John Sample`, `Dr. Your Name` — the names the 1.0 screenshots used.
  Never invent a realistic-sounding name: once written down, a plausible name
  cannot be told apart from a real one by anyone reading the repo later, so
  it can neither be audited nor safely assumed harmless. The same goes for
  DOBs, health numbers, phone and fax numbers, and addresses.
- This covers **screenshots** — App Store listings are public and permanent —
  and any sample IRIS export used for parser work: fabricate the whole
  document rather than lightly editing a real one.
- Before committing anything containing a name, grep the working tree for it.
- If real data ever does reach a commit, know that squashing history does NOT
  fully remove it: orphaned commits stay reachable on GitHub by direct SHA
  until GitHub Support garbage-collects them on request. Rewriting history is
  the first step, not the whole fix.

## Platform & dev conventions

- Targets: **iPad** and **Mac (Designed for iPad)**. No iPhone, no native Mac
  target — one single iOS build. `#if os(iOS)` is true everywhere including on
  Mac; do NOT add `#if os(macOS)` branches or AppKit code.
- Minimum deployment: iOS 17.6 / macOS 15.6 — backward compatibility is
  intentional; flag any API above these floors. The iOS-26 editable-
  `AttributedString` `TextEditor` is not available and not needed.
- New `.swift` files go in the **source folder alongside `ReportModel.swift`**,
  NOT the repo root (`PBXFileSystemSynchronizedRootGroup` auto-registers
  source-folder files; a root file won't appear in Xcode). Never hand-edit
  `project.pbxproj`; framework linking happens via `import`.
- Swift concurrency checking stays at **Minimal** while prototyping;
  `Sendable` conformances are deliberately omitted from the model for now —
  add them together when vault decryption moves off the main actor.

## The data model (ReportModel.swift)

The agreed document model, worked out before any code. Build against it; flag
changes (see Working method).

- A report is an **ordered list of typed blocks** (`[Block]`). From scratch =
  empty list; template = saved list with defaults; filled report = list with
  patient data. Same structure throughout; only storage differs. Block types:
  recipient, title, date, patient, subject, salutation, prose, findings,
  impressionsPlan, closing, signature, spacer.
- Prose: `Paragraph = [Run]`; `Run = { content: .fixed/.token/.slot, emphasis
  (regular/bold/italic/boldItalic + four underline combos) }`;
  `ParagraphStyle` = `.body`/`.bullet`/`.numbered`/`.indented(level)`
  (`.numbered` stores no counter — the renderer derives it). Slots =
  pick-one-or-free-type; tokens resolve patient/practitioner/date at render.
- Every value-bearing element carries **`CarryForward`** (`.sticky`/`.volatile`,
  default volatile) — drives duplicate-for-new-visit: sticky survives,
  volatile clears. The guard against last visit's measurements landing on this
  visit's letter.
- The **patient block is a self-contained, copyable unit**. Three operations
  the model exists to make trivial: `newReport(from:carryingPatient:)`,
  `duplicatedForNewVisit()`, `asTemplate(named:)`. Save-as-template MUST route
  through `asTemplate` (the PHI-stripping path); it blanks ONLY the patient
  and date blocks — everything else deliberately set carries into a template.
- **A template IS a `ReportDocument` with `templateName != nil`** — there is
  no separate Template type and must never be one.
- Sanctioned model changes so far (all additive / zero-migration): `Emphasis`
  underline cases + `ParagraphStyle.numbered`; the `newReport(from:)`
  overload; `asTemplate` blanking only patient+date; **`ProseContent.boxed:
  Bool?`** (nil-default optional so old JSON decodes; `true` = the Boxed Prose
  block — a flag, NOT a new `BlockContent` case); **`LabeledSection.label:
  String → ProseContent`** (rich section labels; a custom decoder maps a
  legacy String to the single bold run it always rendered as, and a String
  convenience init keeps old construction sites compiling);
  **`PatientContent.fieldOrder: [PatientField]?` + `fieldLabels:
  [String: String]?`** (nil-default optionals — patient row order/presence
  and custom labels, e.g. AHC → "PHN"; nil = the historical five in standard
  order with default labels; a field absent from `fieldOrder` is deleted from
  that template — not prompted, not printed — while its TYPED storage stays,
  so identity matching, tokens, and `blanked()` are untouched; labels stored
  WITHOUT punctuation, renderer adds ":");
  **`SalutationContent.dearDoctor` gained `mirrorsRecipient: Bool`** (a custom
  Codable replicates the synthesized JSON shape — `{"custom":{"_0":…}}` etc. —
  and a missing key decodes as true, so legacy salutations decode unchanged
  with mirroring on); **`ReportDocument.bodyFontSize: Double?`** (nil-default
  optional — rendered body size, nil = the historical 11pt);
  **`BlockContent.spacer(SpacerContent)`** (a twelfth case — `{ lines: Int =
  1 }`, an adjustable blank vertical gap; a NEW case rather than a flag
  because it carries no text and belongs nowhere else. Old JSON never
  contains it, so decoding is unaffected).
- The `#if DEBUG` `ModelProof` block has been deleted (sanctioned cleanup,
  done).

## App shell (three tabs)

New Report · Templates · Settings. Letterheads moved UNDER Settings (rarely
used); the Saved Reports tab is SUPPRESSED while the vault is back-burnered
(the stub view file exists, unmounted). One each of `LetterheadStore`,
`TemplateStore`, `PractitionerProfileStore`, `DraftStore`, `ProviderStore`,
`PatientImportInbox`, and `TabRouter` are created app-level in `EYEreportApp`
and injected via `.environmentObject`. Do NOT create per-view store instances (stale-copy
bug); any `#Preview` rendering a view that reads a store must inject one.
Sheets re-inject explicitly (see NewReportView's preview sheet).

- **New Report** (`NewReportView`): chooser (Blank + templates list,
  `.searchable` case-insensitive name filter that preserves the arranged
  template order, plus **"Import report PDF…"** — reopens a previously
  exported report from its EMBEDDED source as an EXACT copy, fresh document
  id only; the user REJECTED routing it through `duplicatedForNewVisit`
  (volatile-clearing read as "blank fields" — they edit by hand instead);
  see EmbeddedReport below), plus **"Import patient details…"** — reads an
  IRIS PDF into the report via the review sheet (see Patient-detail import
  below); a pending shared-in patient shows as a "Patient Details Ready"
  section above the draft row) → block editor → Preview. The working document is a concrete `@State ReportDocument`
  gated by an `isEditing` Bool — see LESSONS. The two finish actions —
  Save-as-Template (bordered; routes through `asTemplate(named:)`) and
  Preview (borderedProminent, the primary, presented via `.sheet(item:)` on
  a tap-time `PreviewPayload` snapshot; never `.sheet(isPresented:)`
  re-reading state — see LESSONS) — sit in `finishBar`, a fixed-height
  (`finishBarHeight` = 68) bar PINNED to the screen bottom via
  `ZStack(alignment: .bottom)` with `.ignoresSafeArea(.keyboard, edges:
  .bottom)` ON THE BAR ONLY; the editor keeps keyboard avoidance, and a
  clear `safeAreaInset` spacer of the same height keeps the last block
  scrollable above the bar. Do NOT mount it as `.safeAreaInset` (a
  stale/phantom keyboard height floats it mid-screen) or as a `.bottomBar`
  toolbar item (collapses to a floating overflow button) — see LESSONS.
  There is no "…" menu. Top bar: Start Over alone at left; the (+) Add Block
  menu and Arrange grouped at right (Arrange in the corner).
- **Draft autosave (`DraftStore.swift`)**: the SINGLE active report survives
  an app quit. While `isEditing`, a 5-second timer + scenePhase-leaves-active
  both call `draftStore.autosave(document:baseline:)` (the BASELINE rides
  along so ModifiedTextGuard warnings resume intact); an encoded
  sortedKeys snapshot (savedAt excluded) makes unchanged ticks free. The
  chooser shows a "Resume Draft" row (patient name + save time) when a draft
  exists. Starting a new report first warns "Replace saved draft?" IF the
  draft has modified text (mirrors Start Over), then autosaves the fresh
  session immediately; Start Over (both paths) and Reset App clear the draft.
  Exporting does NOT clear it (user decision). Privacy: this is a mini vault
  of one — payload AES.GCM-sealed (CryptoKit), key in Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no user-presence gate —
  restore is deliberately silent), file `draft.sealed` in the app-support dir
  excluded from backup, `FileProtectionType.complete` as defense-in-depth.
- **Preview** (`PreviewView`): renders the document read-only via
  `ReportRenderer.renderToPDFData` into a continuous vertical `PDFView`, with
  a top-right letterhead menu — "None (plain)" (the renderer's 72pt-inset
  fallback) plus each stored letterhead. The choice is **STICKY app-wide**:
  `LetterheadStore.activeSelection` (a `LetterheadSelection?` — `.plain`,
  `.letterhead(id)`, or nil = never chosen → fall back to the FIRST stored
  letterhead; persisted in UserDefaults, letterheads.json untouched) seeds
  every Preview and is written back on every pick, including "None".
  Settings → LETTERHEADS shows it as a radio button per row; deleting the
  active letterhead resets the selection to never-chosen.
  `ReportDocument.letterheadID` remains unused by this flow (per-document
  letterhead was never wired; the sticky choice is deliberately app-wide). A **"Text
  size" menu (9–13pt, 11 default)** re-renders live and pushes the choice
  back to the WORKING document via `onFontSizeChange` (the preview holds a
  snapshot; without the callback the choice would die with the sheet) — it
  persists on the report and rides into save-as-template. All render fonts
  derive from `RenderContext.bodySize` (`document.bodyFontSize ?? 11`;
  titles = body + 2; page stamp fixed 9), so measure/draw scale in lockstep.
  The output typeface is **HELVETICA** (user choice, swapped from the system
  font), built in ONE place — `RenderContext.attrs(size:weight:italic:
  underline:)` — mapping regular/bold × upright/oblique to the four
  OS-provided Helvetica faces by name (no `UIAppFonts`; nothing is bundled),
  with a system-font fallback if a face is ever missing. Change typeface only
  there.
  Range capped at 13: patient fullBox rows are a fixed 16pt line height.
  Practitioner identity resolves from the stored profile. **Export = three
  toolbar actions**, all fed the CURRENT rendering (letterhead + text size):
  a **Print button** (`UIPrintInteractionController`, PDF data as
  `printingItem`, jobName = the export filename, presented from a
  top-trailing anchor rect in the key window — iPads need an anchor), a
  **Save to Files button** (`.fileExporter` + the minimal `PDFExportDocument`
  FileDocument wrapper), and a **Share button** as overflow (AirDrop /
  Messages / EMR share extensions) — a `UIActivityViewController` fed a
  CONCRETE tmp-file URL (written at tap time; PHI briefly in tmp is inherent
  to exporting). All three names come from `exportBasename`, the single
  source: **"LAST, First yyyy-MM-dd"**, matching how the letter itself prints
  the patient. The surname is upper-cased THERE rather than assumed of the
  stored value, so a hand-typed name is filed like an imported one. NOT SwiftUI `ShareLink`+`Transferable`: the
  file-promise it hands extensions left iDoc's EMR import button grayed
  out, while a real file URL (the same shape the Files app shares) works.
  Print and Share share the key-window / top-view-controller / anchor
  helpers in PreviewView. CAVEAT: export outputs exactly what preview shows,
  including unfilled placeholder prompts — the output-vs-placeholder cleanup
  (Deferred design) is still open, and one-tap Print makes it more visible.
- **Embedded report source (`EmbeddedReport.swift`)**: every PDF the
  renderer produces carries the full `ReportDocument` JSON (base64,
  "EYEreport1:" prefix) in the **"Keywords"** PDF Info key
  (`UIGraphicsPDFRendererFormat.documentInfo` at write; `CGPDFDocument.info`
  at read). It MUST be a documented Info key: CGPDFContext silently DROPS
  custom keys, while Keywords carries a 120KB payload intact. A device build
  then produced a PDF with NO Keywords despite the documentInfo write, so
  `renderToPDFData` ends with `ensuringEmbeddedSource`: if the rendered bytes
  lack a readable payload, it re-serializes ONCE through PDFKit
  (`PDFDocumentAttribute.keywordsAttribute`, which the CGPDFDocument read path
  sees and which preserves page content). Keep BOTH writers
  pointed at the same key. "Import report
  PDF…" on the chooser reads it back for perfect-fidelity reopening —
  deliberately NOT text-scraping the PDF (rejected: silently error-prone).
  Same PHI the PDF shows visibly, no new exposure. Caveats: only PDFs
  exported after this feature carry the payload; a pipeline that REWRITES
  the PDF may strip it. This is the stopgap for "reopen last year's
  report" until the VAULT (the planned long-term answer) is built.
- **Patient-detail import from IRIS** (`PatientDemographics.swift`,
  `PatientDemographicsParser.swift`, `PatientImport.swift`,
  `PatientImportInbox.swift`, `DemographicsReviewSheet.swift`): the parser
  machinery is PORTED FROM FORM FILLER. Pure text→struct, anchored on the
  "FILE EXCERPT" divider (which is what keeps the clinic letterhead out of
  the patient block) plus per-section anchors for exam values — every
  section reuses `OD:`/`OS:`, so refraction MUST be anchored to
  "Subjective Refraction (BVA)" or it grabs the autorefractor, and IOP
  requires "mmHg" on the line or it grabs the adjacent Pachymetry (µm) row.
  Adapted to this app's model, not re-invented: the name comes back SPLIT
  with the surname UPPER-CASED (so the review sheet and the patient block show
  the "LAST, First" that will print, and the renderer's own `.uppercased()`
  becomes a no-op) and the DOB as `DateComponents` (impossible dates → nil,
  never a silently rolled-over date).
  **Uncorrected (sc) acuity does NOT follow the section/OD/OS shape the other
  findings do.** Under "Entrance Skills →
  Visual Acuities" the viewing condition is labelled PER EYE
  ("Distance • Glasses" / OD line / "Distance • Unaided" / OS line), so an eye
  appears only under the condition it was measured in and a ONE-EYED result is
  normal. `uncorrectedVisualAcuities` therefore can't use `odosValues` (which
  demands both eyes): it treats every line naming an uncorrected condition as
  a marker and collects the eye lines beneath it, merging across markers.
  Three guards stop a stray marker from importing anything — a free-text note
  such as "OD with correction, OS without correction" reads exactly like a
  condition label: values must be Snellen-shaped (near acuities in M units and IOP
  lines both fail this), collection stops at the first non-eye line once it
  has begun, and the scan aborts if a line names a DIFFERENT viewing condition
  (`namesCorrectedCondition`) before any value appears.
  Note "Distance • Glasses" is habitual/aided acuity and is deliberately NOT
  read as cc — corrected VA comes from the subjective refraction, which is
  what the user asked for ("VA as measured with the refraction").
  **Mapping is the part that could NOT port**: Form Filler keys on a field's
  TYPE; findings rows here carry only a free-text label, so `ExamFinding`
  matches rows by keyword — long phrases ("refract", "acuity", "kerat",
  "pressure") anywhere in the label plus whole-word abbreviations ("va",
  "iop", "k"), all derived once in `ExamFinding.Labelling`. "visual" alone is
  deliberately NOT a keyword or the standard "Visual field (FDT)" row would
  swallow visual acuity. Matching is GRADED (`matchQuality`: nil / 1
  plausible / 2 explicit) and each finding takes the BEST unclaimed row
  across every findings block, ties to document order — so an explicit
  "VA (cc)" beats a bare "VA" regardless of which sits higher in the grid. A
  finding with no row is REPORTED (shown in the review sheet before
  applying), never silently dropped.
  **cc vs sc**: corrected VA comes bundled with the subjective refraction
  (always) and uncorrected VA from its own section (often absent). A row must
  carry an explicit sc marker ("sc", "unaided", "uncorrected") to receive the
  uncorrected value; a BARE "VA" row means corrected by convention, and
  uncorrected will NOT fall back to it — guessing there prints the wrong
  acuity, which is worse than leaving it for the clinician.
  **Synthesized findings**: `refractionWithVisualAcuity` has no storage of its
  own — `values(for:)` composes it from the refraction and cc VA on READ, so
  a review-sheet edit flows into it instead of leaving a stale copy. It is
  declared FIRST (`allCases` order is match order) so it claims a fused
  "Refraction / VA" row before plain refraction can; plain refraction still
  takes such a row at quality 1 when nothing fuses (a refraction with no VA).
  Synthesized findings are never reported unmatched (having no fused row is
  the normal case), and anything a fused row delivered is filtered out of
  `unmatched` via `components` — otherwise a post-cataract template with only
  a fused row would claim refraction and VA had nowhere to go.
  `PatientImport.storedValue` is the single place that reconciles a parsed
  value with its row's affordance — the renderer PREPENDS "20/", so VA must
  be stored as "15", not "20/15". Spanning rows ignore affordances at render
  and so get the raw values, eye-labelled.
  A mandatory `DemographicsReviewSheet` (every value editable, rows fixed at
  present-time) stands between the parse and the document — non-negotiable,
  since the parser is tuned to one EMR's layout. Nothing is written on
  cancel; on apply, values go into the working document and straight to the
  draft, i.e. exactly where typed data goes and nowhere else. Include
  toggles, row labels, affordances, and patient layout are never touched.
  Intake is both push and pull: `Info.plist` declares `com.adobe.pdf`
  (`CFBundleDocumentTypes`) so the app appears in the EMR's Share sheet, with
  `LSSupportsOpeningDocumentsInPlace` explicitly **false** — so iOS always
  hands over a COPY in `Documents/Inbox`, which `PatientImportInbox` DELETES
  as soon as it has read it (the PHI answer). The key must be PRESENT rather
  than omitted, or the build warns that the app opens files without declaring
  how; never silence that warning with `UISupportsDocumentBrowser`, which
  declares the opposite and would leave patient PDFs sitting in the app. `EYEreportApp`'s
  `.onOpenURL` feeds the inbox and switches to the New Report tab. The inbox
  checks the EMBEDDED payload FIRST — our own exports also contain readable
  patient text, so a shared EYEreport PDF must reopen as a report, not be
  scraped into a handful of fields. Routing in `NewReportView`: shared while
  editing → review sheet at once; shared at the chooser → HELD (a "Patient
  Details Ready" section) until a template is picked, so the template choice
  stays the clinician's. The import surface (picker + sheet + alert +
  inbox watchers) hangs off `mainContent` INSIDE the NavigationStack, not
  the stack itself — the stack already carries five alerts and the preview
  sheet, and a second `.sheet` on the same view is unreliable.
- **Templates** (`TemplateStore`): an `ObservableObject` persisting
  `[ReportDocument]` as JSON at `Application Support/EYEreport/templates.json`.
  On FIRST launch only (file absent) it seeds the built-in from
  `Presets.swift` (`standardReferral` ONLY — the driver's-licence letter was
  deliberately REMOVED from the seeds; the user maintains it as an ordinary
  template); after seeding they are ordinary user-deletable templates (a
  corrupt file leaves the store empty rather than re-seeding). `Presets.swift`
  is only the seed source. **Export/Import** (TemplatesView "…" menu): export
  = ALL templates as one named JSON file via `ShareLink` +
  `FileRepresentation` (same pattern as the PDF export; templates carry no
  PHI); import = `.fileImporter` (needs `startAccessingSecurityScopedResource`
  for Files-app URLs) decoding `[ReportDocument]`, appended via
  `importTemplates` which assigns FRESH ids (re-import duplicates instead of
  colliding). This is the backup/restore path around app reset.
- **Settings** (`PractitionerProfileStore` at `Application
  Support/EYEreport/profile.json`, saved on every change): practitioner name,
  credentials, practitioner ID, and the handwritten signature.
  **`SignaturePad.swift`** is a hand-rolled Canvas + DragGesture pad (NOT
  PencilKit — works identically with finger/pencil on iPad and mouse on Mac,
  no tool-picker chrome), presented as a fixed non-scrolling sheet so drags
  ink rather than scroll. `SignatureInk` is the single source for stroke
  smoothing (midpoint quad curves) used by BOTH the on-screen preview and the
  export; export = black ink on TRANSPARENT PNG at 3×, cropped to the
  strokes' bounding box. A signature can also be IMPORTED (.png/.jpg,
  fileImporter attached to its own button to avoid colliding with the
  letterheads importer) — downscaled to ≤1200px, re-encoded PNG (bakes EXIF
  orientation; JPEG keeps its white background, invisible on white paper).
  Remove-signature asks for confirmation. The renderer stamps the image
  INSIDE the reserved gap (bottom-aligned, ≤29pt tall / ≤143pt wide — 65% of
  the original caps, a GLOBAL size; a per-block size slider was tried and
  rejected). The gap itself is `signatureGap(context)` — the SINGLE SOURCE
  for measure AND draw: snug 36pt when a signature image exists ("Regards,"
  sits close), the full historical 50pt when none (wet-signing room on a
  printed letter). Empty credentials/ID print nothing rather than dangling
  separators. Settings also hosts **ABOUT** (→ `AboutView.swift`: app
  description, version/developer from the bundle, brief plain-language
  EULA, and links held as `AboutLinks` constants — website and privacy
  policy both point at the live GitHub Pages site
  (`https://xbalsoftware.github.io/EYEreport/` and its `#privacy` anchor);
  there is no separate user-manual constant, because the manual IS that page.
  `linkRow` still renders a nil URL as a grayed "coming soon" row rather than
  a dead link — keep that behaviour for any future link. Support email
  xbalsoftware@gmail.com as a mailto Link) and **BACKUP** — one Files-app JSON of the
  whole backed-up store (`AppBackup.swift`: templates, profile incl.
  signature, letterheads incl. safe zones, providers, sticky letterhead id;
  NO PHI — the draft is excluded by design). Export = `.fileExporter` +
  `BackupDocument`; import = `.fileImporter` attached to its own button,
  decode → "Import backup?" confirmation → wholesale REPLACE via
  `replaceAll` on TemplateStore/LetterheadStore (ids kept — unlike the
  Templates-tab import, which appends with fresh ids) + direct assignment
  for profile/providers. And **Reset App to Defaults** (confirmation alert →
  `TemplateStore.resetToDefaults()` re-seeds `Presets.all`,
  `LetterheadStore.removeAll()`, profile back to `PractitionerProfile()`,
  providers + draft cleared; a backup file is the restore path).
- **Letterheads** live INLINE on the Settings page (no click-through screen;
  `LetterheadsView.swift` was DELETED): the LETTERHEADS section lists each
  letterhead (row pushes `SafeZoneEditorView` on Settings' stack), a trash
  button with confirmation (a letterhead carries its calibrated safe zone),
  and an "Import letterhead PDF…" button (`fileImporter`, validated via
  PDFDocument). Import a letterhead PDF; capture its safe zone and
  page-number position per office. The safe-zone editor is handle-based: 8
  drag handles resize, dragging the interior moves, a separate draggable pin
  sets the page-number position; no draw-from-scratch gesture; all gestures
  share one named coordinate space; bare-background taps do nothing.

## Two-store split (load-bearing for privacy)

- **Backed-up store**: templates, letterheads, practitioner profile, settings
  — no patient data; syncs and backs up normally.
- **Vault**: filled reports (PHI) — encrypted, device-only, biometric-gated,
  excluded from backup, never transmitted over any network. The only crossing
  is save-as-template, which strips patient data first (via `asTemplate`).
- **Import exception (not really an exception)**: patient details read from an
  imported/shared PDF live in memory only (`PatientImportInbox`) until the
  clinician applies them; from then on they are ordinary report data under the
  draft's guarantees. The staged inbox copy of the source PDF is deleted
  immediately. No separate patient store is created — that would be the
  patient registry this app deliberately doesn't have.
- **Draft exception**: the single active draft persists OUTSIDE the vault but
  under the same guarantees minus the auth gate — AES.GCM-sealed,
  Keychain-held device-only key, backup-excluded (see App shell → Draft
  autosave). Deliberate: quit-safety requires silent restore.

## Vault (NOT built — design intent)

- App-layer encryption, not OS file protection: each report's Codable blob
  sealed with CryptoKit `AES.GCM`. Data key = 256-bit `SymmetricKey` in the
  Keychain behind `SecAccessControl` with **`.userPresence`** (NOT
  `.biometryCurrentSet` — the user's Mac Mini has no Touch ID). Auth gates
  **key retrieval**; a screen-level lock is UX only and must not be the
  security boundary.
- Store the structured document, not a flattened PDF — reports must reopen and
  edit; re-render on demand. Vault directory `isExcludedFromBackup = true`;
  iOS `FileProtectionType` is defense-in-depth, not the primary guarantee.
- Privacy overlay on `scenePhase` background/inactive so on-screen PHI is not
  captured in the app-switcher snapshot.
- Search: one auth gate decrypts report metadata (patient name, DOB, date,
  type) into memory for the session; search runs in memory; no plaintext PHI
  index ever persists outside the vault. Match patients on
  lastName + firstName + dob.
- **No patient registry** — patient identity derives from reports in the
  vault; do not build a patients CRUD surface. Two moves: "new report, same
  patient" copies just the patient block forward; "duplicate this report"
  keeps patient + sticky values, clears volatile ones.

## Rendering pipeline (ReportRenderer.swift — BUILT)

- A letterhead is `Letterhead { id, name, pdfData, safeZone, pageNumberOrigin,
  timestamps }`, persisted as JSON by `LetterheadStore` (PDF inline as `Data`).
  Letterhead choice is **orthogonal** to the document: any document prints on
  any letterhead; one practitioner identity, many letterheads.
- **Coordinate space (the historically bug-prone part).** `safeZone` and
  `pageNumberOrigin` are stored **NORMALIZED 0–1** in **UIKit / top-left
  space** (y DOWN). They are captured from on-screen taps (already top-left),
  so there is **no PDF/bottom-left conversion** on stored values.
  `contentRect(forPageSize:)` / `pageNumberPoint(forPageSize:)` return
  UIKit-space values — do NOT add a y-flip (an earlier double-flip bug came
  from treating them as PDF-space). The ONLY correct CTM flip is drawing the
  letterhead PDF page itself as the background (PDF pages are bottom-left
  origin).
- Compose with **PDFKit**: the letterhead page is drawn (CTM-flipped) as the
  background on **every page**, content laid into the safe-zone-derived rect;
  every page geometrically identical. With no letterhead, fall back to a fixed
  72pt-inset content rect + fixed page-number position — keep this nil path
  working. Render at the letterhead's actual point size (US Letter 612×792) —
  1:1, no scaling.
- Pagination is **owned by us**:
  - **Findings grids split between rows** — whole rows fill a page, the OD/OS
    column headers + rule repeat on each continuation, a single row never
    splits. The optional lead-in header prints only on the grid's first page.
    **Findings columns are content-driven** (`findingsLayout`): the label
    column hugs the widest included label (60pt floor, 40%-width cap), OD/OS
    split the rest evenly, spanning rows run OD→right edge. **Row heights are
    content-driven too** (`findingsRowHeight`, 16pt floor): a wrapping value
    grows its row. Both are single-source — measure, the two pagination
    loops, AND draw all read them; never reintroduce a fixed offset/row
    constant in only one place.
  - **Prose splits between paragraphs**; a paragraph taller than a page splits
    **mid-text via TextKit** (`NSLayoutManager`/`NSTextContainer`), preserving
    run emphasis and resolved token/slot text across the seam.
  - **`impressionsPlan` and boxed prose do NOT split** — they move whole and
    overflow if taller than a page (deferred until it bites). Boxed prose is
    excluded from prose splitting in BOTH the draw loop and the `countPages`
    loop — the two gates must stay in step.
  - Infinite-loop guard: a block/row/line too tall for an empty page is drawn
    anyway and allowed to overflow, never bounced to a fresh page forever.
- **page-of-N** stamps at `pageNumberOrigin`, suppressed entirely on
  single-page documents; N comes from a `countPages` dry-run that mirrors the
  draw pass's break math.
- **Findings affordance is data-driven**: `applyAffordance` = `(prefix ?? "")
  + value + (suffix ?? "")`, suppressed entirely when the value is empty (an
  empty VA row prints truly blank, not a lone "20/"). The "20/" prefix and
  "mmHg" suffix are stored row data — editing/clearing them needs NO renderer
  or model change.
- **List rendering is column-aligned.** `buildParagraphAS` takes the full
  paragraph list + an index. A list marker ("•" / "N.") is followed by a
  **tab** whose stop sits at ONE shared text column for the whole run, sized
  by the run's **widest** marker (`numberedRunMax` — "11. " beats "1. "), so
  every item's text starts — and wraps (`headIndent`) — at the same x.
  `numberedOrdinal` derives each number from absolute position in the full
  paragraph list, so a list split across pages resumes correctly. A
  mid-paragraph page-split tail gets `firstLineHeadIndent = headIndent`
  (applied inside `splitAttributedString`, the ONE function both draw and
  `countPages` split through) so continuation lines stay at the indented
  column. An **empty list paragraph prints no marker and no column** — a blank
  line. Numbering still counts an empty mid-list item invisibly (deliberate:
  PDF numbers always match the editor gutter).
- **Boxed prose** (`ProseContent.boxed == true`): body drawn 6pt inset in a
  stroked black rectangle — the exact Impressions/Plan box geometry.
  `boxedProseHeight` is the single source for its measure and draw.
- **Patient block layout is single-source and data-driven**:
  `patientBoxRows` / `patientBoxLayout` / `patientComposedLine` feed BOTH
  `measureBlock` and `drawPatient`. Boxed styles fill two columns in reading
  order (row-major — with the default field order this reproduces the
  historical fullBox exactly); **address is a spanning field**: it flushes the
  row and takes the full width, growing to its wrapped height. Labels come
  from `customLabel(for:)` with per-style defaults (fullBox "DOB:", inline
  "Date of Birth:"); **reducedBox prints NO labels at all** — bare values,
  custom labels included ("Box — no labels" in the editor; the old
  name-only-unlabeled behavior was a bug the user flagged); the fullBox label
  column widens to the widest label in use (60pt floor). An all-fields-deleted
  patient block draws nothing at zero height.
- **Impressions/Plan measure + draw share `impressionsPlanLayout`** (single
  source). Section labels render RICH from their runs (bold is the seeded
  convention, not a hardcoded attribute) at measured height; an empty label
  takes no height.
- The closing sentences for `sharingInCare`/`contactOffice` live here as
  literals and are **hand-duplicated** in `ClosingEditor`'s grayed preview —
  no shared source of truth; edit both or neither.

## Measure/draw lockstep (do not break this)

Pagination depends on measure and draw agreeing exactly. Findings geometry and
prose geometry each have a **SINGLE source** used by the measure path, the
split logic, the draw path, AND the `countPages` pass. **If you change how
something DRAWS, change its measurement (and the count pass) in the same
place**, or splitting breaks at the wrong row/line and page-of-N disagrees
with the real page count. (`countPages` mirrors — doesn't literally share —
the draw pass's break logic; keep them in step.)

## Block editor architecture

- **`ReportEditorView(Binding<ReportDocument>)`** lists the blocks — a
  **ScrollView + VStack over `ForEach(document.blocks)`**, NOT a `List` (see
  LESSONS), with each editor mounted on an **id-based `contentBinding(for:)`**
  (safe fallback), NOT a `ForEach($…)` element binding — deleting the last
  block crashed otherwise (the documented lesson). Each row: type label
  (`blockTitleStyle()`) + the matching editor.
- **`BlockContentEditor(Binding<BlockContent>)`** is the dispatch: switches on
  the content case and mounts the per-type editor via an explicit
  `Binding(get:set:)` projection from enum case to concrete content type.
- **Per-type editors** (all twelve wired): Subject, Title, Closing,
  Salutation, Recipient, Date, Patient, Prose, Findings, ImpressionsPlan,
  Signature, Spacer. `SpacerEditor` is a bare stepper (1–20 blank lines); it
  holds no text, so it is deliberately absent from the tab chain and the
  deletion-warning fingerprint.
- **Arrange mode**: a custom "Arrange"/"Done" toolbar button toggles
  `isArranging`; each block then shows a grip (☰) + trash, and blocks are
  **drag-reordered by their header row** (reorder-on-hover `DropDelegate`s).
  The drag payload is a private `UTType` (`com.eyereport.block-drag`), NOT
  plain text — a text payload gets claimed by UITextViews (pasting the payload
  into prose and swallowing the drop), and the payload data must be consumed
  at drop or the session (and the source row's dimmed lift) lingers ~20 s.
  Drag exists ONLY in arrange mode and ONLY on the header (never over the
  editors). No swipe-delete, no `EditButton`, no state-driven dim-while-
  dragging (it proved sticky).
- **Deletion warnings (`ModifiedTextGuard.swift`)**: `NewReportView` captures
  a `baseline` snapshot when an editing session starts (the template copy or
  the blank document) and passes it into `ReportEditorView`. Deleting a block
  whose text FINGERPRINT differs from its same-id baseline block (or a
  user-added block holding any text), and Start Over when any block is
  modified, first show a "changes will be lost" alert. The fingerprint is
  normal-flow DATA-ENTRY text only. Deliberately excluded as structure:
  toggles, styles, order, everything behind an "Edit fields" toggle
  (findings header/row labels/affordances, patient custom labels,
  Impressions/Plan section labels), fixed-choice valedictions (picker, not
  typed; custom ones count), and a MIRRORING salutation's name (derived,
  not typed) — seeded boilerplate must stay out or freshly added blocks
  warn untouched.
  **When an editor gains a new user-typed field, add it to
  `ModifiedText.fingerprint(of:)`** — same mirror-maintenance rule as
  `FocusOrder`.
- **Add-block**: a "+" toolbar `Menu` (`NewBlockKind`) appends a
  minimally-seeded empty block (Prose one blank paragraph, **Findings the
  full standard grid** — `Presets.standardFindings`, single-sourced with the
  referral preset — Impressions/Plan self-seeds…). Also offers **Boxed Prose** — a `.prose`
  block with `boxed: true` (same `ProseEditor`; block header shows
  "BOXED PROSE"); intended for non-report letter types wanting framed prose.
  And **"Blank space"** — the `.spacer` block (header "BLANK SPACE").
  In arrange mode the same menu also appears as **"Add block here" buttons in
  every gap** (above the first block, between blocks, after the last),
  inserting at that position.

## Editor conventions (follow these)

- **Keyboard-first ("type, don't tap")**: typeable fields + tab order for
  scalar values; pickers only for strictly categorical choices (patient render
  style, salutation/recipient/closing kind).
- **Document-wide tab chain (`FocusChain.swift`)**: ONE `focusedKey` lives in
  `ReportEditorView`; a `BlockFocusChain` (block id + shared binding + move
  closure) threads through `BlockContentEditor` into every editor (`var focus:
  BlockFocusChain? = nil` — nil, as in previews, = plain fields, no Tab
  handling). Tab order is derived from the MODEL at every Tab press by
  `FocusOrder.orderedKeys(for:)`, so reordered/added/deleted blocks tab in
  their current visual order. Field names live in `FocusFields` (single
  source). **Adding/removing a chained field in an editor requires the
  matching change in `FocusOrder.keys(for:)`** — they mirror, they don't
  share. In the chain: every always-visible scalar field, findings value
  cells of INCLUDED rows, each consolidated prose box (ONE stop per box),
  each all-fixed Impressions/Plan body. Deliberately NOT in the chain:
  anything behind an "Edit fields" toggle (structural editing, not data
  entry) and the slot/token per-paragraph prose fallback.
- **`SelectAllTextField`** is the standard short-value input: UIKit-bridged,
  selects-all on focus, tab-chains focus onward. Use it over raw `TextField`
  for scalar entry. **`SelectAllTextView`** is the multi-line counterpart; its
  `selectAllOnFocus` can be set `false` to cursor-at-end instead (Prose-style
  fields use `false`).
- **All user-typed text renders bright red** (`.systemRed`, the default
  `textColor` of both bridged fields) — typed content is visually distinct
  from static labels. A `textColor:` override exists for rare semi-static
  heading fields.
- **Shared styling in `EditorStyle.swift`**: `blockTitleStyle()` (bold, larger,
  blue block headers), `fieldLabelStyle()` (small captions,
  `.primary.opacity(0.75)` for contrast on black), `standardFieldHeight`
  (30pt) applied to every single-line field app-wide; multi-line fields use it
  only as a floor (`max(standardFieldHeight, 60)`). Both bridged fields share
  one border/background style (`.secondarySystemBackground`, 6pt corner
  radius, 0.5pt separator border).
- **"Edit fields" toggle convention** for semi-static headings (Findings'
  lead-in header + row labels, ImpressionsPlan's section labels): read-only
  normally, editable only while the editor's "Edit fields" toggle is on. Never
  unconditionally editable. (Findings' header uses `SelectAllTextField`;
  ImpressionsPlan's labels are RICH and use a `ProseBlockEditor` behind the
  toggle, with a styled read-only preview when off.)
- **Digit-only auto-format on blur, never mid-typing**: phone/fax →
  `(999) 999-9999`, AHC → `99999-9999`, via `onEndEditing` and ONLY when the
  field is exactly the expected digit count with no other characters; anything
  else is left untouched.
- **Default keyboard on EVERY field — no `keyboardType` overrides.** The app
  is used with an external keyboard; `.phonePad`/`.numberPad` bought nothing
  there but made the hardware-keyboard assistant strip inconsistent (the mic/
  dictation icon appears only for dictation-capable keyboards — user flagged
  it). The `keyboardType` parameter still exists on `SelectAllTextField`
  (default `.default`); don't pass it. NOTE: SwiftUI's `.keyboardType()`
  MODIFIER is a silent no-op on the bridged fields — only the init parameter
  ever worked (this mismatch was the "DOB hides the mic but the date block
  doesn't" mystery).
- **Dates are three numeric type-in fields** (DD / MM / YYYY); display format
  ("9 AUG 2026", ALL-CAPS month) is the renderer's job. Patient DOB =
  `DateComponents`; the date block = a full `Date` assembled at noon
  (timezone-midnight guard). The MONTH field displays the ALL-CAPS
  abbreviation on blur ("8" → "AUG") while the model stays numeric: a local
  `monthDisplay` @State backs the field, `MonthFormat`
  (EditorStyle.swift) parses digits OR abbreviations and formats — its
  list mirrors the renderer's uppercased en_US_POSIX symbols; keep them in
  step. Unparseable month text stays visible as typed and stores nil. The
  date BLOCK also has a small "Today" button (stamps the current date at
  noon; added for reopened report PDFs, which restore the original date)
  shown ONLY while the stored date isn't already today (empty = not today)
  — its presence flags a stale date, and stamping dismisses it.
- **Presets are seeds, not live links** (EYEbrary assembly model): tapping a
  template drops a copy in; editing the copy never touches the source.
- Empty-string ↔ `nil` mapping happens in editor **bindings** (findings
  prefix/suffix, findings header) — don't change model optionality for it.

## Rich text in Prose (BUILT — model + renderer + editor)

- **`ProseEditor`** routes per block: an all-`.fixed` block gets the
  consolidated **`ProseBlockEditor`**; a block containing a slot/token run
  falls back to per-paragraph editors (`RichParagraphEditor` for fixed
  paragraphs, `slotFillRow` for slots, read-only for tokens) — consolidated
  multi-line list editing does NOT apply there (known limitation, fine).
- **`ProseBlockEditor`**: ONE `UITextView` editing the whole `ProseContent`.
  Newlines = paragraph boundaries (Return = new line in the same box);
  character attributes carry B/I/U; each paragraph's list style rides on a
  custom `.proseListStyle` attribute (+ hanging indent) so the backing string
  stays marker-free. Markers (•/N.) are DRAWN in the left gutter by
  `ProseListTextView` (a `UITextView` subclass, **TextKit 1 forced** via a
  `layoutManager` touch); numbering matches `numberedOrdinal`. A multi-line
  selection becomes a list in one tap.
- **List continuation & the parked pending style.** Return on a non-empty list
  item continues the list; the •/№ buttons work on an empty line; Return on an
  empty list item ends the list. Mechanism (do NOT "clean this up" — every
  rule closes a verified bug): a zero-length paragraph cannot carry
  attributes, so the trailing empty line's list style is **parked on the text
  view** (`pendingListValue`) — owned by THAT LINE, not the caret or focus (it
  survives blur and caret moves); its marker (correct next number) is drawn at
  TextKit's extra line fragment; it is **stamped onto real attributes in
  `textViewDidChange`** the moment the line gains text (deterministic — UIKit
  drops custom keys from typing attributes across paragraph boundaries, so
  `syncCaretState` re-adds them but is not relied on); it is retired by
  Return-Return, toggling the button off, or a deletion consuming the line.
  `trailingEmptyListValue` re-derives it from the model on load — this is what
  makes SEEDED blank bullets work. `pushParagraphs` post-fixes the trailing
  empty paragraph's model style from the parked value (model honesty).
- **`updateUIView` SKIPS rebuilds while the text view is first responder** — a
  stale binding echo through a deep chain (block enum → sections element →
  body) otherwise rebuilds one keystroke behind and yanks the caret backward.
  Nothing edits prose externally mid-typing; external syncs wait for blur.
- **Formatting UI**: a top-of-block `FormattingToolbar` (NOT a keyboard
  `inputAccessoryView` — that stranded on-screen with a hardware keyboard)
  wraps a UIKit toolbar so B/I/U/•/№ don't resign first responder; driven by a
  `ProseFormattingController` pointing at whichever field holds focus via the
  `ProseFormattingTarget` protocol. Buttons grey out when nothing is focused.
  One controller can drive multiple boxes (ImpressionsPlan shares one across
  its two sections). **⌘B / ⌘I / ⌘U** are wired as `UIKeyCommand`s on both
  prose text views for the external-keyboard workflow.
- **Autocorrect OFF, spellcheck ON** in prose fields (and `spellCheck` is a
  parameter on the bridged fields). Autocorrect mangles clinical terms; a red
  squiggle does not.
- Whole-paragraph indent renders via `NSParagraphStyle.headIndent` +
  `firstLineHeadIndent` (`ParagraphStyle.indented(level:)`). Read-only
  `AttributedString(markdown:)` is acceptable for display if useful.

## Per-editor decisions

**Findings** — one flexible grid: paired OD/OS rows and spanning rows. Row
labels, prefix ("20/"), and suffix ("mmHg") are editable/clearable per-row
data (one flexible VA row covers cc/sc/pinhole/Hand-motion — clear the prefix
and type words). Add/duplicate/delete/reorder rows built (up/down buttons in
edit-fields mode, not drag; the fixed catalogue of standard rows was DROPPED —
a new row is one blank custom row). Per-row include toggle dims but keeps the
row editable — inclusion is a print-time concern. Tab traversal covers every
included value cell in visual order (multi-line cells use
`SelectAllTextView`'s focus contract so Tab moves focus) and continues into
the document-wide chain at both edges — the old private per-block chain and
its tab-trap are gone.

**Impressions/Plan** — exactly two FIXED sections ("Impressions:", "Plan:");
no add/remove of sections. Each body is a consolidated rich-text box
(`ProseBlockEditor`, same surface as Prose): free prose, B/I/U, lists, list
continuation. ONE shared toolbar drives both boxes. Fresh sections seed ONE
blank bullet ready to type behind (deletable; Return-Return ends the list).
Labels are RICH (`LabeledSection.label: ProseContent`; bold "Impressions:" is
the seeded default): "Edit fields" ON = rich label box, OFF = read-only
preview with styling applied. A slot/token-bearing body falls back to
read-only (the conversion silently drops non-fixed runs). No carry-forward
switch surfaced (sections stay `.volatile`; duplicate clears them). The box
strokes only in the rendered PDF (`ImpressionsPlanContent.boxed`, default
true); editor gutter markers are edit-time chrome.

**Signature** — valediction picker (fixed closings + "Custom…" reveal; the
picker reads the stored value, so hand-typed closings reopen correctly) PLUS
a read-only profile preview: the stored signature ink on a white backing
(black-on-transparent PNG needs it), the resolved "Name, credentials" line
(empty pieces drop out, same rule as print), and an "Edit in Settings →
Practitioner Profile" link that switches tabs via `TabRouter` (an app-level
`ObservableObject` in ContentView.swift holding the `TabView` selection,
injected like the stores — any `#Preview` mounting a SignatureEditor must
inject `PractitionerProfileStore` AND `TabRouter`).
Name/credentials/ID/signature image still resolve from the profile at
render — the preview is display-only. `credentialsOverride` stays in the
model, unsurfaced until Settings.

**Patient** — data fields (last/first, DOB as three fields, AHC, phone,
address) + render-style segmented picker (Full box / Inline labels).
`.reducedBox` ("Box — no labels") is RETIRED from the picker — built, fixed,
then judged useless by the user; the model case and renderer path remain for
legacy JSON, and `normalizeRenderStyle` folds a legacy `.reducedBox` into
`.fullBox` when the editor opens (picker and print always agree). Don't
re-offer it. Rows render in `resolvedFieldOrder`. Per-field include toggles sit
INLINE beside their field group (one HStack: toggle, label at fixed 190pt
`labelColumnWidth`, field); data stays editable regardless of toggle —
excluded content just dims; include = per-REPORT print switch. An **"Edit
fields" toggle** (Findings convention) reveals per-row: a rename field
(custom label, empty = default; drives editor label AND print label — "AHC" →
"PHN"), up/down reorder arrows, and delete. Delete = per-TEMPLATE structure
(row gone from editor and print; typed data storage remains); an "Add field"
menu restores deleted standard fields. The five field KINDS are fixed — no
new kinds, no generic rows; identity stays typed for vault
search/tokens/blanking. Email intentionally omitted (rarely used).

**Recipient** — kind picker (Provider + fax / Freeform / None). The
provider+fax case prints ONE line: "To: " + name + "Fax: " + fax,
"Fax:" omitted entirely when the fax is empty, "To:" always
(`recipientProviderLine` — single source for measure AND draw; the old
two-line "TO DOCTOR NAME / Fax …" layout is gone). The editor is backed by
the **provider directory** (`ProviderStore.swift`: `Provider {id, name,
fax}` at `Application Support/EYEreport/providers.json`, backed-up store —
no PHI; saved on change like the profile; insertion order IS display order,
deliberately never auto-sorted so Settings rows can't jump mid-rename):
type-ahead suggestion rows appear under the name field while it holds
document focus (prefix matches rank first, max 4, exact current entry
excluded; tapping fills name + fax — or ↓/↑ from the NAME field highlight a
row and Return fills it, via `SelectAllTextField.onArrowKey`/`onReturnKey`,
opt-in handlers on the bridged field that return true=consumed /
false=normal text behavior; keys pass through untouched when no
suggestions show, and the highlight resets on typing), and below the fax field an
add-or-update affordance ("Add "X" to providers" / "Update fax for "X"",
hidden when the exact entry is already saved). Directory management lives on
**`ManageProvidersView`** (pushed from Settings → PROVIDERS → "Manage
providers…"; the main Settings page shows only the count — decluttering,
user request): editable name/fax rows binding straight into the store
(ID-BASED bindings — bridged fields + shrinkable collection),
trash-with-confirm (blank rows delete silently), "Add provider" appends an
empty row. Suggestions/save are buttons, not typed fields — nothing new in
FocusOrder or the deletion fingerprint.

**Closing** — picker (`sharingInCare`/`contactOffice`/`custom`) + grayed
preview echoing the exact rendered sentence (hand-duplicated from the
renderer — see Rendering pipeline). May be superseded by seeded-prose closings
later.

**Salutation** — the named salutation prints **"Dear \(name),"** — the NAME
carries its own title ("Dr. Smith", "Ms. Jones"; the model case is still
`dearDoctor` for JSON compatibility, but no "Dr." is added at render). It can
**mirror the recipient's name** (default ON):
`ReportEditorView` passes the FIRST provider+fax recipient's name down through
`BlockContentEditor.recipientName`; while mirroring, `SalutationEditor` keeps
the STORED name synced (onAppear + onChange) and shows a grayed "Dear Dr. X,"
preview instead of the field (no tab stop — FocusOrder skips it). The stored
copy is what renders and what templates save, so the renderer knows nothing
about mirroring. Toggle OFF keeps the current name for hand-editing; toggle
ON re-adopts the recipient's. No provider+fax recipient block → sync leaves
the stored name alone.

## Hard-won lessons (do not relearn these)

- **`List` doesn't mix with rich interactive rows**: `.onMove` hijacks inner
  `.onDrag` and a single tap dispatches to every button in a row. The block
  container stays ScrollView+VStack.
  **This bites inside `Form` too, and it MISDIAGNOSES as something else.**
  Every Button sharing a Form/List row needs an explicit
  `.buttonStyle(.borderless)` (or `.plain`) or the row is one tap target and
  ALL their actions run. Settings' backup row had two buttons with no style:
  tapping "Import backup…" also set `exportingBackup`, so the save panel
  (declared first) appeared and the importer only showed once it was
  dismissed. It presents exactly like a `.fileExporter`/`.fileImporter`
  collision — it is not. Two wrong fixes were built and reverted before the
  real cause was found: mounting one dialog at a time via a `switch` in a
  `.background` (SwiftUI reused one view identity across the branches, so
  BOTH buttons opened the importer and export became unreachable), then
  replacing both with imperative `UIDocumentPickerViewController`s (both
  closures still fired; the second `present` silently no-opped because one
  was already presenting — "both buttons save, no import"). That second
  failure is the tell: if a rewrite that removes the suspected mechanism
  entirely does NOT fix it, the mechanism was never the cause. Check
  `buttonStyle` on multi-button rows FIRST. `letterheadsSection` has had it
  right all along.
- **`ForEach($array)` element bindings crash "Index out of range" when the
  LAST element is deleted** (a UIKit-backed control updates once more against
  the stale index). Use **id-based bindings** (lookup by `id` with a safe
  fallback) for anything feeding a `UIViewRepresentable` whose collection can
  shrink — the established pattern throughout `FindingsEditor`. (Fixed
  collections — e.g. ImpressionsPlan's two sections — may use plain element
  bindings.)
- **Bridged fields re-claim first responder on rebuild** while `focusedKey`
  matches — they MUST clear the focus binding in
  `textFieldDidEndEditing`/`textViewDidEndEditing` (implemented in the bridge)
  or focus yanks back to a stale cell.
- **`.sheet(isPresented:)` captured a stale `@State` snapshot** — present
  sheets that must reflect live state via `.sheet(item:)` keyed on a tap-time
  `Identifiable` payload snapshot.
- **A concrete `@State` document gated by a Bool beats an optional working
  document.** Optional `@State ReportDocument?` fed to the editor crashes in
  `BindingOperations.ForceUnwrapping.get` when it goes nil (bridged fields
  fire one more `.update()` during teardown) — both with a hand-rolled
  force-unwrapping binding AND SwiftUI's failable `Binding($doc)`. "Start
  Over" flips `isEditing = false` ONLY; never nil the document under a mounted
  bridged editor.
- **Chaining `.font()` twice on the same `Text` is unreliable** — if a style
  helper bakes in a font, a follow-up `.font()` may be silently discarded. Set
  the font once, in one place.
- **UIKit drops custom NSAttributedString keys from typing attributes across a
  paragraph boundary** (paragraph style survives; custom keys don't). Never
  rely on typingAttributes to propagate a custom key — stamp real attributes
  after the fact (see the parked-pending mechanism).
- **Two `.fileImporter`s in one hierarchy collide — including across an
  ANCESTOR/descendant relationship, where the failure is completely silent.**
  The known sibling rule (each importer on its own button — Settings'
  signature vs. letterheads) is not the whole story: a `.fileImporter` placed
  on a view that WRAPS the chooser made the chooser's own "Import report PDF…"
  button do nothing at all — no sheet, no console output, no error. Put each
  importer on its own button, or in a mutually-exclusive branch, so only one
  is ever mounted. (Bit once, by the patient-import surface.)
- **A field backed by `@State` that is seeded in `init` goes stale when the
  MODEL is written from outside that editor.** The patient DOB's month field
  keeps a `monthDisplay` @State (digits while typing, "AUG" on blur), so an
  import landing in an open report updated DD and YYYY — which read the model
  directly — and left MM blank until the view was rebuilt. Both editors that
  do this now resync: `DateEditor.setToday` hand-syncs, `PatientEditor` uses
  `.onChange(of: content.dob?.month)` guarded by
  `MonthFormat.parse(monthDisplay) != model month` so it can't fire mid-typing
  and snap "8" to "AUG" before blur. **Any new editor that mirrors model state
  into @State needs the same resync** — otherwise it silently breaks the next
  time something writes the model behind it.
- **The Simulator is authoritative** for gesture/tap/drag verification; the
  SwiftUI Preview canvas is not.
- **Pinned bottom bars: ignore the keyboard safe area for the WHOLE subtree
  and restore scroll room from UIKit keyboard notifications.** Three
  approaches were tried; two failed on device: (1) a `.safeAreaInset(edge:
  .bottom)` bar rides the KEYBOARD safe area, and iPadOS sometimes reports a
  stale/phantom keyboard height that leaves the bar floating mid-screen
  until relaunch; (2) `ToolbarItem(placement: .bottomBar)` holding a custom
  multi-button HStack COLLAPSES into a single non-functional floating
  overflow button on the iPadOS-26 toolbar system; (2b) `.ignoresSafeArea(
  .keyboard)` on only the BAR child of a ZStack does nothing — the keyboard
  inset is applied ABOVE the ZStack, so the whole container lifts. The
  working pattern (NewReportView's `finishBar`): ZStack(alignment: .bottom)
  pinning the bar, `.ignoresSafeArea(.keyboard, edges: .bottom)` **on the
  NavigationStack itself** (the keyboard safe area is applied at the
  navigation container's hosting view — the same modifier on the ZStack
  inside the stack had NO effect; it remains there only as belt-and-braces),
  plus a `KeyboardOverlapObserver` (keyboardWillChangeFrame/Hide
  notifications, immune to the phantom heights) driving the editor's clear
  spacer inset (`max(finishBarHeight, keyboard.overlap)`) so fields stay
  scrollable above a real keyboard.
- **This target builds with `MemberImportVisibility`**: Combine-owned symbols
  (`ObservableObject` conformance, `Timer.publish(...).autoconnect()`) need an
  explicit `import Combine` in EACH file that uses them — SwiftUI's re-export
  does not satisfy it, and the CLI-side SourceKit diagnostics won't show the
  error (it surfaces only in the Xcode build). Bit twice: NewReportView's
  autosave timer, ContentView's TabRouter.
- **Types used off the main actor need explicit `nonisolated`.** The target
  builds with `-default-isolation MainActor`, so a plain `struct`/`enum`
  touched from a background context draws an isolation warning. `AppBackup`
  and `PatientDemographicsParser` both carry it.
- **CGPDFContext silently drops CUSTOM PDF Info keys, and writing
  `documentInfo` is not enough on device.** Metadata that must survive goes in
  a DOCUMENTED key (we use "Keywords"), and the renderer reads its own output
  back and re-serializes through PDFKit's `keywordsAttribute` if the payload
  didn't take. See App shell → Embedded report source.
- **SwiftUI `ShareLink` + `Transferable` hands share extensions a file
  PROMISE** that some EMR extensions cannot load (iDoc's import button stayed
  grey). A concrete tmp-file `URL` in a `UIActivityViewController` works — the
  same shape the Files app shares.
- **SwiftUI's `.keyboardType()` MODIFIER is a silent no-op on the bridged
  fields** — only the init parameter ever worked. This produced the "DOB hides
  the mic but the date block doesn't" mystery. See Editor conventions.
- **APIs above the iOS 17.6 floor need an `#available` guard.** Live example:
  `ToolbarSpacer` in NewReportView is iOS 26+.
- **There is no test target.** Pure-Swift logic (the IRIS parser, row
  matching, apply) is checked with a standalone `swiftc` harness — which must
  run under the target's own flags (`-swift-version 5 -default-isolation
  MainActor`) or it proves nothing about the real build. SwiftUI wiring can
  only be verified by the user on device.

## Deferred design decisions (not yet designed/built)

- **cc line** (multiple recipients) belongs on the **recipient** block — an
  optional cc (name + optional fax) when the recipient editor is revisited.
- **Closings as seeded prose**: under seeds-not-links, `ClosingEditor`'s
  picker may be superseded by seeded prose, which would also retire the
  hand-duplicated sentence strings.
- ~~Cross-block focus chain~~ — **BUILT and shipped**; moot as a deferred
  item. See Editor conventions / `FocusChain.swift`. Remaining gaps,
  deliberate: the slot/token per-paragraph prose fallback is outside the chain
  (Tab still inserts whitespace there), as is everything behind an "Edit
  fields" toggle.
- **Undo**: snapshot stack vs `UndoManager` — parked, to be scoped before any
  code.
- **Output-vs-placeholder**: edit-mode prompts ("TO DOCTOR NAME",
  "Dear Dr.,", unfilled slot "[opt / opt / opt]") currently render as content;
  the final output path must not print unfilled prompts — handle at a
  generate-for-output step. Related: To:/Re: baked into strings vs a
  structured label — promote if render-time bold gets fiddly.

Current tactical status, the deferred-debt list, the next step, the dated
session log, and the numbered **Standing decisions** table (things already
settled — do not re-ask or re-propose them) all live in `PROJECT_STATE.md`.
