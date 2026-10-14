import Foundation
import LoLKit
import Testing
import UIKit
@testable import Faille

// Réponses Data Dragon réduites (forme réelle de `api/versions.json` et des fichiers `data/fr_FR/…`).
private let versionsJSON = #"["16.20.1","16.19.1","16.18.1","lolpatch_3.7"]"#
private let itemsJSON = #"{"type":"item","version":"16.18.1","data":{"1054":{"name":"Bouclier de Doran","image":{"full":"1054.png"},"tags":["Health"]},"3364":{"name":"Lentille de l'oracle","image":{"full":"3364.png"},"tags":["Trinket","Vision"]}}}"#
private let runesJSON = #"[{"id":8400,"key":"Resolve","icon":"perk-images/Styles/7204_Resolve.png","name":"Volonté","slots":[{"runes":[{"id":8437,"key":"GraspOfTheUndying","icon":"perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png","name":"Poigne de l'immortel"}]}]}]"#
private let summonersJSON = #"{"type":"summoner","version":"16.18.1","data":{"SummonerFlash":{"id":"SummonerFlash","name":"Saut éclair","image":{"full":"SummonerFlash.png"}}}}"#
private let championJSON = #"{"type":"champion","version":"16.18.1","data":{"KSante":{"id":"KSante","name":"K'Santé","spells":[{"name":"Coups de ntofo","image":{"full":"KSanteQ.png"}},{"name":"Pour Nazumah !","image":{"full":"KSanteW.png"}},{"name":"Jeu de jambes","image":{"full":"KSanteE.png"}},{"name":"Tout donner","image":{"full":"KSanteR.png"}}],"passive":{"name":"Instinct de l'ntofo","image":{"full":"KSante_P.png"}}}}}"#

/// Data Dragon (spec fonctionnalités §3) : version du patch (liste relue au plus toutes les 24 h), catalogues et images
/// gardés sur disque, rien de redemandé inutilement, aucune requête pour le store d'aperçu.
@MainActor
@Suite(.serialized)
struct DataDragonStoreTests {
    private static func cache() -> DiskCache {
        DiskCache(root: TemporaryFiles.directory().appendingPathComponent("cache", isDirectory: true))
    }

    /// Faux Data Dragon : versions, catalogues, sorts de K'Santé et son icône (`png`) ; 404 pour le reste.
    private static func transport(png: Data = Data()) -> ScriptedTransport {
        ScriptedTransport(extra: { url in
            let path = url.path(percentEncoded: false)
            let body: Data?
            if path.hasSuffix("/api/versions.json") {
                body = Data(versionsJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/item.json") {
                body = Data(itemsJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/runesReforged.json") {
                body = Data(runesJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/summoner.json") {
                body = Data(summonersJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/champion/KSante.json") {
                body = Data(championJSON.utf8)
            } else if path.hasSuffix("/img/champion/KSante.png"), !png.isEmpty {
                body = png
            } else {
                body = nil
            }
            return body.map { HTTPResponse(status: 200, body: $0) }
        })
    }

    @Test func versionComesFromTheListWhichIsKeptADay() async {
        let cache = Self.cache()
        let transport = Self.transport()
        let store = DataDragonStore(transport: transport, cache: cache)
        let now = Date()
        #expect(await store.version(forPatch: "16.18.819.1060", now: now) == "16.18.1")
        #expect(store.knownVersion(forPatch: "16.18.819.1060") == "16.18.1")
        #expect(await store.version(forPatch: "16.19.300.1", now: now) == "16.19.1")
        #expect(await transport.requests.count == 1) // une seule lecture de la liste

        // Relancée moins de 24 h plus tard : la liste du disque, sans réseau.
        let offline = ScriptedTransport(mode: .failing)
        let later = DataDragonStore(transport: offline, cache: cache)
        #expect(await later.version(forPatch: "16.20.4.1", now: now.addingTimeInterval(20 * 3600)) == "16.20.1")
        #expect(await offline.requests.isEmpty)

        // Plus de 24 h : nouvel essai ; le réseau échoue, la liste périmée sert encore.
        let stale = DataDragonStore(transport: offline, cache: cache)
        #expect(await stale.version(forPatch: "16.18.1.1", now: now.addingTimeInterval(25 * 3600)) == "16.18.1")
        #expect(await offline.requests.count == 1)
    }

    @Test func catalogsAreReadOnceThenFromDisk() async {
        let cache = Self.cache()
        let transport = Self.transport()
        let store = DataDragonStore(transport: transport, cache: cache)
        await store.loadCatalogs(version: "16.18.1")
        #expect(store.items["16.18.1"]?.item(3364)?.isTrinket == true)
        #expect(store.runes["16.18.1"]?.rune(8437)?.name == "Poigne de l'immortel")
        #expect(store.summoners["16.18.1"]?.spell("SummonerFlash")?.name == "Saut éclair")
        #expect(await transport.requests.count == 3)
        await store.loadCatalogs(version: "16.18.1")
        #expect(await transport.requests.count == 3)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = DataDragonStore(transport: offline, cache: cache)
        await reopened.loadCatalogs(version: "16.18.1")
        #expect(reopened.items["16.18.1"]?.item(1054)?.name == "Bouclier de Doran")
        #expect(await offline.requests.isEmpty)

        // Sorts d'un champion : lus à la demande (fiche du joueur), puis gardés.
        #expect(await reopened.champion(version: "16.18.1", championId: "KSante") == nil) // hors ligne, jamais lus
        let spells = await store.champion(version: "16.18.1", championId: "KSante")
        #expect(spells?.spell(forAbility: "R")?.image == "KSanteR.png")
        #expect(await reopened.champion(version: "16.18.1", championId: "KSante")?.passive?.image == "KSante_P.png")
    }

    @Test func imagesAreKeptOnDiskAndMissingOnesAreNotAskedAgain() async throws {
        let cache = Self.cache()
        let png = TestImages.png(.systemTeal, letter: "K")
        let transport = Self.transport(png: png)
        let store = DataDragonStore(transport: transport, cache: cache)
        let url = DataDragon.championImage(version: "16.18.1", championId: "KSante")
        #expect(store.cachedImage(url) == nil)
        #expect(await store.image(url) != nil)
        #expect(store.cachedImage(url) != nil)
        #expect(cache.data("ddragon/16.18.1/img/champion/KSante.png") == png)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = DataDragonStore(transport: offline, cache: cache)
        #expect(await reopened.image(url) != nil)
        #expect(await offline.requests.isEmpty)

        let missing = DataDragon.itemImage(version: "16.18.1", itemId: 9999)
        #expect(await store.image(missing) == nil)
        #expect(await store.image(missing) == nil)
        #expect(await transport.requests.filter { $0 == missing }.count == 1)
    }

    @Test func previewStoreAsksNothing() async {
        let store = DataDragonStore.preview()
        #expect(await store.version(forPatch: "16.18.819.1060") == nil)
        await store.loadCatalogs(version: "16.18.1")
        #expect(store.items.isEmpty)
        #expect(await store.image(DataDragon.championImage(version: "16.18.1", championId: "KSante")) == nil)
    }

    @Test func fallbackInitialsReadTheChampionId() {
        #expect(DDragonIcon.initials("KSante") == "KS")
        #expect(DDragonIcon.initials("XinZhao") == "XZ")
        #expect(DDragonIcon.initials("Ahri") == "AH")
        #expect(DDragonIcon.initials("") == "")
    }
}
