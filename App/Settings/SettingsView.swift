import LoLKit
import SwiftUI

/// Réglages (spec §5.4) : mode de la Live Activity et À propos.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Live Activity")
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Live Activity", selection: mode) {
                            Text("Automatique").tag(LiveActivityMode.automatic)
                            Text("Manuelle").tag(LiveActivityMode.manual)
                        }
                        .pickerStyle(.segmented)
                        Text(explanation)
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                        Text("Sans serveur de push, la Live Activity se met à jour quand Faille est ouverte, et en arrière-plan quand iOS le permet (environ toutes les 15 min, si l'actualisation en arrière-plan est activée). Sinon elle affiche « màj il y a X minutes ».")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                    .glassCard(radius: Radius.inner, padding: 14)

                    SectionLabel(text: "Faille")
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Text("À propos").font(Typo.body)
                            Spacer()
                            IconView(icon: .arrow, size: 15)
                                .foregroundStyle(Palette.secondary)
                        }
                        .foregroundStyle(Palette.text)
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(16)
            }
            .abyssBackground()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    /// Une seule source de vérité : le réglage du store, lu et écrit directement (rien n'est recopié dans la vue).
    private var mode: Binding<LiveActivityMode> {
        Binding(get: { store.settings.liveActivityMode }, set: { store.setLiveActivityMode($0) })
    }

    private var explanation: String {
        switch store.settings.liveActivityMode {
        case .automatic:
            return "Automatique : chaque match en direct d'une équipe suivie s'affiche tout seul sur l'écran verrouillé (3 au plus)."
        case .manual:
            return "Manuelle : rien ne s'affiche tout seul, on épingle un match depuis son écran Détail."
        }
    }
}

/// À propos : source des données, version, stockage, diagnostic des Live Activities.
struct AboutView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                block("Faille", "Version \(Self.version)")
                block("Données", "Matchs, équipes et stats viennent de l'API de lolesports.com (non officielle) et du flux livestats de Riot, avec une à deux minutes de retard sur le direct (le flux de Riot suit la diffusion). Usage strictement personnel.")
                block("Stockage", AppGroup.identifier.map { "Groupe d'apps : \($0)" }
                      ?? "Aucun groupe d'apps : les données restent dans l'appli seule.")
                diagnostic
                Text("Police Sora, sous licence SIL Open Font License.")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            .padding(16)
        }
        .abyssBackground()
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
        // L'utilisateur a pu changer l'autorisation dans les Réglages d'iOS depuis la dernière passe.
        .onAppear { store.liveActivities.refreshAuthorization() }
    }

    /// « Diagnostic Live Activity » : pourquoi une Live Activity n'est pas apparue ou ne bouge pas en arrière-plan (le
    /// journal d'iOS n'est pas lisible depuis Windows). Heures locales, « — » quand c'est inconnu.
    private var diagnostic: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostic Live Activity")
                .font(Typo.headline)
                .foregroundStyle(Palette.text)
            ForEach(store.liveActivityDiagnosticLines()) { line in
                Text("\(line.title) : \(line.value)")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.headline)
                .foregroundStyle(Palette.text)
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    /// « 0.1.0 (1) · LoLKit 0.1.0 »
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build)) · LoLKit \(LoLKitInfo.version)"
    }
}

#Preview {
    SettingsView().environment(AppStore(preview: .standard))
}
