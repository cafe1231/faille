import Foundation
import LoLKit
import Observation
import UIKit

/// Images et données Data Dragon (spec fonctionnalités §3), sans clé : version du patch d'une game, catalogues fr_FR
/// (objets, runes, sorts d'invocateur, sorts d'un champion) et icônes. Tout est gardé dans le cache disque, sous
/// `ddragon/` : la liste des versions 24 h, le reste pour toujours (une version ne change pas). Les images sont décodées
/// hors du fil principal, jamais dans un `body`. Anti-spoiler : ce store ne connaît pas les matchs ; l'appli ne lui demande
/// rien pour un match masqué (les vues qui l'appellent n'existent pas tant qu'il est masqué).
@MainActor
@Observable
final class DataDragonStore {
    /// Version Data Dragon retenue pour chaque patch du flux (`gameMetadata.patchVersion`).
    private(set) var versions: [String: String] = [:]
    /// Catalogues par version.
    private(set) var items: [String: ItemCatalog] = [:]
    private(set) var runes: [String: RuneCatalog] = [:]
    private(set) var summoners: [String: SummonerCatalog] = [:]
    /// Sorts d'un champion, par « <version>/<championId> ».
    private(set) var champions: [String: ChampionSpells] = [:]

    /// Résultat d'un chargement d'image, transporté d'un fil à l'autre : l'image n'est jamais modifiée après sa création.
    struct LoadedImage: @unchecked Sendable {
        let image: UIImage?
        /// Absente chez Data Dragon (réponse autre que 200, ou illisible) : inutile de la redemander pendant la session.
        let missing: Bool
    }

    /// Pas plus d'un essai par minute pour la liste des versions quand le réseau échoue.
    static let versionsRetry: TimeInterval = 60

