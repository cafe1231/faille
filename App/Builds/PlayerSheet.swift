import LoLKit
import SwiftUI

/// Ce que la fiche d'un joueur affiche : le joueur, son équipe (code et couleur) et le contexte de la game.
struct PlayerSheetItem: Identifiable, Equatable {
    let player: PlayerBuild
    let teamCode: String
    let tint: Color?
    let context: BuildContext
    /// Game terminée : les sorts d'invocateur viennent de Leaguepedia (sinon seul le Châtiment du jungler est connu).
    let finished: Bool
    /// Game de la fiche : ses sorts d'invocateur sont lus en direct dans le store (`PlayerSheet`), car Leaguepedia peut
    /// répondre pendant que la fiche est ouverte. nil (aperçus de composants) : ceux du `context`.
    var gameId: String? = nil

    var id: Int { player.participantId }
}

/// Fiche d'un joueur (spec fonctionnalités §3) : champion, KDA, CS, gold, niveau, participation aux kills, part des
/// dégâts (barre), balises posées et détruites, ordre de montée des sorts (icônes du champion), runes, objets nommés et
/// sorts d'invocateur. Tout est déjà chargé par le Détail, sauf les sorts du champion (`champion/<id>.json`), lus à
/// l'ouverture de la fiche.
struct PlayerSheet: View {
    let item: PlayerSheetItem
    @Environment(\.dataDragon) private var store
    /// Le store de l'appli, pour lire les sorts d'invocateur en direct ; nil (aperçus de composants) : ceux de la fiche.
    @Environment(AppStore.self) private var appStore: AppStore?
    @Environment(\.dismiss) private var dismiss
    @State private var champion: ChampionSpells?

