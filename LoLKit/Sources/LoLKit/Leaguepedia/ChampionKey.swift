/// Clé de comparaison d'un nom de champion, commune aux noms de Leaguepedia (« Lee Sin », « K'Sante », « Renata Glasc »,
/// « Wukong ») et aux ids Data Dragon du flux (« LeeSin », « KSante », « Renata », « MonkeyKing »).
public enum ChampionKey {
    /// Les trois champions dont l'id Data Dragon n'est pas le nom (vérifié sur `champion.json` 16.17.1 et 16.20.1).
    static let aliases = ["wukong": "monkeyking", "renataglasc": "renata", "nunuwillump": "nunu"]

    /// Minuscules, lettres et chiffres ASCII seulement (sans espace, apostrophe, point ni « & »), puis alias :
    /// « LeBlanc » et « Leblanc » → « leblanc » ; « Wukong » → « monkeyking » ; « Dr. Mundo » → « drmundo ».
    public static func normalized(_ name: String) -> String {
        let compact = String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        return aliases[compact] ?? compact
    }
}