    private let transport: (any HTTPTransport)?
    private let cache: DiskCache?
    private let images = NSCache<NSURL, UIImage>()
    @ObservationIgnored private var versionList: Cached<[String]>?
    @ObservationIgnored private var versionsAttempt: Date?
    @ObservationIgnored private var catalogsLoading: Set<String> = []
    @ObservationIgnored private var imageLoads: [URL: Task<LoadedImage, Never>] = [:]
    @ObservationIgnored private var missingImages: Set<URL> = []

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil (aperçus) : rien n'est lu ni écrit.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        self.transport = transport
        self.cache = cache
    }

    /// Aperçus : aucune requête, aucun fichier ; les vues montrent leurs vignettes de repli.
    static func preview() -> DataDragonStore {
        DataDragonStore(transport: nil, cache: nil)
    }

    // MARK: Version

    /// Version Data Dragon d'un patch du flux (« 16.18.819.1060 » → « 16.18.1 », `DataDragon.version(forPatch:versions:)`)
    /// sur la liste `api/versions.json`, relue au plus toutes les 24 h ; si le réseau échoue, la liste du disque, même
    /// périmée. nil si aucune liste n'a jamais pu être lue.
    func version(forPatch patch: String?, now: Date = Date()) async -> String? {
        let key = patch ?? ""
        if let known = versions[key] { return known }
        let list = await versionsList(now: now)
        guard let version = DataDragon.version(forPatch: patch, versions: list) else { return nil }
        versions[key] = version
        return version
    }

    /// Version déjà retenue pour ce patch (lecture instantanée pour un `body`) ; nil tant qu'elle n'est pas connue.
    func knownVersion(forPatch patch: String?) -> String? {
        versions[patch ?? ""]
    }

    private func versionsList(now: Date) async -> [String] {
        if versionList == nil {
            versionList = cache?.load(Cached<[String]>.self, from: DataDragon.versionsCachePath)
        }
        if let list = versionList, list.age(now: now) >= 0, list.age(now: now) < DataDragon.versionsMaxAge {
            return list.value
        }
        let mayTry = versionsAttempt.map { now.timeIntervalSince($0) >= Self.versionsRetry } ?? true
        if let transport, mayTry {
            versionsAttempt = now
            if let response = try? await transport.get(DataDragon.versionsURL, headers: [:]), response.status == 200,
               let fresh = try? DataDragon.decodeVersions(response.body), !fresh.isEmpty {
                let saved = Cached(value: fresh, fetchedAt: now)
                versionList = saved
                cache?.save(saved, to: DataDragon.versionsCachePath)
                return fresh
            }
        }
        return versionList?.value ?? []
    }

    // MARK: Catalogues

    /// Objets, runes et sorts d'invocateur d'une version : disque, sinon réseau (puis disque) ; une fois pour toutes.
    func loadCatalogs(version: String) async {
        guard !catalogsLoading.contains(version) else { return }
        catalogsLoading.insert(version)
        defer { catalogsLoading.remove(version) }
        if items[version] == nil {
            items[version] = await load(DataDragon.itemsURL(version: version)) { try ItemCatalog(json: $0) }
        }
        if runes[version] == nil {
            runes[version] = await load(DataDragon.runesURL(version: version)) { try RuneCatalog(json: $0) }
        }
        if summoners[version] == nil {
            summoners[version] = await load(DataDragon.summonerSpellsURL(version: version)) { try SummonerCatalog(json: $0) }
        }
    }

    /// Sorts (Q, W, E, R) et passif d'un champion : lus à l'ouverture de sa fiche seulement.
    func champion(version: String, championId: String) async -> ChampionSpells? {
        let key = "\(version)/\(championId)"
        if let known = champions[key] { return known }
        let url = DataDragon.championURL(version: version, championId: championId)
        guard let spells = await load(url, decode: { try ChampionSpells(json: $0) }) else { return nil }
        champions[key] = spells
        return spells
    }

    /// Un fichier de données : le disque, sinon le réseau ; décodé hors du fil principal, écrit sur disque seulement s'il
    /// se décode (un fichier abîmé ne reste jamais en cache).
    private func load<T: Sendable>(_ url: URL, decode: @escaping @Sendable (Data) throws -> T) async -> T? {
        guard let path = DataDragon.cachePath(for: url) else { return nil }
        let disk = cache
        if let saved = await Task.detached(priority: .utility, operation: {
            disk?.data(path).flatMap { try? decode($0) }
        }).value {
            return saved
        }
        guard let transport, let response = try? await transport.get(url, headers: [:]), response.status == 200 else {
            return nil
        }
        let body = response.body
        guard let fresh = await Task.detached(priority: .utility, operation: { try? decode(body) }).value else {
            return nil
        }
        cache?.write(body, to: path)
        return fresh
    }

    // MARK: Images

    /// Image déjà décodée (mémoire seulement : ni disque ni réseau) ; nil sinon.
    func cachedImage(_ url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    /// Image Data Dragon : mémoire, sinon disque, sinon réseau (puis disque) ; décodée hors du fil principal. nil si
    /// introuvable ; une image absente chez Data Dragon n'est plus redemandée pendant la session (une panne réseau, si).
    func image(_ url: URL) async -> UIImage? {
        if let hit = cachedImage(url) { return hit }
        guard !missingImages.contains(url), let path = DataDragon.cachePath(for: url) else { return nil }
        let load = imageLoads[url] ?? Task.detached(priority: .utility) {
            [transport = self.transport, cache = self.cache] in
            await Self.fetchImage(url, path: path, transport: transport, cache: cache)
        }
        imageLoads[url] = load
        let loaded = await load.value
        imageLoads[url] = nil
        if loaded.missing { missingImages.insert(url) }
        guard let image = loaded.image else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    private nonisolated static func fetchImage(_ url: URL, path: String, transport: (any HTTPTransport)?,
                                               cache: DiskCache?) async -> LoadedImage {
        if let data = cache?.data(path), let image = decode(data) {
            return LoadedImage(image: image, missing: false)
        }
        guard let transport else { return LoadedImage(image: nil, missing: false) }
        do {
            let response = try await transport.get(url, headers: [:])
            guard response.status == 200, let image = decode(response.body) else {
                return LoadedImage(image: nil, missing: true)
            }
            cache?.write(response.body, to: path)
            return LoadedImage(image: image, missing: false)
        } catch {
            return LoadedImage(image: nil, missing: false)
        }
    }

    private nonisolated static func decode(_ data: Data) -> UIImage? {
        UIImage(data: data)?.preparingForDisplay()
    }
}
