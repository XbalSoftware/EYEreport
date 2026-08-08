//
//  SavedReportsView.swift
//  EYEreport
//

import SwiftUI

struct SavedReportsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Saved Reports", systemImage: "lock.doc", description: Text("Coming soon."))
                .navigationTitle("Saved Reports")
        }
    }
}

#Preview {
    SavedReportsView()
        .environmentObject(LetterheadStore())
}
