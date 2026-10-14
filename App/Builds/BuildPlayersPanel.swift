import LoLKit
import SwiftUI

/// Ce dont les lignes et la fiche d'un joueur ont besoin en plus du joueur : version Data Dragon (liens des icônes),
/// catalogues (balise, noms, icônes des runes) et sorts d'invocateur de Leaguepedia par champion (game terminée).
struct BuildContext: Equatable {
    var version: String?
    var items: ItemCatalog?
    var runes: RuneCatalog?
    var summoners: SummonerCatalog?
    /// Sorts de Leaguepedia par champion ; vide en direct ou tant que le wiki n'a pas la game.
    var summonerSpells: [String: [String]] = [:]

    func championURL(_ championId: String) -> URL? {
        version.map { DataDragon.championImage(version: $0, championId: championId) }
    }

    func itemURL(_ itemId: Int?) -> URL? {
        guard let itemId, let version else { return nil }
        return DataDragon.itemImage(version: version, itemId: itemId)
    }

    func summonerURL(_ spellId: String) -> URL? {
        version.map { DataDragon.summonerSpellImage(version: $0, spellId: spellId) }
    }

    /// Rune principale (clé de voûte) d'un joueur.
    func keystone(_ details: ParticipantDetails?) -> RuneCatalog.Entry? {
        details?.perkMetadata?.keystone.flatMap { runes?.rune($0) }
    }

    /// Arbre secondaire d'un joueur.
    func secondaryTree(_ details: ParticipantDetails?) -> RuneCatalog.Entry? {
        details?.perkMetadata.flatMap { runes?.style($0.subStyleId) }
    }

    /// Sorts d'invocateur à montrer pour ce joueur (`PlayerBuilds.summonerSpells`).
    func spells(for line: PlayerLine) -> [String] {
        PlayerBuilds.summonerSpells(role: line.role, leaguepedia: summonerSpells[line.champion])
    }
}

/// Section « Joueurs » enrichie (spec fonctionnalités §3) : sélecteur d'équipe, puis une ligne par joueur — icône du
/// champion et niveau, pseudo, KDA, CS, gold, six objets et la balise, rune principale et arbre secondaire, sorts
/// d'invocateur. Toucher une ligne ouvre la fiche du joueur. Remplace `PlayersPanel` (spec §5.3).
struct BuildPlayersPanel: View {
    /// Équipes dans l'ordre d'affichage.
    let teams: [MatchTeam]
    /// Joueurs de chaque équipe affichée (`PlayerBuilds.rows`).
    let rows: [[PlayerBuild]]
    let context: BuildContext
    @Binding var selection: Int
    /// Joueur touché et index de son équipe (fiche du joueur).
    let onSelect: (PlayerBuild, Int) -> Void

    var body: some View {
        let index = rows.indices.contains(selection) ? selection : 0
        let players = rows.indices.contains(index) ? rows[index] : []
        VStack(alignment: .leading, spacing: 10) {
            Picker("Équipe", selection: $selection) {
                ForEach(teams.indices, id: \.self) { position in
                    Text(teams[position].code).tag(position)
                }
            }
            .pickerStyle(.segmented)
            // Changement d'équipe animé (spec finitions §9) : fondu des lignes, animation portée par `selection`.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(players) { player in
                    Button {
                        onSelect(player, index)
                    } label: {
                        PlayerBuildRow(player: player, context: context)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                if players.isEmpty {
                    Text("Joueurs indisponibles")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .id(index)
            .transition(.opacity)
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Une ligne de joueur : champion (et niveau), pseudo et rôle, « Champion · KDA · CS · gold », sorts d'invocateur ; puis
/// six objets, la balise (ronde), la rune principale et l'arbre secondaire.
struct PlayerBuildRow: View {
    let player: PlayerBuild
    let context: BuildContext

    var body: some View {
        let line = player.line
        let inventory = PlayerBuilds.inventory(player.details?.items ?? [], catalog: context.items)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DDragonIcon(url: context.championURL(line.champion), size: 36,
                            fallback: DDragonIcon.initials(line.champion))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(player.level)")
                            .font(Sora.font(9, .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 3)
                            .background(Palette.abyss.opacity(0.85), in: Capsule())
                            .offset(x: 4, y: 4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(line.name.isEmpty ? Format.champion(line.champion) : line.name)
                            .font(Typo.secondaryMedium)
                            .lineLimit(1)
                        Text(Format.role(line.role))
                            .font(Typo.label)
                            .foregroundStyle(Palette.secondary)
                    }
                    Text("\(Format.champion(line.champion)) · \(Format.kda(line)) · \(line.creepScore) CS · \(Format.gold(line.gold))")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(context.spells(for: line), id: \.self) { spell in
                        DDragonIcon(url: context.summonerURL(spell), size: 18, radius: 4)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(PlayerBuilds.slots(inventory).enumerated()), id: \.offset) { _, item in
                    DDragonIcon(url: context.itemURL(item), size: 20, radius: 4)
                }
                DDragonIcon(url: context.itemURL(inventory.trinket), size: 20, radius: 10)
                Spacer(minLength: 6)
                DDragonIcon(url: context.keystone(player.details).map { DataDragon.runeIcon($0.icon) }, size: 20,
                            radius: 10)
                DDragonIcon(url: context.secondaryTree(player.details).map { DataDragon.runeIcon($0.icon) }, size: 16,
                            radius: 8)
            }
            .padding(.leading, 46)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name), \(Format.champion(line.champion)), \(Format.kda(line)), \(line.creepScore) CS")
        .accessibilityHint("Ouvre la fiche du joueur")
    }
}

/// Squelette de la section « Joueurs » enrichie : sélecteur, puis cinq lignes à deux étages, à la hauteur de
/// `BuildPlayersPanel` (le Détail ne saute pas quand les joueurs arrivent).
struct BuildPlayersSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(height: 32, radius: 8)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            SkeletonBlock(width: 36, height: 36, radius: 8)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: 110, height: 11)
                                SkeletonBlock(width: 180, height: 10)
                            }
                            Spacer()
                        }
                        SkeletonBlock(width: 160, height: 20, radius: 4)
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joueurs en chargement")
    }
}
