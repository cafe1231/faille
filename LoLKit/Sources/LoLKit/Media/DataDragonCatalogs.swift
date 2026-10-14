import Foundation

/// Objets (`data/fr_FR/item.json`) : nom, image et balise par id.
public struct ItemCatalog: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let id: Int
        public let name: String
        /// Fichier d'image (`image.full`, ex. « 1054.png ») ; l'URL vient de `DataDragon.itemImage`.
        public let image: String
        /// Balise (tag Data Dragon « Trinket ») : affichée à part, après les 6 objets.
        public let isTrinket: Bool

        public init(id: Int, name: String, image: String, isTrinket: Bool) {
            self.id = id
            self.name = name
            self.image = image
            self.isTrinket = isTrinket
        }
    }

    /// Les objets d'un joueur, balise à part (ligne « 6 objets + balise » du Détail).
    public struct Inventory: Sendable, Equatable {
        /// Objets dans l'ordre du flux, sans la balise.
        public let items: [Int]
        public let trinket: Int?

        public init(items: [Int], trinket: Int?) {
            self.items = items
            self.trinket = trinket
        }
    }

    public let version: String?
    public let items: [Int: Item]

    public init(version: String?, items: [Int: Item]) {
        self.version = version
        self.items = items
    }

    /// Lit `item.json`. Un objet illisible est ignoré (décodage tolérant).
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        var items: [Int: Item] = [:]
        for (key, entry) in file.data {
            guard let id = Int(key), let raw = entry.value else { continue }
            items[id] = Item(id: id, name: raw.name, image: raw.image.full, isTrinket: raw.tags?.contains("Trinket") ?? false)
        }
        self.init(version: file.version, items: items)
    }

    public func item(_ id: Int) -> Item? { items[id] }

    /// Sépare la balise des autres objets ; un id inconnu du catalogue reste un objet.
    public func inventory(_ ids: [Int]) -> Inventory {
        let trinket = ids.first { items[$0]?.isTrinket == true }
        return Inventory(items: ids.filter { $0 != trinket }, trinket: trinket)
    }

    private struct File: Decodable {
        let version: String?
        let data: [String: Tolerant<Raw>]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        let name: String
        let image: Image
        let tags: [String]?
    }
}

/// Runes et arbres (`data/fr_FR/runesReforged.json`) : nom et icône par id.
public struct RuneCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let id: Int
        public let key: String
        public let name: String
        /// Chemin d'icône (ex. « perk-images/Styles/7204_Resolve.png ») ; l'URL vient de `DataDragon.runeIcon`.
        public let icon: String

        public init(id: Int, key: String, name: String, icon: String) {
            self.id = id
            self.key = key
            self.name = name
            self.icon = icon
        }
    }

    /// Arbres (`styleId`, `subStyleId` de `perkMetadata`).
    public let styles: [Int: Entry]
    /// Runes (`perks` de `perkMetadata` ; la première est la rune principale).
    public let runes: [Int: Entry]

    public init(styles: [Int: Entry], runes: [Int: Entry]) {
        self.styles = styles
        self.runes = runes
    }

    /// Lit `runesReforged.json`. Un arbre illisible est ignoré.
    public init(json: Data) throws {
        let styles = try JSONDecoder().decode([Tolerant<Style>].self, from: json).compactMap(\.value)
        var styleEntries: [Int: Entry] = [:]
        var runeEntries: [Int: Entry] = [:]
        for style in styles {
            styleEntries[style.id] = Entry(id: style.id, key: style.key, name: style.name, icon: style.icon)
            for rune in style.slots.flatMap(\.runes) {
                runeEntries[rune.id] = Entry(id: rune.id, key: rune.key, name: rune.name, icon: rune.icon)
            }
        }
        self.init(styles: styleEntries, runes: runeEntries)
    }

    public func style(_ id: Int) -> Entry? { styles[id] }

    public func rune(_ id: Int) -> Entry? { runes[id] }

    private struct Style: Decodable {
        struct Slot: Decodable { let runes: [Rune] }
        struct Rune: Decodable {
            let id: Int
            let key: String
            let icon: String
            let name: String
        }

        let id: Int
        let key: String
        let icon: String
        let name: String
        let slots: [Slot]
    }
}

/// Sorts d'invocateur (`data/fr_FR/summoner.json`) : nom et image par id Data Dragon (« SummonerFlash »).
public struct SummonerCatalog: Sendable, Equatable {
    public struct Spell: Sendable, Equatable {
        /// Id Data Dragon, ex. « SummonerFlash » ; l'URL vient de `DataDragon.summonerSpellImage`.
        public let id: String
        public let name: String
        public let image: String

        public init(id: String, name: String, image: String) {
            self.id = id
            self.name = name
            self.image = image
        }
    }

    public let spells: [String: Spell]

    public init(spells: [String: Spell]) {
        self.spells = spells
    }

    /// Lit `summoner.json`. Un sort illisible est ignoré.
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        var spells: [String: Spell] = [:]
        for (key, entry) in file.data {
            guard let raw = entry.value else { continue }
            spells[key] = Spell(id: raw.id, name: raw.name, image: raw.image.full)
        }
        self.init(spells: spells)
    }

    public func spell(_ id: String) -> Spell? { spells[id] }

    private struct File: Decodable {
        let data: [String: Tolerant<Raw>]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        let id: String
        let name: String
        let image: Image
    }
}

/// Sorts d'un champion (`data/fr_FR/champion/<id>.json`) : Q, W, E, R et passif, pour l'ordre de montée.
public struct ChampionSpells: Sendable, Equatable {
    public struct Ability: Sendable, Equatable {
        public let name: String
        /// Fichier d'image (`image.full`) ; URL : `DataDragon.spellImage` (sorts) ou `DataDragon.passiveImage` (passif).
        public let image: String

        public init(name: String, image: String) {
            self.name = name
            self.image = image
        }
    }

    public let championId: String
    public let name: String
    /// Q, W, E, R, dans cet ordre.
    public let spells: [Ability]
    public let passive: Ability?

    public init(championId: String, name: String, spells: [Ability], passive: Ability?) {
        self.championId = championId
        self.name = name
        self.spells = spells
        self.passive = passive
    }

    /// Lit `champion/<id>.json` (un seul champion dans `data`).
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        guard let champion = file.data.values.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Aucun champion dans le fichier"))
        }
        self.init(championId: champion.id, name: champion.name,
                  spells: champion.spells.map { Ability(name: $0.name, image: $0.image.full) },
                  passive: champion.passive.map { Ability(name: $0.name, image: $0.image.full) })
    }

    /// Sort d'une lettre de l'ordre de montée (`abilities` du flux `details` : « Q », « W », « E » ou « R ») ; nil sinon.
    public func spell(forAbility letter: String) -> Ability? {
        guard let index = ["Q", "W", "E", "R"].firstIndex(of: letter.uppercased()), spells.indices.contains(index) else {
            return nil
        }
        return spells[index]
    }

    private struct File: Decodable {
        let data: [String: Raw]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        struct Spell: Decodable {
            let name: String
            let image: Image
        }

        let id: String
        let name: String
        let spells: [Spell]
        let passive: Spell?
    }
}

/// Valeur décodée si possible, sinon nil : un élément illisible n'empêche pas de lire les autres.
private struct Tolerant<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
