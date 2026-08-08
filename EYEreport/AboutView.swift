//
//  AboutView.swift
//  EYEreport
//
//  About page, pushed from Settings → ABOUT. Description, app info,
//  a brief plain-language EULA, privacy-policy link, and support links.
//
//  PLACEHOLDERS: the website / user-manual / privacy-policy URLs are nil
//  until the user supplies real ones — nil renders as a grayed
//  "coming soon" row, never a dead link. Set them in `AboutLinks` below.
//

import SwiftUI

/// External destinations — fill these in as they go live.
private enum AboutLinks {
    static let website = URL(string: "https://xbalsoftware.github.io/EYEreport/")
    static let privacyPolicy = URL(string: "https://xbalsoftware.github.io/EYEreport/#privacy")
    static let supportEmail = "xbalsoftware@gmail.com"
}

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("EYEreport is a clinical report composer for eye-care correspondence: referral letters, examination reports, driver's-licence vision reports, and screening letters. Reports are assembled from reusable templates, rendered onto your office letterhead, and printed, faxed, or shared to your EMR as PDF. Patient information stays on this device — the app sends nothing over the network.")

                Divider()

                Text("APP INFORMATION")
                    .blockTitleStyle()

                LabeledContent("Version", value: version)
                LabeledContent("Developer", value: "XBAL Software")

                Divider()

                Text("LEGAL")
                    .blockTitleStyle()

                Text("""
                EYEreport is provided "as is", without warranty of any kind. It is a document-composition tool: the clinical content of every report is entered, reviewed, and approved by you, and responsibility for the accuracy and appropriateness of issued reports rests with the issuing practitioner. By using the app you agree to use it only for lawful professional purposes and not to redistribute, resell, or reverse-engineer it. To the maximum extent permitted by law, the developer is not liable for any damages arising from the use of the app or of documents produced with it.
                """)
                .font(.subheadline)
                .foregroundStyle(.secondary)

                linkRow("Privacy Policy", url: AboutLinks.privacyPolicy)

                Divider()

                Text("SUPPORT")
                    .blockTitleStyle()

                linkRow("Website including Quick Start Guide + full user manual", url: AboutLinks.website)
                if let mail = URL(string: "mailto:\(AboutLinks.supportEmail)") {
                    Link(destination: mail) {
                        Label(AboutLinks.supportEmail, systemImage: "envelope")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("About EYEreport")
    }

    /// A live Link when the URL exists; a grayed "coming soon" row until
    /// then — never a dead link.
    @ViewBuilder
    private func linkRow(_ title: String, url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                Label(title, systemImage: "link")
            }
        } else {
            Label("\(title) — coming soon", systemImage: "link")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
