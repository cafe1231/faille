import Foundation
import LoLKit
import Testing
@testable import Faille

/// Flux `details` de la game GD (forme réelle, deux frames, deux joueurs).
private let detailsJSON = """
{"frames":[{"rfc460Timestamp":"2026-10-04T20:38:20.000Z","participants":[{"participantId":1,"level":11,"kills":1,\
"deaths":0,"assists":2,"creepScore":150,"totalGoldEarned":6000,"items":[1054,3340],"perkMetadata":{"styleId":8400,\
"subStyleId":8300,"perks":[8437,8401]},"abilities":["Q","E","W"]}]},{"rfc460Timestamp":"2026-10-04T20:38:29.000Z",\
"participants":[{"participantId":1,"level":12,"kills":2,"deaths":0,"assists":2,"creepScore":160,"totalGoldEarned":6500,\
"killParticipation":0.5,"championDamageShare":0.27,"wardsPlaced":7,"wardsDestroyed":1,"items":[1054,3340,3071],\
"perkMetadata":{"styleId":8400,"subStyleId":8300,"perks":[8437,8401]},"abilities":["Q","E","W","Q"]},\
{"participantId":6,"level":10,"kills":0,"deaths":2,"assists":0,"creepScore":120,"totalGoldEarned":4500,"items":[1055],\
"abilities":["Q"]}]}]}
"""

/// Faux flux `details` de la game GD (404 si `statsDisabled`).
private func detailsTransport(statsDisabled: Bool = false) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        guard url.path.contains("/details/GD") else { return nil }
        return statsDisabled ? HTTPResponse(status: 404, body: Data())
            : HTTPResponse(status: 200, body: Data(detailsJSON.utf8))
    })
}

/// Draft et builds (spec fonctionnalités §3) : jointure des lignes du flux et du détail par `participantId`, balise à part,
/// sorts d'invocateur (Leaguepedia, sinon Châtiment du jungler), détails gardés sur disque et lus au plus une fois pour
/// une game terminée.
@MainActor
@Suite(.serialized)
struct BuildsTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-builds-\(UUID().uuidString)", isDirectory: true))
    }

    private static func detailsRequests(_ transport: ScriptedTransport) async -> Int {
        await transport.requests.filter { $0.path.contains("/details/") }.count
    }

    @Test func rowsJoinTheFeedLinesToTheirDetails() throws {
        let snapshot = SampleData.kcSnapshot
        let details = BuildSamples.details(for: snapshot)
        let blue = PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "kc")
        let red = PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "c9")
        #expect(blue.map(\.participantId) == [1, 2, 3, 4, 5])
        #expect(red.map(\.participantId) == [6, 7, 8, 9, 10])
        #expect(red[0].line.champion == "KSante")
        #expect(red[0].details?.participantId == 6)
        #expect(blue[1].details?.items.contains(3364) == true) // balise du jungler
        #expect(PlayerBuilds.rows(snapshot: snapshot, details: nil, teamId: "kc").allSatisfy { $0.details == nil })
        #expect(PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "g2").isEmpty)
        #expect(PlayerBuilds.draft(snapshot: snapshot, teamIds: ["c9", "kc"])
            == [["KSante", "Vi", "Azir", "Ezreal", "Nautilus"], ["Rumble", "XinZhao", "Taliyah", "Kaisa", "Rell"]])
    }

    @Test func trinketIsSetApartAndSlotsArePadded() {
        let fallback = PlayerBuilds.inventory([1054, 2031, 6692, 1001, 3364, 3071, 1036], catalog: nil)
        #expect(fallback.trinket == 3364)
        #expect(fallback.items == [1054, 2031, 6692, 1001, 3071, 1036])
        let catalog = ItemCatalog(version: "16.18.1", items: [
            3330: ItemCatalog.Item(id: 3330, name: "Poupée épouvantail", image: "3330.png", isTrinket: true),
        ])
        let withCatalog = PlayerBuilds.inventory([1054, 3330], catalog: catalog)
        #expect(withCatalog.trinket == 3330)
        #expect(PlayerBuilds.slots(withCatalog) == [1054, nil, nil, nil, nil, nil])
    }

    @Test func summonerSpellsComeFromTheWikiElseSmiteForTheJungler() {
        #expect(PlayerBuilds.summonerSpells(role: "jungle", leaguepedia: ["SummonerFlash", "SummonerSmite"])
            == ["SummonerFlash", "SummonerSmite"])
        #expect(PlayerBuilds.summonerSpells(role: "jungle", leaguepedia: nil) == ["SummonerSmite"])
        #expect(PlayerBuilds.summonerSpells(role: "mid", leaguepedia: nil).isEmpty)
        #expect(PlayerBuilds.summonerSpells(role: "mid", leaguepedia: []).isEmpty)
        #expect(PlayerBuilds.percent(0.274) == "27 %")
        #expect(PlayerBuilds.percent(nil) == "—")
    }

    @Test func liveDetailsKeepTheLastFrameOnDisk() async {
        let cache = Self.cache()
        let transport = detailsTransport()
        let store = GameDetailsStore(transport: transport, cache: cache)
        await store.refresh(gameId: "GD", finished: false)
        #expect(store.details["GD"]?.frames.count == 1)
        #expect(store.details["GD"]?.latest(participantId: 1)?.items == [1054, 3340, 3071])
        // Game en cours : relue à chaque tour (toutes les 60 s, cadence tenue par `follow`).
        await store.refresh(gameId: "GD", finished: false)
        #expect(await Self.detailsRequests(transport) == 2)
        let saved = cache.load(SavedDetails.self, from: GameDetailsStore.path("GD"))
        #expect(saved?.isFinal == false)
        #expect(saved?.details.frames.count == 1)
    }

    @Test func finishedGameIsReadOnceEver() async {
        let cache = Self.cache()
        let transport = detailsTransport()
        let store = GameDetailsStore(transport: transport, cache: cache)
        await store.refresh(gameId: "GD", finished: true)
        await store.refresh(gameId: "GD", finished: true)
        await store.follow(gameId: "GD", finished: true)
        #expect(await Self.detailsRequests(transport) == 1)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = GameDetailsStore(transport: offline, cache: cache)
        await reopened.refresh(gameId: "GD", finished: true)
        #expect(reopened.details["GD"]?.latest(participantId: 6)?.deaths == 2)
        #expect(await offline.requests.isEmpty)
    }

    @Test func statsDisabledStopsAsking() async {
        let transport = detailsTransport(statsDisabled: true)
        let store = GameDetailsStore(transport: transport, cache: Self.cache())
        await store.refresh(gameId: "GD", finished: false)
        await store.refresh(gameId: "GD", finished: false)
        #expect(store.unavailable.contains("GD"))
        #expect(await Self.detailsRequests(transport) == 1)
    }

    @Test func previewStoreNeverAsks() async {
        let details = BuildSamples.details(for: SampleData.kcSnapshot)
        let store = GameDetailsStore(preview: [SampleData.kcSnapshot.gameId: details])
        await store.refresh(gameId: SampleData.kcSnapshot.gameId, finished: false)
        #expect(store.details[SampleData.kcSnapshot.gameId] == details)
    }
}
