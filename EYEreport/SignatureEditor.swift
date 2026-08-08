import SwiftUI
import UIKit

struct SignatureEditor: View {
    @Binding var content: SignatureContent
    var focus: BlockFocusChain? = nil
    @EnvironmentObject private var profileStore: PractitionerProfileStore
    @EnvironmentObject private var tabRouter: TabRouter

    /// Internal (not private): FocusOrder reads this to derive whether the
    /// custom-valediction field is on screen for a signature block.
    static let fixedChoices = ["Regards,", "Sincerely,", "Yours truly,"]

    private enum Kind: Hashable {
        case fixed(String)
        case custom
    }

    private var kind: Binding<Kind> {
        Binding(
            get: {
                Self.fixedChoices.contains(content.valediction) ? .fixed(content.valediction) : .custom
            },
            set: { chosen in
                switch chosen {
                case .fixed(let text): content.valediction = text
                case .custom: content.valediction = ""
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Valediction", selection: kind) {
                ForEach(Self.fixedChoices, id: \.self) { text in
                    Text(text).tag(Kind.fixed(text))
                }
                Text("Custom…").tag(Kind.custom)
            }
            .pickerStyle(.menu)

            if case .custom = kind.wrappedValue {
                SelectAllTextField(placeholder: "Custom valediction", text: $content.valediction,
                                   focusKey: focus.key(FocusFields.signatureValediction),
                                   focusBinding: focus.binding,
                                   onTab: focus.tab(FocusFields.signatureValediction))
                    .frame(height: standardFieldHeight)
            }

            // Live preview of what the profile will stamp under the
            // valediction — read-only here; edited in Settings.
            Text("From the practitioner profile:")
                .fieldLabelStyle()

            if let data = profileStore.profile.signatureImageData,
               let image = UIImage(data: data) {
                // White backing: the stored ink is black on transparent,
                // exactly as it will stamp onto the letterhead paper.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 70, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
            } else {
                Text("No signature on file — this report will print without one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !identityLine.isEmpty {
                Text(identityLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                tabRouter.selection = .settings
            } label: {
                Label("Edit in Settings → Practitioner Profile", systemImage: "gearshape")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
        }
    }

    /// "Name, credentials" as the renderer resolves them; empty pieces drop
    /// out rather than dangling separators (same rule as print).
    private var identityLine: String {
        let p = profileStore.profile
        return [p.name, p.credentials]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

#Preview {
    struct Demo: View {
        @State private var content = SignatureContent()
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                SignatureEditor(content: $content)
                Text("Bound value: \(content.valediction)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }
    return Demo()
        .environmentObject(PractitionerProfileStore())
        .environmentObject(TabRouter())
}
