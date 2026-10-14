import Foundation
import LoLKit
import Observation

/// Frames du fil des événements et de la courbe de gold, par game (spec fonctionnalités §4, §5) : relecture du flux à pas
/// de 60 s — game terminée, ou ouverture tardive d'une game en cours —, gardée sur disque (`replays/<gameId>.json`), puis
/// chaque frame lue en direct par l'écran Détail (10 s). Le fil et la courbe se calculent dans LoLKit (`GameTimeline`,
/// `GoldSeries`). Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué (le fil raconte la game, la courbe dit
/// qui mène) ; ce store ne connaît pas les matchs.
@MainActor
@Observable
final class TimelineStore {
    /// Frames de la relecture, par game : première frame de la game, puis une par minute.
    private(set) var replayFrames: [String: [GameSnapshot]] = [:]
    /// Frames reçues en direct après l'ouverture de l'écran (mémoire seulement).
    private(set) var liveFrames: [String: [GameSnapshot]] = [:]
    /// Première frame de chaque game : le 0:00 du temps de jeu.
    private(set) var firstFrames: [String: Date] = [:]
    /// Games en cours de relecture (gabarit de la courbe et du fil).
    private(set) var replaying: Set<String> = []
    /// Games dont Riot ne fournit pas les stats (404) : plus aucune requête.
    private(set) var unavailable: Set<String> = []

    /// La relecture n'est écrite sur le disque que tous les 5 pas (le fichier grossit à chaque fenêtre), à la frame
    /// `finished` et à la sortie (annulation, erreur) ; la mémoire, elle, suit chaque pas.
    private static let saveEvery = 5

    private let client: LoLClient?
    private let cache: DiskCache?
    @ObservationIgnored private var records: [String: ReplayRecord] = [:]
    /// Numéro du dernier appel de `load` pour chaque game. L'écran annule la relecture quand sa clé change et en lance une
    /// autre aussitôt, sans attendre que la première soit sortie : la requête annulée ne rend la main qu'après coup (le
    /// rappel d'`URLSession` passe par sa file). L'appel le plus récent reprend la game ; l'ancien, au retour de sa requête,
    /// voit que son numéro n'est plus le bon et sort sans rien publier.
    @ObservationIgnored private var generations: [String: Int] = [:]

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : relectures figées (la première frame de chaque liste est le début de la game), aucune requête.
    init(preview frames: [String: [GameSnapshot]]) {
        client = nil
        cache = nil
        replayFrames = frames
        firstFrames = frames.compactMapValues { $0.first?.timestamp }
    }

    // MARK: Lectures pour les vues

    /// Toutes les frames connues de la game (relecture puis direct) ; `GameTimeline` et `GoldSeries` les remettent dans
    /// l'ordre chronologique. Tant que la game est relue, les frames du direct restent à part : la plus récente serait
    /// comparée à un pas relu bien plus ancien (un gros paquet d'événements en tête, une courbe en ligne droite) ; elles
    /// rejoignent la relecture quand elle est finie.
    func snapshots(gameId: String) -> [GameSnapshot] {
        let replay = replayFrames[gameId] ?? []
        return replaying.contains(gameId) ? replay : replay + (liveFrames[gameId] ?? [])
    }

    /// Fil de la game, dans l'ordre chronologique (l'écran l'affiche du plus récent au plus ancien) ; vide tant que la
    /// première frame n'est pas connue.
    func events(gameId: String) -> [TimelineEvent] {
        guard let first = firstFrames[gameId] else { return [] }
        return GameTimeline.events(from: snapshots(gameId: gameId), firstFrameTime: first)
    }

    /// Courbe de l'écart de gold, positive quand `teamId` mène (l'équipe de gauche de l'écran).
    func goldPoints(gameId: String, orientedTo teamId: String?) -> [GoldPoint] {
        guard let first = firstFrames[gameId] else { return [] }
        return GoldSeries.points(from: snapshots(gameId: gameId), firstFrameTime: first, orientedTo: teamId)
    }

    // MARK: Chargement

