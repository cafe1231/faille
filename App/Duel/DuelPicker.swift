import LoLKit
import SwiftUI

/// Sélecteur « Changer » (spec saison §3.3) : recherche parmi les joueurs des games en cache et des effectifs du
/// catalogue.
struct DuelPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        let candidates = DuelModel.candidates(query: query, games: Array(store.season.games.values), catalog: store.catalog)
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisir un joueur").sora(.title).tracking(Typo.titleTracking)
            TextField("", text: $query, prompt: Text("Rechercher un joueur").foregroundStyle(Palette.secondary))
                .sora(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates, id: \.id) { player in
                        Button {
                            onPick(player.id)
                            dismiss()
                        } label: {
                            Text(player.name).sora(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .padding(20)
        .abyssBackground()
        .presentationDetents([.medium, .large])
    }
}