    var body: some View {
        let line = item.player.line
        let details = item.player.details
        let context = item.context
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(line)
                    stats(line, details)
                    if let share = details?.championDamageShare {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                StatLabel(icon: .swords, text: String(localized: "Part des dégâts"))
                                Spacer()
                                Text(PlayerBuilds.percent(share)).sora(.stat).monospacedDigit()
                            }
                            ShareBar(value: share, tint: item.tint ?? Palette.accent)
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    if let abilities = details?.abilities, !abilities.isEmpty {
                        section(String(localized: "Ordre des sorts")) {
                            AbilityOrderView(abilities: abilities, champion: champion, version: context.version)
                        }
                    }
                    section(String(localized: "Runes")) { runes(details) }
                    section(String(localized: "Objets")) { items(details) }
                    section(String(localized: "Sorts d'invocateur")) { summonerSpells(line) }
                }
                .padding(16)
            }
            .abyssBackground()
            .navigationTitle(line.name.isEmpty ? Format.champion(line.champion) : line.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task(id: line.champion) {
            guard let version = context.version, let store else { return }
            champion = await store.champion(version: version, championId: line.champion)
        }
    }

    private func header(_ line: PlayerLine) -> some View {
        HStack(spacing: 12) {
            DDragonIcon(url: item.context.championURL(line.champion), size: 56,
                        fallback: DDragonIcon.initials(line.champion))
            VStack(alignment: .leading, spacing: 3) {
                Text(champion?.name ?? Format.champion(line.champion))
                    .sora(.headline)
                Text("\(item.teamCode) · \(Format.role(line.role)) · niveau \(item.player.level)")
                    .sora(.secondary)
                    .foregroundStyle(item.tint ?? Palette.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: item.tint, radius: Radius.inner, padding: 14)
    }

    private func stats(_ line: PlayerLine, _ details: ParticipantDetails?) -> some View {
        let wards = details.flatMap { detail in
            detail.wardsPlaced.map { "\($0) / \(detail.wardsDestroyed ?? 0)" }
        } ?? "—"
        return VStack(spacing: 8) {
            statRow(String(localized: "KDA"), Format.kda(line))
            statRow(String(localized: "Gold"), Format.gold(line.gold))
            statRow(String(localized: "CS"), "\(line.creepScore)")
            statRow(String(localized: "Participation aux kills"), PlayerBuilds.percent(details?.killParticipation))
            statRow(String(localized: "Balises posées / détruites"), wards)
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .sora(.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondary)
            Spacer()
            Text(value)
                .sora(.stat)
                .monospacedDigit()
        }
        .foregroundStyle(Palette.text)
    }

    @ViewBuilder private func runes(_ details: ParticipantDetails?) -> some View {
        let context = item.context
        if let keystone = context.keystone(details) {
            nameRow(url: DataDragon.runeIcon(keystone.icon), name: keystone.name, round: true)
        }
        if let tree = context.secondaryTree(details) {
            nameRow(url: DataDragon.runeIcon(tree.icon), name: tree.name, round: true)
        }
        if context.keystone(details) == nil, context.secondaryTree(details) == nil {
            Text("Runes indisponibles")
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder private func items(_ details: ParticipantDetails?) -> some View {
        let context = item.context
        let inventory = PlayerBuilds.inventory(details?.items ?? [], catalog: context.items)
        ForEach(Array(inventory.items.enumerated()), id: \.offset) { _, id in
            nameRow(url: context.itemURL(id), name: context.items?.item(id)?.name ?? String(localized: "Objet \(id)"), round: false)
        }
        if let trinket = inventory.trinket {
            nameRow(url: context.itemURL(trinket), name: context.items?.item(trinket)?.name ?? String(localized: "Balise"), round: true)
        }
        if inventory.items.isEmpty, inventory.trinket == nil {
            Text("Aucun objet")
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    /// Contexte de la fiche, avec les sorts d'invocateur du store tels qu'ils sont à cet instant : la fiche se met à jour si
    /// Leaguepedia répond pendant qu'elle est ouverte (le reste du contexte est celui de son ouverture).
    private var liveContext: BuildContext {
        var context = item.context
        if item.finished, let gameId = item.gameId, let known = appStore?.summonerSpells.spells[gameId] {
            context.summonerSpells = known
        }
        return context
    }

    @ViewBuilder private func summonerSpells(_ line: PlayerLine) -> some View {
        let context = liveContext
        let spells = context.spells(for: line)
        ForEach(spells, id: \.self) { spell in
            nameRow(url: context.summonerURL(spell), name: context.summoners?.spell(spell)?.name ?? spell, round: false)
        }
        Text(item.finished
             ? (context.summonerSpells[line.champion] == nil
                ? String(localized: "Leaguepedia n'a pas encore cette game : seul le Châtiment du jungler est connu.")
                : String(localized: "Source : Leaguepedia."))
             : String(localized: "En direct, Riot ne donne pas les sorts d'invocateur : seul le Châtiment du jungler est connu."))
            .sora(.secondary)
            .foregroundStyle(Palette.secondary)
    }

    private func nameRow(url: URL?, name: String, round: Bool) -> some View {
        HStack(spacing: 10) {
            DDragonIcon(url: url, size: 28, radius: round ? 14 : 6)
            Text(name)
                .sora(.body)
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .glassCard(radius: Radius.inner, padding: 14)
        }
    }
}

/// Barre d'une part (0…1) à la couleur de l'équipe : part des dégâts.
struct ShareBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

/// Ordre de montée des sorts : le passif et les quatre sorts du champion (icônes, lettres P Q W E R), puis la lettre
/// montée à chaque niveau ; R à l'accent.
struct AbilityOrderView: View {
    let abilities: [String]
    let champion: ChampionSpells?
    let version: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(["P", "Q", "W", "E", "R"], id: \.self) { letter in
                    VStack(spacing: 3) {
                        DDragonIcon(url: url(letter), size: 30, fallback: letter)
                        Text(letter)
                            .sora(.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 9), alignment: .leading,
                      spacing: 4) {
                ForEach(Array(abilities.enumerated()), id: \.offset) { level, letter in
                    Text(letter)
                        .font(Sora.font(11, .bold))
                        .foregroundStyle(letter == "R" ? Palette.abyss : Palette.text)
                        .frame(width: 24, height: 24)
                        .background(letter == "R" ? Palette.accent : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Niveau \(level + 1) : \(letter)")
                }
            }
        }
    }

    /// Icône du passif (« P », `passive.image`) ou du sort d'une lettre (`spells[Q…R].image`) ; nil tant que la version ou
    /// les sorts du champion ne sont pas connus (vignette de repli).
    private func url(_ letter: String) -> URL? {
        guard let version else { return nil }
        if letter == "P" {
            return champion?.passive.map { DataDragon.passiveImage(version: version, file: $0.image) }
        }
        guard let file = champion?.spell(forAbility: letter)?.image else { return nil }
        return DataDragon.spellImage(version: version, file: file)
    }
}