    /// Relecture de la game : le disque d'abord ; puis, sauf si elle est complète, la première frame (fenêtre sans
    /// `startingTime`) et une fenêtre par minute pleine (`ReplaySchedule`), une à une, avec une pause entre deux, en
    /// gardant la dernière frame de chacune. La mémoire suit chaque pas ; le disque est écrit tous les 5 pas, à la frame
    /// `finished` et à la sortie (une relecture interrompue reprend où elle s'était arrêtée). Game terminée : jusqu'à la
    /// frame `finished`. Game en cours : jusqu'à `LiveStatsTime.startingTime(now:)` (le flux refuse une fenêtre en avance
    /// sur la diffusion), le direct prend le relais (`append`). Une erreur réseau arrête la relecture sans rien perdre ;
    /// un 404 (stats désactivées) la clôt. Un appel plus récent pour la même game reprend la main : celui-ci s'arrête, sans
    /// rien publier, dès qu'il le constate (après chaque attente), et ne lève la marque « en cours » que si elle est encore
    /// la sienne.
    func load(gameId: String, inProgress: Bool, now: Date = Date()) async {
        guard !unavailable.contains(gameId) else { return }
        if records[gameId] == nil, let saved = cache?.load(ReplayRecord.self, from: Self.path(gameId)) {
            publish(saved, gameId: gameId)
        }
        guard let client, records[gameId]?.complete != true else { return }
        let mine = (generations[gameId] ?? 0) + 1
        generations[gameId] = mine
        replaying.insert(gameId)
        func isCurrent() -> Bool { generations[gameId] == mine }
        // Pas lus depuis la dernière écriture sur le disque : écrits à la sortie, quelle qu'elle soit.
        var unsaved = 0
        defer {
            if isCurrent() { replaying.remove(gameId) }
            if unsaved > 0, let record = records[gameId] { persist(record, gameId: gameId) }
        }
        do {
            var record: ReplayRecord
            if let known = records[gameId] {
                record = known
            } else {
                let opening = try await client.window(gameId: gameId, startingTime: nil)
                guard isCurrent(), let first = opening.firstFrameTime else { return }
                record = ReplayRecord(firstFrame: first, frames: opening.snapshots().prefix(1).map(CachedFrame.init),
                                      lastStep: nil, complete: false)
                publish(record, gameId: gameId)
                persist(record, gameId: gameId)
            }
            let until = inProgress ? LiveStatsTime.startingTime(now: now) : nil
            for step in ReplaySchedule.steps(firstFrame: record.firstFrame, after: record.lastStep, until: until) {
                try await Task.sleep(for: ReplaySchedule.pause)
                guard isCurrent() else { return }
                var window: LiveWindow?
                do {
                    window = try await client.window(gameId: gameId, startingTime: step)
                } catch LoLAPIError.noData {
                    // Fenêtre vide (début de game) : on passe au pas suivant.
                }
                guard isCurrent() else { return }
                if let last = window?.latestSnapshot() {
                    record.frames.append(CachedFrame(last))
                    record.complete = last.phase == .finished
                }
                record.lastStep = step
                publish(record, gameId: gameId)
                unsaved += 1
                if record.complete || unsaved >= Self.saveEvery {
                    persist(record, gameId: gameId)
                    unsaved = 0
                }
                if record.complete { break }
            }
        } catch LoLAPIError.statsDisabled {
            unavailable.insert(gameId)
        } catch {
            // Réseau, refus du flux, annulation (écran quitté) : la relecture reprendra à la prochaine ouverture.
        }
    }

    /// Frame lue en direct par l'écran Détail : ajoutée au fil si elle est plus récente que tout ce qu'on a déjà pour
    /// cette game (la même frame relue n'est pas ajoutée deux fois).
    func append(_ snapshot: GameSnapshot) {
        let gameId = snapshot.gameId
        let latest = [replayFrames[gameId]?.last?.timestamp, liveFrames[gameId]?.last?.timestamp].compactMap { $0 }.max()
        guard latest.map({ snapshot.timestamp > $0 }) ?? true else { return }
        liveFrames[gameId, default: []].append(snapshot)
    }

    /// Mémoire : ce que les vues lisent.
    private func publish(_ record: ReplayRecord, gameId: String) {
        records[gameId] = record
        firstFrames[gameId] = record.firstFrame
        replayFrames[gameId] = record.frames.map(\.snapshot)
    }

    /// Disque : `replays/<gameId>.json`.
    private func persist(_ record: ReplayRecord, gameId: String) {
        cache?.save(record, to: Self.path(gameId))
    }

    static func path(_ gameId: String) -> String {
        "replays/\(gameId).json"
    }
}
