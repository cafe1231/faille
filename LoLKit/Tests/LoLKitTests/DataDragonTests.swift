import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli choisit la version, écrit les liens et lit les catalogues.
import LoLKit

/// Data Dragon (spec fonctionnalités §3), sur de vrais fichiers réduits (version 16.17.1, fr_FR, capturés le 14/10/2026).
@Suite struct DataDragonTests {
    private func versions() throws -> [String] {
        try DataDragon.decodeVersions(Fixture.data("ddragon_versions"))
    }

    @Test func versionOfThePatchOfTheFeed() throws {
        let list = try versions()
        #expect(list.count == 22)
        #expect(list.first == "16.20.1")
        // Patchs réels des fixtures window_* : 16.17 (finale LCS), 16.18 (Demacia Cup).
        #expect(DataDragon.version(forPatch: "16.17.815.3183", versions: list) == "16.17.1")
        #expect(DataDragon.version(forPatch: "16.18.819.1060", versions: list) == "16.18.1")
        // « 16.1. » ne prend pas « 16.18.1 » ni « 16.19.1 ».
        #expect(DataDragon.version(forPatch: "16.1.540.1", versions: list) == "16.1.1")
        #expect(DataDragon.version(forPatch: "15.24.700.1", versions: list) == "15.24.1")
    }

    @Test func unknownPatchFallsBackToTheMostRecent() throws {
        let list = try versions()
        #expect(DataDragon.version(forPatch: "16.21.900.1", versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: nil, versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: "", versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: "16", versions: list) == "16.20.1")
        // Les entrées « lolpatch_* » ne sont jamais des versions.
        #expect(DataDragon.version(forPatch: "16.17.1", versions: ["lolpatch_3.7"]) == nil)
        #expect(DataDragon.version(forPatch: "16.17.1", versions: []) == nil)
    }

    @Test func imageAndDataLinks() {
        #expect(DataDragon.versionsURL.absoluteString == "https://ddragon.leagueoflegends.com/api/versions.json")
        #expect(DataDragon.versionsMaxAge == 86_400)
        #expect(DataDragon.championImage(version: "16.17.1", championId: "KSante").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/champion/KSante.png")
        #expect(DataDragon.itemImage(version: "16.17.1", itemId: 3364).absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/item/3364.png")
        #expect(DataDragon.spellImage(version: "16.17.1", file: "KSanteQ.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/spell/KSanteQ.png")
        #expect(DataDragon.passiveImage(version: "16.17.1", file: "Icons_KSante_P.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/passive/Icons_KSante_P.png")
        #expect(DataDragon.summonerSpellImage(version: "16.17.1", spellId: "SummonerFlash").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/spell/SummonerFlash.png")
        #expect(DataDragon.runeIcon("perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/img/perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png")
        #expect(DataDragon.itemsURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/item.json")
        #expect(DataDragon.runesURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/runesReforged.json")
        #expect(DataDragon.summonerSpellsURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/summoner.json")
        #expect(DataDragon.championURL(version: "16.17.1", championId: "KSante").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/champion/KSante.json")
        // Un id inattendu du flux est encodé, le lien reste valide.
        #expect(DataDragon.championImage(version: "16.17.1", championId: "Nouveau Champion").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/champion/Nouveau%20Champion.png")
    }

