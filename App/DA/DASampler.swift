import SwiftUI

/// Planche de la DA (couleurs, typographie, icônes, verre) : rendue en PNG (00-da) pour juger depuis Windows.
struct DASampler: View {
    private struct SampleTint: Identifiable {
        let code: String
        let hex: String
        var id: String { code }
    }

    private let tints = [SampleTint(code: "KC", hex: "#5B8CFF"), SampleTint(code: "T1", hex: "#FF5C7A"),
                         SampleTint(code: "GEN", hex: "#FFB454")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Planche DA", subtitle: "Abysse · Verre · Sora · Vitrail")
                SectionLabel(text: "Typographie")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Titre 32").sora(.title).tracking(Typo.titleTracking)
                    Text("Score 1 – 0").sora(.score)
                    Text("Corps 15 regular").sora(.body)
                    Text("Corps 15 medium").sora(.bodyMedium)
                    Text("Titre 15 semibold").sora(.headline)
                    Text("Secondaire 12").sora(.secondary).foregroundStyle(Palette.secondary)
                    Text("Étiquette 11")
                        .sora(.label)
                        .tracking(Typo.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondary)
                }
                .foregroundStyle(Palette.text)
                SectionLabel(text: "Icônes")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(Icon.allCases, id: \.self) { icon in
                        IconView(icon: icon, size: 22)
                    }
                }
                .foregroundStyle(Palette.text)
                SectionLabel(text: "Vitrail")
                ForEach(tints) { sample in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Équipe \(sample.code)", dot: Palette.team(sample.hex))
                        HStack {
                            TeamBadge(code: sample.code, tint: Palette.team(sample.hex))
                            Text(sample.code).sora(.headline)
                            Spacer()
                            Chip {
                                IconView(icon: .live, size: 12)
                                Text("En direct · Game 2 · 18:42")
                            }
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .glassCard(tint: Palette.team(sample.hex))
                }
                HStack {
                    TeamBadge(code: "C9")
                    Text("Verre neutre").sora(.body)
                    Spacer()
                    Chip(muted: true) {
                        IconView(icon: .eyeOff, size: 12)
                        Text("masqué")
                    }
                }
                .foregroundStyle(Palette.text)
                .glassCard(radius: Radius.inner)
                ErrorBanner(text: "lolesports ne répond pas · màj 14:05")
                NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .abyssBackground()
    }
}

#Preview {
    DASampler()
}
