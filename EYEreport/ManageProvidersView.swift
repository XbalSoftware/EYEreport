//
//  ManageProvidersView.swift
//  EYEreport
//
//  The provider directory's management screen, pushed from Settings →
//  PROVIDERS → "Manage providers…" (the list moved OFF the main Settings
//  page to keep it uncluttered — Settings shows only the count). Rows bind
//  straight into ProviderStore (saved on change, keyboard-first); bindings
//  are ID-BASED (bridged fields + shrinkable collection — the documented
//  last-element-deleted crash).
//

import SwiftUI

struct ManageProvidersView: View {
    @EnvironmentObject private var providerStore: ProviderStore
    @State private var providerPendingDeletion: Provider?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The doctors you refer to regularly. The recipient block suggests these as you type, and can save new ones here itself.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if providerStore.providers.isEmpty {
                    Text("No saved providers yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(providerStore.providers) { provider in
                    HStack(spacing: 6) {
                        SelectAllTextField(placeholder: "Name (e.g. Dr. Smith)",
                                           text: providerField(provider.id, \.name))
                            .frame(height: standardFieldHeight)
                        SelectAllTextField(placeholder: "Fax number",
                                           text: providerField(provider.id, \.fax),
                                           onEndEditing: { snapProviderFax(provider.id) })
                            .frame(width: 170, height: standardFieldHeight)
                        Button(role: .destructive) {
                            // An entirely blank row has nothing to protect.
                            if provider.name.isEmpty && provider.fax.isEmpty {
                                providerStore.delete(id: provider.id)
                            } else {
                                providerPendingDeletion = provider
                            }
                        } label: {
                            Image(systemName: "trash")
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button {
                    providerStore.add(Provider())
                } label: {
                    Label("Add provider", systemImage: "plus")
                }
            }
            .padding()
        }
        .navigationTitle("Providers")
        .alert("Delete this provider?",
               isPresented: Binding(
                   get: { providerPendingDeletion != nil },
                   set: { if !$0 { providerPendingDeletion = nil } }),
               presenting: providerPendingDeletion) { provider in
            Button("Delete", role: .destructive) { providerStore.delete(id: provider.id) }
            Button("Cancel", role: .cancel) { }
        } message: { provider in
            Text("\"\(provider.name)\" will be removed from the provider directory.")
        }
    }

    /// ID-based lookup binding into one string field of one provider row.
    private func providerField(_ id: UUID,
                               _ keyPath: WritableKeyPath<Provider, String>) -> Binding<String> {
        Binding(
            get: {
                providerStore.providers.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = providerStore.providers.firstIndex(where: { $0.id == id })
                else { return }
                providerStore.providers[index][keyPath: keyPath] = newValue
            }
        )
    }

    /// Same digit-snap as the recipient editor: format only a bare 10-digit
    /// number, on blur, never mid-typing.
    private func snapProviderFax(_ id: UUID) {
        guard let index = providerStore.providers.firstIndex(where: { $0.id == id }) else { return }
        let fax = providerStore.providers[index].fax
        guard fax.count == 10, fax.allSatisfy(\.isNumber) else { return }
        let a = fax.prefix(3)
        let b = fax.dropFirst(3).prefix(3)
        let c = fax.dropFirst(6)
        providerStore.providers[index].fax = "(\(a)) \(b)-\(c)"
    }
}

#Preview {
    NavigationStack {
        ManageProvidersView()
            .environmentObject(ProviderStore())
    }
}
