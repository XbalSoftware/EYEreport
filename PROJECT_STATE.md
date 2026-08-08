# EYEreport — PROJECT STATE

Current status, standing decisions, lessons, and the dated session log. Read
AFTER `CLAUDE.md` (design, conventions and working method live there — this
file deliberately does not repeat them).

## NEXT SESSION — START HERE

**EYEreport 1.0 was submitted for review on 2026-08-04** with *Manually
release this version* selected. The review outcome is not recorded here —
check App Store Connect first. Nothing is pending in code.

- **Approved** → press Release when ready, then resume the roadmap: the vault
  (planning conversation first) or the output-vs-placeholder cleanup.
- **Rejected / question in Resolution Center** → draft the reply from
  `docs/app-store-submission.md`'s review notes rather than writing fresh. A
  code fix needs a bumped `CURRENT_PROJECT_VERSION`; version stays 1.0.
- **Metadata-only change** (description, keywords, screenshots) needs no new
  build.

Everything on the clinic-usability punch list is built and user-verified
except item 8 (layout harmonization), which is blocked on concrete examples
from the user. Do not re-verify shipped work — see the session log.

## What's BUILT and user-verified

- **Data model + renderer**: twelve block types; letterhead compositing;
  full pagination (findings row-splitting with repeated headers, prose
  paragraph and mid-text splitting); page-of-N; data-driven findings
  affordances and content-driven column widths / row heights;
  column-aligned list rendering; rich Impressions/Plan labels; boxed prose;
  single-source patient layout with a full-width spanning address row.
  Output typeface is Helvetica.
- **Block editor**: all twelve per-type editors; arrange mode (drag-reorder
  by header, "Add block here" in every gap, trash); "+" add-block menu;
  deletion warnings via `ModifiedTextGuard`; document-wide tab chain
  (`FocusChain.swift`).
- **Rich text in Prose**: consolidated one-box editor with gutter markers and
  list continuation, B/I/U/•/№ toolbar, ⌘B/⌘I/⌘U key commands, spellcheck on
  with autocorrect off. Slot/token blocks use the per-paragraph fallback.
- **App shell**: three tabs (New Report · Templates · Settings);
  `TemplateStore` seeded on first launch with `standardReferral` only;
  save-as-template via `asTemplate`; encrypted single-draft autosave.
- **Preview & export**: sticky app-wide letterhead selection, 9–13pt text-size
  menu, Print / Save to Files / Share, embedded-source PDFs that reopen as an
  exact copy.
- **Patient-detail import from IRIS**: parse → mandatory review sheet → apply,
  including the cc/sc acuity split, the fused "Refraction / VA" row, graded
  row matching, and inbox intake from the EMR's Share sheet.
- **Settings**: practitioner profile with draw-or-import signature, provider
  directory (`ManageProvidersView`), inline letterhead management with
  safe-zone editor, About page, whole-app backup/restore, reset to defaults.

## Placeholders / NOT built

- **Saved Reports (vault)**: tab not mounted — vault back-burnered;
  `SavedReportsView.swift` stub remains.
- **No test target.** Pure-Swift logic is checked with a standalone `swiftc`
  harness (see Lessons learned); SwiftUI wiring is verified by the user on
  device.

## Deferred debt (handle when it bites)

- `impressionsPlan` and Boxed Prose do NOT split across pages — they move
  whole and overflow. Keep the two draw/count exclusion gates in step.
- **Output-vs-placeholder**: unfilled prompts ("To: DOCTOR NAME", "Dear Dr.,",
  unfilled slots) still print. Needs a generate-for-output step. Shipped in
  1.0 as a known cosmetic issue; one-tap Print makes it more visible.
- Tab still inserts whitespace in the slot/token per-paragraph prose fallback
  (`RichParagraphEditor`) — outside the chain by design.
- `ClosingEditor`'s closing sentences are hand-duplicated from the renderer.
- Undo — parked design fork (snapshot stack vs `UndoManager`).
- cc line on recipient — deferred design.
- Renderer polish batch: list indent is DONE; remaining spacing tweaks stay
  batched until the app is closer to fully assembled — do not one-off them.
- Cosmetic: Findings reorder arrows not visibly greyed at first/last row;
  Impressions/Plan body placeholder overlaps the seeded gutter bullet;
  letterhead polish (rename, thumbnails, multi-page letterhead).
- The chooser's search list no longer shrinks above the keyboard — accepted
  cost of the pinned-bottom-bar fix.

## File map (orientation, not exhaustive)

