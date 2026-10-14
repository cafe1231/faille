import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Icônes Data Dragon (spec fonctionnalités §3) : lues dans un cache rempli de fausses icônes (aucun réseau, aucune
    /// image de Riot dans le dépôt), puis vignettes de repli quand la version ou l'image manque.
    @Test func dataDragonBoard() async throws {
        let cache = DiskCache(root: TemporaryFiles.directory().appendingPathComponent("cache", isDirectory: true))
        let version = "16.18.1"
        let champion = DataDragon.championImage(version: version, championId: "KSante")
        let item = DataDragon.itemImage(version: version, itemId: 1054)
        let rune = DataDragon.runeIcon("perk-images/Styles/7204_Resolve.png")
        let spell = DataDragon.summonerSpellImage(version: version, spellId: "SummonerFlash")
        TestImages.seed(cache, [(champion, .systemIndigo, "K"), (item, .systemGreen, "D"), (rune, .systemTeal, "R"),
                                (spell, .systemYellow, "F")])
        // Les quatre icônes sont décodées avant la capture : l'aperçu ne dépend plus du délai de `Snapshot.write` (1 s).
        let store = DataDragonStore(transport: nil, cache: cache)
        for icon in [champion, item, rune, spell] {
            _ = await store.image(icon)
        }
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Data Dragon", subtitle: "Icônes en cache · vignettes de repli")
                SectionLabel(text: "Depuis le cache")
                HStack(spacing: 10) {
                    DDragonIcon(url: champion, size: 48, fallback: "KS")
                    DDragonIcon(url: item, size: 32, radius: 6)
                    DDragonIcon(url: rune, size: 32, radius: 16)
                    DDragonIcon(url: spell, size: 32)
                }
                .glassCard(radius: Radius.inner, padding: 14)
                SectionLabel(text: "Vignettes de repli")
                HStack(spacing: 10) {
                    DDragonIcon(url: nil, size: 48, fallback: DDragonIcon.initials("XinZhao"))
                    DDragonIcon(url: DataDragon.championImage(version: version, championId: "Ahri"), size: 48,
                                fallback: DDragonIcon.initials("Ahri"))
                    DDragonIcon(url: nil, size: 32, radius: 6)
                    DDragonIcon(url: nil, size: 32, radius: 16)
                }
                .glassCard(radius: Radius.inner, padding: 14)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .environment(\.dataDragon, store)
        let url = try await Snapshot.write(board, named: "18-data-dragon")
        expectNotBlank(url)
    }
}
