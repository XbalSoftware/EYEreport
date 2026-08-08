# EYEreport 1.0 — App Store submission pack

Everything App Store Connect will ask you for, written out ready to paste.
Character limits are Apple's; the counts in brackets are what the text below
actually uses.

---

## App name  [9 / 30]

```
EYEreport
```

## Subtitle  [29 / 30]

```
Referral letters for eye care
```

## Category

- Primary: **Medical**
- Secondary: **Productivity**

## Price

Free. Worldwide availability.

---

## Promotional text  [161 / 170]

This one can be changed later WITHOUT submitting a new build — use it for
announcements.

```
Write referral letters, exam reports and vision reports on your own office letterhead, in minutes. Templates, patient import, and a signed PDF ready to fax or share.
```

---

## Description  [~2,050 / 4,000]

```
EYEreport is a letter composer for eye-care practitioners. It turns the correspondence you write every day — referral letters, examination reports, driver's-licence vision reports, screening letters — into a few minutes of typing, rendered onto your own office letterhead and ready to print, fax, or send to your EMR.

BUILT FROM YOUR OWN TEMPLATES
Every letter type is the same set of building blocks in a different order: recipient, patient details, findings, impressions and plan, closing, signature. Save any letter you have set up as a template, then start from it next time. Templates are yours to rename, reorder, and edit.

YOUR LETTERHEAD, YOUR SIGNATURE
Import your office letterhead as a PDF and mark its safe zone once. Every report is composed onto it, page after page, with page numbering where you put it. Sign once with your finger or Apple Pencil — or import a scanned signature — and it is stamped on every letter.

TYPE, DON'T TAP
Built for a clinician working at speed with an external keyboard. Tab moves through every field in the order they appear on the page. Findings grids take OD and OS values in a single pass. Dates are three quick numeric fields.

PATIENT DETAILS WITHOUT RETYPING
Share a patient record PDF from your EMR straight into EYEreport and the demographics — name, date of birth, health number, contact details — plus refraction, visual acuity, keratometry and intraocular pressure are read out and offered for review. Nothing is written into your report until you have checked every value and approved it.

REPORTS THAT REOPEN
Every PDF EYEreport produces carries its own source inside it. Open last year's exported letter back into the app and it returns exactly as it was, ready to edit for this visit.

PATIENT INFORMATION STAYS ON YOUR DEVICE
EYEreport has no account and no sign-in. It does not talk to any server run by the developer, collects no analytics, and sends nothing over the network. The report you are working on is saved encrypted on the device so it survives a restart. Patient PDFs shared in from your EMR are deleted as soon as they have been read. Where your finished PDF goes — printer, fax, EMR, AirDrop — is entirely your choice.

BACKUP AND RESTORE
Your templates, letterheads, signature, practitioner details, and provider directory export to a single file you can keep or move to another iPad. That file contains no patient information.

Designed for iPad, and runs on Mac.

EYEreport is a document-composition tool for licensed practitioners. It does not diagnose, and it makes no clinical decisions — the content of every report is written, reviewed, and approved by you.
```

## Keywords  [93 / 100]

Comma-separated, **no spaces after the commas**. Do not repeat the app name or
the category — Apple already indexes those.

```
optometry,ophthalmology,referral,letterhead,eyecare,clinic,letters,EMR,optometrist,PDF,report
```

---

## URLs

| Field | Value |
|---|---|
| Support URL | `https://xbalsoftware.github.io/EYEreport/` |
| Marketing URL | `https://xbalsoftware.github.io/EYEreport/` |
| Privacy Policy URL | `https://xbalsoftware.github.io/EYEreport/#privacy` |

---

## App Privacy ("nutrition label")

In App Store Connect → App Privacy, answer:

- **Do you or your third-party partners collect data from this app?** → **No**

That is the whole section. It is accurate: no account, no analytics, no
network calls to anything the developer runs. The bundled
`PrivacyInfo.xcprivacy` says the same thing in machine-readable form.

---

## Age rating

Answer **None** to every question, including the medical ones. The relevant
one reads roughly "Medical/Treatment Information" — that is aimed at apps
that give medical advice or drug information to a user. EYEreport formats
correspondence that a practitioner writes themselves. Result: **4+**.

---

## Export compliance

Already answered in code — `ITSAppUsesNonExemptEncryption = false` in
`Info.plist`. App Store Connect will stop asking per build.

Rationale, if you are ever asked: the only cryptography is Apple's own
CryptoKit AES.GCM, protecting the app's own draft file on the user's own
device. That is an exempt use.

---

## Notes for the App Review team

Paste into "Notes" on the version page. Medical-category apps get a closer
look; this answers the questions reviewers actually ask.

```
No sign-in is required — the app opens straight into a usable state, and a sample referral template is seeded on first launch. No demo account is needed.

What the app is: a document composer for licensed eye-care practitioners. The practitioner writes the letter; the app lays it out on their office letterhead and produces a PDF. It performs no diagnosis, gives no medical advice, offers no drug information, and makes no clinical recommendations of its own. All clinical content is typed and approved by the practitioner.

To try it: New Report → tap the seeded template → fill any fields → Preview → Print / Save to Files / Share. Letterhead is optional; with none set, reports render on a plain page.

Privacy: the app has no account system, contacts no server operated by the developer, and collects no analytics. Patient information is held only on the device. The active draft is stored AES.GCM-encrypted with a key held in the Keychain (device-only), excluded from backup.

Optional patient-detail import: the app declares PDF as a document type so a practitioner can share a patient record out of their EMR into the app. iOS delivers a copy into the app's Inbox; the app parses it, presents every value for review and correction, and deletes the source file immediately. Nothing is written into a report until the practitioner approves it. This is entirely user-initiated and the app never reaches out for data.

The screenshots use fabricated patient data. No real patient information appears anywhere in the app, the screenshots, or the metadata.
```

---

## Screenshots

Apple requires the **13-inch iPad** set. Accepted sizes: **2064 × 2752** or
**2048 × 2732** portrait (or those dimensions swapped, for landscape).
Minimum 1, maximum 10. Take them all in the same orientation.

Take them in the **iPad Pro 13-inch Simulator**, not on your clinic iPad —
partly for the exact pixel dimensions, and mostly so no real patient data
can leak into a public listing.

Suggested set, in order:

1. The block editor mid-letter — a filled referral with findings visible
2. Preview, showing the finished letter on a letterhead
3. The New Report chooser with several templates
4. The patient-detail review sheet after an EMR import
5. Settings — signature pad and practitioner profile

Use only self-evidently fake names — the ones the 1.0 screenshots used:
patient **PATIENT, Pretend** (DOB 1 JAN 1970), recipient **Dr. John Sample**,
practitioner **Dr. Your Name**. Never a real patient, a real provider, or a
real fax number. Do NOT invent a realistic-sounding name for this: a
plausible name cannot be distinguished from a real one later, and this file
is public.

---

## Build settings — already correct, for reference

| Setting | Value |
|---|---|
| Bundle ID | `Xbal.EYEreport` |
| Version (MARKETING_VERSION) | `1.0` |
| Build (CURRENT_PROJECT_VERSION) | `1` |
| Team | `KJ2353G82F` |
| Deployment target | iOS 17.6 |
| Device family | iPad only (`2`) |
| Mac | "Designed for iPad" enabled |

If a build is rejected and you upload a replacement, bump **build** to `2`
(version stays `1.0`). Every upload needs a unique build number.