- Model / rendering: `ReportModel.swift`, `ReportRenderer.swift`,
  `Presets.swift` (seed source only), `EmbeddedReport.swift`.
- Shell: `EYEreportApp.swift`, `ContentView.swift` (+ `TabRouter`),
  `NewReportView.swift`, `PreviewView.swift`, `TemplatesView.swift`,
  `TemplateStore.swift`, `DraftStore.swift`, `SettingsView.swift`,
  `AboutView.swift`, `AppBackup.swift`, `ManageProvidersView.swift`,
  `PractitionerProfileStore.swift`, `ProviderStore.swift`,
  `SignaturePad.swift`, `SavedReportsView.swift` (stub).
- Letterheads: `Letterhead.swift`, `LetterheadStore.swift`,
  `SafeZoneEditorView.swift` (list/import UI is inline in `SettingsView`).
- Patient import: `PatientDemographics.swift`,
  `PatientDemographicsParser.swift`, `PatientImport.swift`,
  `PatientImportInbox.swift`, `DemographicsReviewSheet.swift`.
- Block editor: `ReportEditorView.swift` (+ `NewBlockKind`),
  `BlockContentEditor.swift`, one file per editor (Subject, Title, Closing,
  Salutation, Recipient, Date, Patient, Prose, Findings, ImpressionsPlan,
  Signature, Spacer), `EditorStyle.swift`, `SelectAllTextField.swift`,
  `FocusChain.swift`, `ModifiedTextGuard.swift`.
- Prose rich text: `ProseBlockEditor.swift`, `RichParagraphEditor.swift`,
  `ProseFormatting.swift`.
- Repo (not bundled): `docs/index.html` (user manual + privacy policy, served
  by GitHub Pages), `docs/app-store-submission.md`.

## Clinic-usability punch list (agreed 2026-07-09, in order)

1. Draft autosave — done.
2. Editor toolbar reorg — done.
3. Small-fix batch — done.
4. Signature shown in the New Report signature block — done.
5. Template search filter — done.
6. Recipient/provider arc — done.
7. Preview export buttons — done.
8. **Screen-layout harmonization sweep — OPEN.** Blocked: needs concrete
   examples from the user of what looks wrong.

Deliberately skipped: driver-template cataract-slot sentence (the real gap is
that the per-paragraph fallback editor has no delete-paragraph control);
bottom-of-screen overflow past the Preview button (user reports it fixed —
reopen if it recurs).

## Roadmap (after the punch list)

1. **Vault** — CryptoKit AES.GCM sealing; Keychain key behind `.userPresence`;
   auth gates KEY RETRIEVAL; directory excluded from backup; privacy overlay
   on background; in-memory metadata search (lastName+firstName+dob); no
   patient registry. Touches the two-store split and likely `ReportModel`
   adjacency — warrants a planning conversation before code.
   (`DraftStore.swift` is a working miniature of the crypto pattern.)
   A scope was drafted in conversation but NOT ratified: four decisions
   (relock policy, save-button placement, device-only tradeoff, where
   vault-spawned edits happen) were never answered. Re-raise them if it
   resumes.
2. Then: output-vs-placeholder cleanup; impressionsPlan/boxed-prose splitting
   when it bites; renderer polish batch; undo.

## App Store submission — 1.0

Version **1.0**, build **1**, bundle `Xbal.EYEreport`, team `KJ2353G82F`.
Submitted 2026-08-04 with **Manually release this version**, so it does not go
live automatically when review passes.

Settings used, for the next version: category **Medical** (secondary
Productivity), **free**, all territories, support + marketing URL =
`https://xbalsoftware.github.io/EYEreport/`, privacy policy = that URL's
`#privacy` anchor, contact = xbalsoftware@gmail.com, copyright
"2026 XBAL Software", age rating 4+, App Privacy = **no data collected**.
Six landscape 13-inch iPad screenshots with fabricated data only.

All submission copy — name, subtitle, description, keywords, promotional text,
review notes — lives in **`docs/app-store-submission.md`**. Reuse it; only
"What's New" is added per version.

Two blockers closed in code: `EYEreport/PrivacyInfo.xcprivacy` (no tracking,
no data collected, UserDefaults declared with reason CA92.1 — without it every
upload draws an ITMS-91053 warning) and `Info.plist` →
`ITSAppUsesNonExemptEncryption = false` (the only crypto is CryptoKit AES.GCM
on the local draft, an exempt use — skips the per-build questionnaire).

