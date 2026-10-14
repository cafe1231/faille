#!/usr/bin/env python3
"""Contrôle du catalogue de chaînes de Faille (spec saison §3.8, P2).

Chaque littéral affiché de `App/`, `Shared/` et `Widgets/` — `Text("…")`, `Label("…")`, `Button("…")`, `Tab("…")`,
`Toggle("…")`, `.navigationTitle("…")`, `.accessibilityLabel("…")`, `.accessibilityHint("…")`,
`.accessibilityValue("…")`, `String(localized: "…")` — doit avoir une entrée dans `Resources/Localizable.xcstrings`
avec une traduction anglaise non vide ; et aucun littéral nu ne doit être passé à un composant qui prend une `String`
(`ScreenHeader("…")`, `subtitle: "…"`, `text: "…"` : affiché tel quel, jamais traduit — écrire
`String(localized: "…")`). Les interpolations `\\(…)` correspondent à n'importe quel format du catalogue (`%@`,
`%lld`, `%lf`, `%1$@`…).

Usage :
  python3 scripts/strings-check.py                 # contrôle (code de sortie 1 s'il manque quelque chose)
  python3 scripts/strings-check.py --add-missing   # ajoute les clés manquantes (anglais vide, état « new »), puis contrôle
Aucune dépendance hors de la bibliothèque standard.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "Localizable.xcstrings"
SOURCES = [ROOT / "App", ROOT / "Shared", ROOT / "Widgets"]
PREFIXES = [
    "Text(", "Label(", "Button(", "Tab(", "Toggle(", ".navigationTitle(", ".accessibilityLabel(",
    ".accessibilityHint(", ".accessibilityValue(", "String(localized:", "Picker(", "ColorPicker(",
]
# Littéral nu passé à un composant qui prend une `String` (affichée telle quelle, donc jamais traduite) : à écrire
# `String(localized: "…")`.
BARE = re.compile(r'(?:ScreenHeader\(|\bsubtitle:|\btext:)\s*"')
# Planche de la DA (outil de développement, jamais montrée à l'utilisateur).
EXCLUDED = {"App/DA/DASampler.swift"}
FORMAT = re.compile(r"%(?:\d+\$)?(?:ll[du]|l[du]|l?f|[@dsue]|\.\d+l?f)")
PLACEHOLDER = "\u0000"


def literal_at(text, start):
    """Littéral Swift qui commence au guillemet `start` ; renvoie (contenu avec interpolations remplacées, fin) ou None."""
    if text.startswith('"""', start):
        return None
    i, out = start + 1, []
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text) and text[i + 1] == "(":
            depth, i = 1, i + 2
            while i < len(text) and depth:
                if text[i] == '"':
                    end = literal_at(text, i)
                    i = end[1] if end else i + 1
                    continue
                depth += {"(": 1, ")": -1}.get(text[i], 0)
                i += 1
            out.append(PLACEHOLDER)
            continue
        if c == "\\" and i + 1 < len(text):
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        if c == "\n":
            return None
        out.append(c)
        i += 1
    return None


def literals(path):
    text = path.read_text(encoding="utf-8")
    found = []
    for prefix in PREFIXES:
        for match in re.finditer(re.escape(prefix), text):
            j = match.end()
            while j < len(text) and text[j] in " \t":
                j += 1
            if j < len(text) and text[j] == '"':
                parsed = literal_at(text, j)
                if parsed and parsed[0].strip():
                    line = text.count("\n", 0, j) + 1
                    found.append((parsed[0], f"{path.relative_to(ROOT).as_posix()}:{line}"))
    return found


def bare_literals(path):
    text = path.read_text(encoding="utf-8")
    found = []
    for m in BARE.finditer(text):
        parsed = literal_at(text, m.end() - 1)
        if parsed and parsed[0].strip() in ("", PLACEHOLDER):
            continue  # interpolation seule : valeur calculée, pas un texte écrit en dur
        found.append(f"{path.relative_to(ROOT).as_posix()}:{text.count(chr(10), 0, m.start()) + 1}")
    return found


def normalize(key):
    return FORMAT.sub(PLACEHOLDER, key.replace("%%", "%"))


def has_english(entry):
    english = entry.get("localizations", {}).get("en", {})
    unit = english.get("stringUnit")
    if unit is not None:
        return bool(unit.get("value", "").strip())
    variations = english.get("variations", {})
    units = [v.get("stringUnit", {}) for group in variations.values() for v in group.values()]
    return bool(units) and all(u.get("value", "").strip() for u in units)


def main():
    add = "--add-missing" in sys.argv
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {
        "sourceLanguage": "fr", "strings": {}, "version": "1.0"}
    entries = catalog.setdefault("strings", {})
    by_norm = {normalize(k): v for k, v in entries.items()}
    used, bare = {}, []
    for folder in SOURCES:
        if not folder.exists():
            continue
        for path in sorted(folder.rglob("*.swift")):
            if path.relative_to(ROOT).as_posix() in EXCLUDED:
                continue
            bare += bare_literals(path)
            for value, where in literals(path):
                used.setdefault(value, where)
    missing = [(v, w) for v, w in used.items() if normalize(v) not in by_norm]
    if add and missing:
        for value, _ in missing:
            key = value.replace(PLACEHOLDER, "%@")
            entries[key] = {"localizations": {"en": {"stringUnit": {"state": "new", "value": ""}}}}
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        by_norm = {normalize(k): v for k, v in entries.items()}
        missing = []
    untranslated = [(v, w) for v, w in used.items() if not has_english(by_norm.get(normalize(v), {}))]
    for value, where in missing:
        print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::absent du catalogue : {value!r}")
    for value, where in untranslated:
        if (value, where) not in missing:
            print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::sans traduction anglaise : {value!r}")
    for where in bare:
        print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::littéral nu passé à un composant "
              f"(écrire String(localized: \"…\"))")
    print(f"{len(used)} chaînes, {len(missing)} absentes, {len(untranslated)} sans anglais, {len(bare)} littéraux nus")
    return 1 if missing or untranslated or bare else 0


if __name__ == "__main__":
    sys.exit(main())
