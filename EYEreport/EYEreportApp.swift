//
//  EYEreportApp.swift
//  EYEreport
//
//  Created by Simon Reid on 2026-06-28.
//

import SwiftUI

@main
struct EYEreportApp: App {
    @StateObject private var letterheadStore = LetterheadStore()
    @StateObject private var templateStore = TemplateStore()
    @StateObject private var profileStore = PractitionerProfileStore()
    @StateObject private var draftStore = DraftStore()
    @StateObject private var tabRouter = TabRouter()
    @StateObject private var providerStore = ProviderStore()
    /// Holds a PDF shared in from another app (the EMR's Share sheet) until
    /// New Report picks it up. In-memory only — see PatientImportInbox.
    @StateObject private var importInbox = PatientImportInbox()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(letterheadStore)
                .environmentObject(templateStore)
                .environmentObject(profileStore)
                .environmentObject(draftStore)
                .environmentObject(tabRouter)
                .environmentObject(providerStore)
                .environmentObject(importInbox)
                // A PDF opened/shared into EYEreport: either one of our own
                // exports (reopen it) or an IRIS patient PDF (parse it).
                .onOpenURL { url in
                    importInbox.receive(pdfAt: url)
                    tabRouter.selection = .newReport
                }
        }
    }
}