**Every future upload needs a unique build number** — bump
`CURRENT_PROJECT_VERSION`, leave `MARKETING_VERSION` at 1.0 for a
resubmission of the same version.

## Standing decisions — do not re-ask, do not re-propose

Numbers are permanent anchors: never renumber, never reuse, never delete a
row. A decision that gets overtaken is marked "superseded by #N" in place.

| # | Decision | Why |
|---|---|---|
| D1 | A template IS a `ReportDocument` with `templateName != nil` — never a separate Template type. | One structure everywhere; save-as-template is just `asTemplate`. |
| D2 | Presets are seeds, not live links. Editing a copy never touches the source. | Matches the EYEbrary assembly model the user already thinks in. |
| D3 | Only `standardReferral` is seeded on first launch. The driver's-licence letter is an ordinary user template. | The user maintains it themselves; seeding it made it un-deletable-feeling. |
| D4 | Model changes are additive / zero-migration (nil-default optionals, custom decoders). | Old saved JSON must keep decoding without a migration step. |
| D5 | Reports print in **Helvetica**, built in one place (`RenderContext.attrs`). | The system font read as "modern app", not "letter". A Preview font menu was floated and deferred. |
| D6 | Signature print size is **global** (≤29 × 143pt). A per-block size slider was built and rejected. | One correct size beats a control nobody wants to set per letter. |
| D7 | Patient render style `.reducedBox` is **retired from the picker** (superseded by D7a). | Built, fixed, then judged useless. |
| D7a | The `.reducedBox` model case and renderer path stay for legacy JSON; `normalizeRenderStyle` folds it to `.fullBox` on editor open. | Picker and print must always agree; old documents must still open. |
| D8 | The five patient field KINDS are fixed — no new kinds, no generic rows. Deleting a field is per-template structure; its typed storage remains. | Identity stays typed for vault search, tokens, and `blanked()`. Email omitted as rarely used. |
| D9 | Impressions/Plan has exactly two fixed sections. No add/remove. | The box is a known clinical shape, not a freeform container. |
| D10 | "Import report PDF…" restores an **exact** copy (fresh document id only), not `duplicatedForNewVisit`. | Volatile-clearing read as "blank findings"; the user edits by hand instead. |
| D11 | Exporting does NOT clear the draft. | Export is not "done with this report". |
| D12 | Every field uses the **default keyboard** — no `keyboardType` overrides. | External-keyboard app; specialised keyboards made the hardware assistant strip (mic icon) inconsistent. |
| D13 | Autocorrect **off**, spellcheck **on**, in prose fields. | Autocorrect mangles clinical terms; a red squiggle does not. |
| D14 | Patient-detail import always passes through a mandatory review sheet. Non-negotiable. | The parser is tuned to one EMR's layout; nothing reaches the document unreviewed. |
| D15 | Row matching for imported findings is loose keyword matching, GRADED best-match-wins. | Findings rows carry only a free-text label, so type-based matching (Form Filler's approach) cannot port. |
| D16 | A bare "VA" row means **corrected**. Uncorrected VA never falls back to it. | Guessing prints the wrong acuity — worse than leaving it for the clinician. |
| D17 | No keratometry row is added to `Presets.standardFindings`. | The user adds it to templates that need it. |
| D18 | The exam date is NOT parsed from an import; the date block stays today. | Letters are dated when written, not when examined. |
| D19 | Patient details shared in at the chooser are HELD until a template is picked. | The template choice stays the clinician's. |
| D20 | No patient registry, ever. Identity derives from reports. | A registry is the surface this app deliberately does not have. |
| D21 | The **vault is back-burnered**; clinic usability comes first. | User's call; the draft store covers quit-safety meanwhile. |
| D22 | Template reorder is long-press drag with **no** `EditButton` / edit mode; rename via the pencil button only, rest of the row inert. | The user rejected edit mode as redundant. |
| D23 | Letterhead choice is app-wide sticky, not per-document. `ReportDocument.letterheadID` stays unused. | One office, one letterhead, many letters. |
| D24 | Export/Print/Share all use one filename source: "LAST, First yyyy-MM-dd", surname upper-cased at the point of use. | A hand-typed name files identically to an imported one. |
| D25 | The `#if DEBUG` `ModelProof` block was deleted (sanctioned cleanup — done 2026-07-26 or earlier). | Superseded by real use; no longer earning its space. |

## Lessons learned

Platform and build traps, hoisted out of the log. The canonical write-ups for
the SwiftUI/UIKit ones live in **CLAUDE.md → Hard-won lessons**; the lines
below are the index, plus the ones that only exist here.

**Build & toolchain**

- **The command-line build is not authoritative.** This machine has no iOS SDK
  on the CLI path, so SourceKit "cannot find in scope" / "No such module" are
  false positives. Xcode is the source of truth; the Simulator (not the
  Preview canvas) is authoritative for gestures and taps.
- **Pure-Swift logic can be tested without a test target** with a standalone
  `swiftc` harness — but it must run under the target's own flags
  (`-swift-version 5 -default-isolation MainActor`) or it proves nothing about
  the real build. This is how the IRIS parser and row-matching were checked.
- **`import Combine` is required in every file that touches Combine symbols**
  (`ObservableObject` conformance, `Timer.publish(...).autoconnect()`) —
  `MemberImportVisibility` means SwiftUI's re-export does not satisfy it, and
  the error surfaces only in the Xcode build. Bit twice.
- **Types used off the main actor need explicit `nonisolated`** under
  `-default-isolation MainActor` — `AppBackup` and `PatientDemographicsParser`
  both carry it. Symptom is an isolation warning, not an error.
- **APIs above the iOS 17.6 floor need `#available` guards.** Live example:
  `ToolbarSpacer` in `NewReportView` is iOS-26 only.

**SwiftUI / UIKit**

- Two `.fileImporter`s in one hierarchy collide — including across an
  **ancestor/descendant** relationship, where the failure is completely
  silent. One importer per button, or mutually exclusive branches.
- Every Button sharing a `Form`/`List` row needs an explicit
  `.buttonStyle(.borderless)` or the row is one tap target and **all** their
  actions run. This misdiagnoses as a file-dialog collision. Check
  `buttonStyle` FIRST. Corollary: if a rewrite that removes the suspected
  mechanism entirely does not fix the bug, the mechanism was never the cause.
- `ForEach($array)` element bindings crash "Index out of range" when the last
  element is deleted. Use id-based bindings for anything feeding a
  `UIViewRepresentable` whose collection can shrink.
- `.sheet(isPresented:)` captures a stale `@State` snapshot — use
  `.sheet(item:)` keyed on a tap-time payload.
- A concrete `@State` document gated by a Bool beats an optional working
  document; an optional going nil under a mounted bridged editor crashes.
- **`@State` seeded in `init` goes stale when the model is written from
  outside that editor.** Any editor mirroring model state into `@State` needs
  a guarded `.onChange` resync.
- **SwiftUI's `.keyboardType()` modifier is a silent no-op on bridged
  (`UIViewRepresentable`) fields** — only the init parameter ever worked. This
  produced the "DOB hides the mic but the date block doesn't" mystery.
- The keyboard safe area is applied at the **NavigationStack's hosting view**,
  so `.ignoresSafeArea(.keyboard)` must go on the stack, not on an inner
  ZStack or the bar child. Three earlier approaches failed on device;
  `.safeAreaInset` bars ride a stale/phantom keyboard height, and a
  `.bottomBar` toolbar item collapses to a floating overflow button on
  iPadOS 26.
- Chaining `.font()` twice on the same `Text` is unreliable — set it once.
- UIKit drops custom `NSAttributedString` keys from typing attributes across a
  paragraph boundary. Never rely on typingAttributes to carry one; stamp real
  attributes after the fact.
- `List` does not mix with rich interactive rows (`.onMove` hijacks inner
  `.onDrag`; one tap dispatches to every button). The block container stays
  ScrollView+VStack.
- A drag payload must use a **private `UTType`**, not plain text — UITextViews
  claim a text payload and paste it into prose. Consume the payload at drop or
  the session lingers ~20 s.

**PDFKit / CoreGraphics**

- **CGPDFContext silently drops custom PDF Info keys.** Metadata you need to
  survive must go in a *documented* key — EYEreport uses "Keywords", which
  round-trips 120 KB intact.
- **Writing `documentInfo` is not enough on device.** A device build produced
  a PDF with no Keywords entry despite the write, so `renderToPDFData` ends
  with `ensuringEmbeddedSource`: read the rendered bytes back and, if the
  payload is missing, re-serialize once through PDFKit's
  `keywordsAttribute`. Keep both writers pointed at the same key.
- **SwiftUI `ShareLink` + `Transferable` hands share extensions a file
  promise** that some EMR extensions cannot load (iDoc's import button stayed
  grey). A concrete tmp-file `URL` in a `UIActivityViewController` works —
  the same shape the Files app shares.
- Stored safe zones are normalized 0–1 in **UIKit top-left space**. The only
  correct CTM flip is drawing the letterhead PDF page itself. An earlier
  double-flip bug came from treating stored values as PDF-space.
- `UIPrintInteractionController` needs an **anchor rect** on iPad.

**Renderer discipline**

- Measure, split, draw and `countPages` must read the same single source for
  every geometry. Change how something draws and you change its measurement in
  the same place, or pagination breaks at the wrong row and page-of-N
  disagrees with reality.

## Session log

Newest first. Design rationale lives in CLAUDE.md; this is what happened when.

### 2026-08-08
- Replaced a real-shaped Alberta PHN in `PatientDemographicsParser.swift`'s
  comments with a `999 999 999` placeholder. **The original is still in the
  pushed history and stays reachable by SHA on GitHub until garbage
  collection** — see the note under the placeholder convention in CLAUDE.md.
- Added `CLAUDE.md` and `PROJECT_STATE.md` as Xcode file references so they
  are visible in the project navigator (not target members — not bundled).

### 2026-08-04 — IRIS import, submission blockers, 1.0 submitted
- **Patient-detail import from IRIS** built end to end and user-verified:
  parser, `ExamFinding` row matching, mandatory review sheet, inbox intake
  from the EMR's Share sheet, `.onOpenURL` routing. No model change — it all
  hangs off an extension in `PatientImport.swift`.
- **cc/sc acuity split + fused "Refraction / VA" rows.** Row matching became
  graded (best-match-wins) so an explicit "VA (cc)" beats a bare "VA"
  wherever each sits. Uncorrected VA needed a different shape entirely:
  under "Entrance Skills → Visual Acuities" the viewing condition is labelled
  per EYE, so a one-eyed result is normal and the both-eyes requirement in
  `odosValues` rejected it — rewritten as a marker-and-collect scan with
  three guards against stray markers.
- IOP search window widened 8 → 12 lines: section preambles vary (a page
  footer can sit between the header and its readings). The `requiring:
  "mmHg"` filter means a wider window can only find a value a tight one
  would have missed, never a wrong one.
- Tonometry rows now receive IOP — the stem is "tonomet", not "tonometr",
  which misses "tonometER"; bare "NCT" also accepted.
- Imported surnames arrive UPPER-CASED so the editor shows what will print.
- Export filename is now "LAST, First yyyy-MM-dd.pdf", upper-casing at the
  point of use so typed names file like imported ones.
- **Two import wiring bugs**, both fixed and verified: an imported DOB left
  the MM field blank (stale `@State`), and "Import report PDF…" silently
  stopped working (an ancestor `.fileImporter` swallowed it). Both are now
  Lessons.
- **Backup import opened the export save panel first** — the two backup
  buttons shared a `Form` row with no `.buttonStyle`, so a tap ran both
  actions. Two wrong fixes were built and reverted before the real cause was
  found.
- A `ToolbarSpacer` (iOS-26 guarded) unfused Start Over from Patient details.
- Submission blockers closed: `PrivacyInfo.xcprivacy` and
  `ITSAppUsesNonExemptEncryption`.
- **Repo-wide personal-data scan.** `Presets.swift` and the asset catalogue
  are clean. Example values in `PatientDemographicsParser.swift`,
  `docs/index.html` and `SalutationEditor.swift` were reviewed and
  deliberately kept — don't re-flag them.
- **1.0 submitted for review.**

### 2026-07-26
- **Blank Spacer block added** — a twelfth block type (`SpacerContent { lines:
  Int }`, `SpacerEditor.swift`, "Blank space" in the "+" menu). Renders as N
  blank body lines. No text, so it is deliberately outside the tab chain and
  the deletion-warning fingerprint.

### 2026-07-21
- **User manual moved into the repo as `docs/index.html`** and merged with the
  privacy policy (`#privacy` anchor). GitHub Pages serves it from `main`
  `/docs`. `AboutLinks` in `AboutView.swift` now points at the live site —
  the separate `userManual` constant is gone; one "Website including Quick
  Start Guide + full user manual" link covers it.
- ⌘B / ⌘I / ⌘U key commands added to both prose editors.
- Spellcheck enabled in prose fields (autocorrect stays off).

### 2026-07-14
- Settings appearance tweak.
- `nonisolated` on `AppBackup` cleared a main-actor isolation warning.

### 2026-07-13
- **Embedded report source**: every rendered PDF carries its `ReportDocument`
  JSON in the "Keywords" Info key, and the chooser gained "Import report
  PDF…". Took three attempts — a custom Info key was silently dropped, then a
  device build produced no Keywords entry at all despite the `documentInfo`
  write, so the renderer now verifies the bytes and re-serializes through
  PDFKit if needed. Still worth testing once: a PDF that went through iDoc and
  back, in case the EMR strips Info metadata.
- **Share-to-EMR fix**: `UIActivityViewController` with a concrete tmp-file URL
  replaced `ShareLink` + `Transferable`.
- **Whole-app backup/restore** (`AppBackup.swift`): one JSON of templates,
  profile + signature, letterheads + safe zones, providers, sticky letterhead
  id. No PHI — the draft is excluded by design. Import wholesale-replaces.
- **Settings declutter + About page**: PROVIDERS reduced to a count +
  "Manage providers…" pushing the new `ManageProvidersView`; new ABOUT section
  pushing `AboutView.swift`.
- Provider suggestions gained keyboard navigation (↓/↑ highlight, Return
  fills) via opt-in `onArrowKey`/`onReturnKey` on the bridged fields.
- **"Today" button in `DateEditor`**, visible only while the stored date isn't
  already today — its presence is the stale-date flag. Companion to the
  exact-copy PDF import, which restores the original date.
- Removed the developer's identifying information from default code.

### 2026-07-10
- **Helvetica** replaces the system font for rendered reports.
- **Sticky letterhead selection** app-wide (`LetterheadStore.activeSelection`,
  UserDefaults), with radio buttons in Settings. "None (plain)" is sticky too.
- `.reducedBox` retired from the patient picker.
- **Bottom-bar float fix, take 4** — `.ignoresSafeArea(.keyboard)` on the
  NavigationStack itself. Takes 1–3 all failed on device; a `.bar`-material
  Rectangle extending to the physical bottom edge finished the polish.
- Preview gained **Print / Save to Files / Share** in place of Share alone.

### 2026-07-09
- **Draft autosave** (`DraftStore.swift`) — the single active report survives
  a quit, AES.GCM-sealed with a Keychain key.
- **Provider directory** (`ProviderStore.swift`) + recipient type-ahead;
  recipient renders as one line, "To: … Fax: …", labels unbolded.
- Template search filter in the New Report chooser.
- Signature preview inside the signature block, with a `TabRouter` link to
  Settings.
- ALL-CAPS months in both date fields; Impressions/Plan label size hand-tuned
  by the user (keep their choice).
- Editor toolbar reorg: Save as Template beside Preview in the bottom bar,
  "…" menu deleted, (+) grouped with Arrange.

### 2026-07-08
- Preview **text-size menu** (9–13pt) writing back to `bodyFontSize`; all
  render fonts derive from `RenderContext.bodySize`.
- Signature import from .png/.jpg, remove-confirmation, and print size cut to
  65% with an adaptive gap (36pt with an image, 50pt without).
- Letterheads moved inline into Settings; Saved Reports tab suppressed;
  `LetterheadsView.swift` deleted.
- Template reorder by drag.
- Deletion-warning false positives fixed for empty Impressions/Plan,
  Signature and Findings blocks.
- Findings column widths became content-driven.

### 2026-07-07
- Template export/import; share sheet from Preview.
- `ModifiedTextGuard` — deletion warnings keyed on a data-entry-only text
  fingerprint.
- Signature module; salutation mirrors the recipient by default.
- Patient field-name editing; document-wide tab chain fixed.
- Arrange mode: drag-reorder and add-block-here.

### 2026-07-06
- Impressions/Plan reworked as consolidated rich prose with a seeded bullet.
- Boxed Prose block.
- Typed bullets and numbering in prose; renderer hanging indents.

### 2026-07-05
- `ProseBlockEditor` — one `UITextView` editing a whole block, with the parked
  `pendingListValue` mechanism. **Do not "clean this up"**: every rule in it
  closes a specific verified bug.

### 2026-07-04
- Live preview pane reflecting the active editor; model extended for rich
  text; templates pre-seeded.

### 2026-07-03
- Model cleanup; standard field-size convention; phone/fax auto-format on
  blur; findings editor polish.

### 2026-07-02
- All block editors finished; block-assembly layer (reorder, delete);
  Impressions/Plan editor.

### 2026-07-01
- Findings editor: add and reorder rows.

### 2026-06-29
- Letterhead safe-zone editor (handle-based) and `LetterheadStore`.
- Pagination for prose and findings; page-of-N with a movable position.

### 2026-06-28
- Project created; `ReportModel`, `ReportRenderer`, `Presets`.
