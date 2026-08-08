//
//  ContentView.swift
//  EYEreport
//
//  Created by Simon Reid on 2026-06-28.
//

import SwiftUI
import Combine

enum AppTab: Hashable {
    case newReport, templates, settings
}

/// App-level tab selection, injected like the stores so a deep child (e.g.
/// SignatureEditor's "edit profile" link) can switch tabs programmatically.
final class TabRouter: ObservableObject {
    @Published var selection: AppTab = .newReport
}

struct ContentView: View {
    @EnvironmentObject private var tabRouter: TabRouter

    var body: some View {
        // Letterheads live under Settings (rarely used); the Saved Reports
        // tab is SUPPRESSED while the vault is back-burnered — the stub view
        // still exists, it just isn't mounted.
        TabView(selection: $tabRouter.selection) {
            NewReportView()
                .tabItem { Label("New Report", systemImage: "square.and.pencil") }
                .tag(AppTab.newReport)
            TemplatesView()
                .tabItem { Label("Templates", systemImage: "doc.on.doc") }
                .tag(AppTab.templates)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LetterheadStore())
        .environmentObject(TemplateStore())
        .environmentObject(PractitionerProfileStore())
        .environmentObject(DraftStore())
        .environmentObject(TabRouter())
        .environmentObject(ProviderStore())
        .environmentObject(PatientImportInbox())
}