    @Test func itemCatalog() throws {
        let catalog = try ItemCatalog(json: Fixture.data("ddragon_item"))
        #expect(catalog.version == "16.17.1")
        #expect(catalog.items.count == 9)
        #expect(catalog.item(6692) == ItemCatalog.Item(id: 6692, name: "Éclipse", image: "6692.png", isTrinket: false))
        #expect(catalog.item(3364) == ItemCatalog.Item(id: 3364, name: "Brouilleur oraculaire", image: "3364.png",
                                                       isTrinket: true))
        #expect(catalog.item(3340)?.isTrinket == true)
        #expect(catalog.item(2055)?.name == "Balise de contrôle")
        #expect(catalog.item(2055)?.isTrinket == false)
        #expect(catalog.item(9999) == nil)
        // Objets réels du joueur 1 (TLAW Morgan) dans la fixture details_ingame : la balise passe à part.
        #expect(catalog.inventory([1054, 2031, 6692, 1001, 3364, 3071, 1036])
                == ItemCatalog.Inventory(items: [1054, 2031, 6692, 1001, 3071, 1036], trinket: 3364))
        #expect(catalog.inventory([1054, 4242]) == ItemCatalog.Inventory(items: [1054, 4242], trinket: nil))
    }

    @Test func runeCatalog() throws {
        let catalog = try RuneCatalog(json: Fixture.data("ddragon_runesReforged"))
        #expect(catalog.styles.count == 2)
        #expect(catalog.runes.count == 24)
        #expect(catalog.style(8400) == RuneCatalog.Entry(id: 8400, key: "Resolve", name: "Volonté",
                                                         icon: "perk-images/Styles/7204_Resolve.png"))
        #expect(catalog.style(8300)?.icon == "perk-images/Styles/7203_Whimsy.png")
        #expect(catalog.rune(8437) == RuneCatalog.Entry(
            id: 8437, key: "GraspOfTheUndying", name: "Poigne de l'immortel",
            icon: "perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png"))
        #expect(catalog.rune(8345)?.name == "Livraison de biscuits")
        // Fragments de stats (5008…) : absents de runesReforged.json.
        #expect(catalog.rune(5008) == nil)
    }

    @Test func summonerCatalog() throws {
        let catalog = try SummonerCatalog(json: Fixture.data("ddragon_summoner"))
        #expect(catalog.spells.count == 9)
        #expect(catalog.spell("SummonerFlash") == SummonerCatalog.Spell(id: "SummonerFlash", name: "Saut éclair",
                                                                       image: "SummonerFlash.png"))
        #expect(catalog.spell("SummonerDot")?.name == "Embrasement")
        #expect(catalog.spell("SummonerBoost")?.name == "Purge")
        #expect(catalog.spell("SummonerTeleport")?.name == "Téléportation")
        #expect(catalog.spell("Flash") == nil)
    }

    @Test func championSpells() throws {
        let ksante = try ChampionSpells(json: Fixture.data("ddragon_champion_KSante"))
        #expect(ksante.championId == "KSante")
        #expect(ksante.name == "K'Santé")
        #expect(ksante.spells.map(\.image) == ["KSanteQ.png", "KSanteW.png", "KSanteE.png", "KSanteR.png"])
        #expect(ksante.spell(forAbility: "Q") == ChampionSpells.Ability(name: "Coups de ntofo", image: "KSanteQ.png"))
        #expect(ksante.spell(forAbility: "r")?.name == "Grand jeu")
        #expect(ksante.spell(forAbility: "P") == nil)
        #expect(ksante.passive == ChampionSpells.Ability(name: "Instinct intrépide", image: "Icons_KSante_P.png"))
    }

    @Test func toleratesUnreadableEntries() throws {
        let items = #"{"version":"16.17.1","data":{"1001":{"name":"Bottes","image":{"full":"1001.png"},"tags":["Boots"]},"1002":{"name":7},"abc":{"name":"x","image":{"full":"x.png"}}}}"#
        let catalog = try ItemCatalog(json: Data(items.utf8))
        #expect(catalog.items.keys.sorted() == [1001])
        let summoners = #"{"data":{"SummonerFlash":{"id":"SummonerFlash","name":"Saut éclair","image":{"full":"SummonerFlash.png"}},"Bad":{}}}"#
        #expect(try SummonerCatalog(json: Data(summoners.utf8)).spells.count == 1)
        #expect(throws: (any Error).self) { try ChampionSpells(json: Data(#"{"data":{}}"#.utf8)) }
    }
}
