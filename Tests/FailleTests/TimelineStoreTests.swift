import Foundation
import LoLKit
import Testing
@testable import Faille

/// Début de la game de test (comme la fixture `window_pregame.json` de LoLKit) : la relecture lit 20:19, 20:20…
private let gameStart = LoLDate.parse("2026-10-04T20:18:26.892Z")!

/// Fenêtre livestats d'une frame (forme réelle de `window`, joueurs omis) : gold bleu qui monte de 500 par minute, un
/// kill bleu à partir de 20:21, `finished` à partir de 20:24.
private func windowJSON(at time: Date) -> String {
    let minute = Int(time.timeIntervalSince(gameStart) / 60)
    let state = time >= gameStart.addingTimeInterval(5 * 60) ? "finished" : "in_game"
    let team = #""inhibitors":0,"towers":0,"barons":0,"dragons":[],"participants":[]"#
    return """
    {"esportsGameId":"G1","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.18.819.1060",\
    "blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},\
    "redTeamMetadata":{"esportsTeamId":"c9","participantMetadata":[]}},\
    "frames":[{"rfc460Timestamp":"\(LoLDate.format(time))","gameState":"\(state)",\
    "blueTeam":{"totalGold":\(2500 + 500 * minute),"totalKills":\(minute >= 2 ? 1 : 0),\(team)},\
    "redTeam":{"totalGold":2500,"totalKills":0,\(team)}}]}
    """
}

/// Faux flux `window` de la game G1 : sans `startingTime`, la première frame ; sinon une frame 9 s après le début demandé.
private func replayTransport(statsDisabled: Bool = false) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        guard url.path.contains("/window/G1") else { return nil }
        if statsDisabled { return HTTPResponse(status: 404, body: Data()) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let start = query?.first { $0.name == "startingTime" }?.value.flatMap(LoLDate.parse)
        let time = start.map { $0.addingTimeInterval(9) } ?? gameStart
        return HTTPResponse(status: 200, body: Data(windowJSON(at: time).utf8))
    })
}

