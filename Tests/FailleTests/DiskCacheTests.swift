import Foundation
import LoLKit
import Testing
@testable import Faille

/// Cache disque des fonctionnalités : chemins sûrs, aller-retour JSON et octets, chemins Data Dragon.
struct DiskCacheTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-cache-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func pathsNeverLeaveTheCache() {
        #expect(DiskCache.safePath("ddragon/16.18.1/img/item/1054.png") == "ddragon/16.18.1/img/item/1054.png")
        #expect(DiskCache.safePath("/replays//g1.json") == "replays/g1.json")
        #expect(DiskCache.safePath("./details/g1.json") == "details/g1.json")
        #expect(DiskCache.safePath("../follows.json") == nil)
        #expect(DiskCache.safePath("spells/../../settings.json") == nil)
        #expect(DiskCache.safePath("") == nil)
        #expect(Self.cache().url("../x.json") == nil)
    }

    @Test func valuesAndBytesRoundTrip() throws {
        let cache = Self.cache()
        let value = Cached(value: ["16.20.1", "16.19.1"], fetchedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        cache.save(value, to: "ddragon/versions.json")
        #expect(cache.load(Cached<[String]>.self, from: "ddragon/versions.json") == value)
        cache.write(Data([1, 2, 3]), to: "ddragon/16.20.1/img/item/1054.png")
        #expect(cache.data("ddragon/16.20.1/img/item/1054.png") == Data([1, 2, 3]))
        #expect(cache.data("ddragon/absent.png") == nil)
        // Fichier illisible : ignoré (la donnée sera relue sur le réseau).
        cache.write(Data("pas du json".utf8), to: "replays/g1.json")
        #expect(cache.load(Cached<[String]>.self, from: "replays/g1.json") == nil)
    }

    @Test func dataDragonUrlsMapToTheirCachePath() throws {
        #expect(DataDragon.cachePath(for: DataDragon.championImage(version: "16.18.1", championId: "KSante"))
            == "ddragon/16.18.1/img/champion/KSante.png")
        #expect(DataDragon.cachePath(for: DataDragon.itemImage(version: "16.18.1", itemId: 3364))
            == "ddragon/16.18.1/img/item/3364.png")
        #expect(DataDragon.cachePath(for: DataDragon.runeIcon("perk-images/Styles/7204_Resolve.png"))
            == "ddragon/img/perk-images/Styles/7204_Resolve.png")
        #expect(DataDragon.cachePath(for: DataDragon.itemsURL(version: "16.18.1")) == "ddragon/16.18.1/data/fr_FR/item.json")
        #expect(DataDragon.cachePath(for: DataDragon.versionsURL) == nil) // `api/` : gardée à part, avec sa date
        #expect(DataDragon.cachePath(for: try #require(URL(string: "https://example.com/cdn/1.png"))) == nil)
    }
}