/// Fil et courbe de gold (spec fonctionnalités §4, §5) : relecture à pas de 60 s gardée sur disque, reprise, arrêt à la
/// frame `finished`, jamais en avance sur la diffusion, frames du direct ajoutées une seule fois.
@MainActor
@Suite(.serialized)
struct TimelineStoreTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-timeline-\(UUID().uuidString)", isDirectory: true))
    }

    private static func windowRequests(_ transport: ScriptedTransport) async -> [URL] {
        await transport.requests.filter { $0.path.contains("/window/") }
    }

    /// Attend (20 s au plus) que la relecture de G1 ait au moins `count` frames en mémoire.
    private static func waitForFrames(_ store: TimelineStore, atLeast count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while (store.replayFrames["G1"]?.count ?? 0) < count {
            try #require(ContinuousClock.now < deadline, "relecture trop lente")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func cachedFramesRoundTrip() throws {
        let snapshot = SampleData.kcSnapshot
        let data = try JSONEncoder().encode(CachedFrame(snapshot))
        #expect(try JSONDecoder().decode(CachedFrame.self, from: data).snapshot == snapshot)
    }

    @Test func scheduleReadsEveryFullMinuteFromTheStart() throws {
        let steps = ReplaySchedule.steps(firstFrame: gameStart, after: nil, until: nil)
        #expect(steps.count == ReplaySchedule.maxSteps)
        #expect(LoLDate.format(try #require(steps.first)) == "2026-10-04T20:19:00.000Z")
        #expect(LoLDate.format(steps[35]) == "2026-10-04T20:54:00.000Z")
        let resumed = ReplaySchedule.steps(firstFrame: gameStart, after: steps[10], until: steps[12])
        #expect(resumed == [steps[11], steps[12]])
        #expect(ReplaySchedule.steps(firstFrame: gameStart, after: nil, until: gameStart).isEmpty)
    }

    @Test func finishedGameIsReplayedOnceThenReadFromDisk() async throws {
        let cache = Self.cache()
        let transport = replayTransport()
        let store = TimelineStore(transport: transport, cache: cache)
        await store.load(gameId: "G1", inProgress: false)
        // Première frame, puis 20:19 … 20:23 en jeu et 20:24 `finished` : la relecture s'arrête là.
        #expect(await Self.windowRequests(transport).count == 7)
        #expect(store.replayFrames["G1"]?.count == 7)
        #expect(store.replayFrames["G1"]?.last?.phase == .finished)
        #expect(store.firstFrames["G1"] == gameStart)
        let kill = try #require(store.events(gameId: "G1").first)
        #expect(kill.kind == .kills)
        #expect(kill.teamId == "kc")
        #expect(store.goldPoints(gameId: "G1", orientedTo: "c9").last?.difference == -2_500)

        // Relecture complète : plus aucune requête, ni dans ce store ni au prochain lancement.
        await store.load(gameId: "G1", inProgress: false)
        let offline = ScriptedTransport(mode: .failing)
        let reopened = TimelineStore(transport: offline, cache: cache)
        await reopened.load(gameId: "G1", inProgress: false)
        #expect(await offline.requests.isEmpty)
        #expect(reopened.replayFrames["G1"]?.count == 7)
        #expect(await Self.windowRequests(transport).count == 7)
    }

    /// Ouverture tardive d'une game en cours : relecture jusqu'à `LiveStatsTime.startingTime(now:)` seulement (jamais en
    /// avance sur la diffusion), puis reprise au pas suivant à la prochaine ouverture.
    @Test func liveGameIsReplayedUpToTheBroadcastDelayThenResumed() async {
        let cache = Self.cache()
        let transport = replayTransport()
        let store = TimelineStore(transport: transport, cache: cache)
        // 20:22:40 : `startingTime` au plus 20:21:10 → fenêtres de 20:19, 20:20 et 20:21.
        await store.load(gameId: "G1", inProgress: true, now: gameStart.addingTimeInterval(254))
        #expect(await Self.windowRequests(transport).count == 4)
        #expect(store.replayFrames["G1"]?.count == 4)

        let reopened = TimelineStore(transport: transport, cache: cache)
        await reopened.load(gameId: "G1", inProgress: true, now: gameStart.addingTimeInterval(374))
        // 20:24:40 : reprise à 20:22, puis 20:23.
        let requests = await Self.windowRequests(transport)
        #expect(requests.count == 6)
        #expect(requests.last?.query?.contains("2026-10-04T20:23:00.000Z") == true)
        #expect(reopened.replayFrames["G1"]?.count == 6)
    }

    /// Le disque n'est écrit ni à chaque pas (le fichier grossit à chaque fenêtre) ni jamais : tous les 5 pas, puis à la
    /// sortie quand l'écran est quitté en cours de relecture, qui reprend alors où elle s'était arrêtée.
    @Test func replayIsSavedEveryFiveStepsAndOnExit() async throws {
        let cache = Self.cache()
        let transport = replayTransport()
        let store = TimelineStore(transport: transport, cache: cache)
        let task = Task { await store.load(gameId: "G1", inProgress: false) }
        func saved() -> Int? {
            cache.load(ReplayRecord.self, from: TimelineStore.path("G1"))?.frames.count
        }

        // Première frame et trois pas en mémoire : le disque n'a que la première frame.
        try await Self.waitForFrames(store, atLeast: 4)
        let memory = store.replayFrames["G1"]?.count ?? 0
        #expect(memory >= 6 || saved() == 1)

        // Cinq pas : écrits.
        try await Self.waitForFrames(store, atLeast: 6)
        #expect(saved() == store.replayFrames["G1"]?.count)

        // Écran quitté : la relecture écrit ce qu'elle a lu, quel que soit le pas.
        task.cancel()
        await task.value
        #expect(saved() == store.replayFrames["G1"]?.count)
        #expect(!store.replaying.contains("G1"))

        // Prochaine ouverture : reprise sans relire un pas, jusqu'à la frame `finished`.
        let reopened = TimelineStore(transport: transport, cache: cache)
        await reopened.load(gameId: "G1", inProgress: false)
        #expect(await Self.windowRequests(transport).count == 7)
        #expect(reopened.replayFrames["G1"]?.count == 7)
        #expect(reopened.replayFrames["G1"]?.last?.phase == .finished)
    }

    @Test func statsDisabledStopsTheReplay() async {
        let transport = replayTransport(statsDisabled: true)
        let store = TimelineStore(transport: transport, cache: Self.cache())
        await store.load(gameId: "G1", inProgress: false)
        await store.load(gameId: "G1", inProgress: false)
        #expect(store.unavailable.contains("G1"))
        #expect(await Self.windowRequests(transport).count == 1)
    }

    @Test func liveFramesAreAddedOnceAndInOrder() {
        let start = SampleData.kcGameStart
        let frames = TimelineSamples.frames(.kcLive, start: start, final: SampleData.kcSnapshot)
        let store = TimelineStore(preview: [SampleData.kcSnapshot.gameId: frames])
        store.append(SampleData.kcSnapshot)
        store.append(SampleData.kcSnapshot)
        store.append(frames[3]) // plus ancienne que la dernière : ignorée
        #expect(store.liveFrames[SampleData.kcSnapshot.gameId]?.count == 1)
        #expect(store.snapshots(gameId: SampleData.kcSnapshot.gameId).count == frames.count + 1)
    }

    /// Le scénario d'exemple raconte la game que montre l'aperçu : 7 kills contre 4, nommés, trois drakes, +2,1k.
    @Test func sampleGameTellsItsStory() {
        let gameId = SampleData.kcSnapshot.gameId
        let frames = TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart, final: SampleData.kcSnapshot)
        let store = TimelineStore(preview: [gameId: frames + [SampleData.kcSnapshot]])
        let events = store.events(gameId: gameId)
        let kills = events.filter { $0.kind == .kills }
        #expect(kills.filter { $0.teamId == "kc" }.map(\.count).reduce(0, +) == 7)
        #expect(kills.filter { $0.teamId == "c9" }.map(\.count).reduce(0, +) == 4)
        #expect(kills.allSatisfy { !$0.players.isEmpty })
        #expect(events.filter { TimelineText.isMarker($0) }.count == 3)
        #expect(store.goldPoints(gameId: gameId, orientedTo: "kc").last?.difference == 2_100)
    }

    @Test func textsNeverInventNames() {
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 1, players: ["KC Mid"]))
            == "Kill · KC Mid")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 2,
                                                players: ["KC Mid", "KC Bot"])) == "2 kills · KC Mid, KC Bot")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 2)) == "+2 kills")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 1)) == "+1 kill")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .dragon("ocean"), count: 1))
            == "Drake océan")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .baron, count: 1)) == "Baron")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .tower, count: 2)) == "2 tours")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .inhibitor, count: 1)) == "Inhibiteur")
    }

    @Test func goldCurveCrossesZeroOnTheAxis() {
        let points = [GoldPoint(gameTime: 0, difference: 0), GoldPoint(gameTime: 60, difference: -100),
                      GoldPoint(gameTime: 120, difference: 300)]
        let split = GoldChartData.withZeroCrossings(points)
        #expect(split.count == 4)
        #expect(split[2] == GoldPoint(gameTime: 75, difference: 0))
        #expect(GoldChartData.axisLimit(points) == 1_000)
        #expect(GoldChartData.axisLimit([GoldPoint(gameTime: 0, difference: -12_460)]) == 13_000)
    }
}
