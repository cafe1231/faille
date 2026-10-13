#!/usr/bin/env bash
# Génère Resources/Assets.xcassets : les icônes au trait des maquettes (grille 24, trait 1,8, rendu « template »)
# et la couleur du fond de lancement. Tracés copiés des <symbol> de docs/maquettes/ecrans-appli.html.
# Usage : bash scripts/icones.sh   (relancer après avoir modifié un tracé ci-dessous)
set -euo pipefail
cd "$(dirname "$0")/.."
CATALOG=Resources/Assets.xcassets
S='fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"'

mkdir -p "$CATALOG"
cat > "$CATALOG/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

icon() {
  local name="$1" body="$2"
  local dir="$CATALOG/icon-$name.imageset"
  mkdir -p "$dir"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>\n' "$body" > "$dir/icon-$name.svg"
  cat > "$dir/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "icon-$name.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
EOF
}

icon swords   "<path $S d=\"M14.5 17.5L3 6V3h3l11.5 11.5M13 19l6-6M16 16l4 4M19 21l2-2M14.5 6.5L18 3h3v3l-3.5 3.5M5 14l4 4M7 17l-3 3M3 19l2 2\"/>"
icon gold     "<ellipse $S cx=\"12\" cy=\"6.5\" rx=\"7\" ry=\"3\"/><path $S d=\"M5 6.5v5c0 1.7 3.1 3 7 3s7-1.3 7-3v-5M5 11.5v5c0 1.7 3.1 3 7 3s7-1.3 7-3v-5\"/>"
icon tower    "<path $S d=\"M7 21V10L5 8V4h3v2h2V4h4v2h2V4h3v4l-2 2v11zM10 21v-4h4v4\"/>"
icon inhib    "<path $S d=\"M12 3l6 9-6 9-6-9z\"/><path $S d=\"M6 12h12\"/>"
icon drake    "<path $S d=\"M12 3c1 4 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5.5 1-8.5z\"/>"
icon baron    "<path $S d=\"M12 3l8 4.5v9L12 21l-8-4.5v-9z\"/><circle $S cx=\"12\" cy=\"12\" r=\"2.5\"/>"
icon clock    "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M12 7v5l3 2\"/>"
icon live     "<circle $S cx=\"12\" cy=\"12\" r=\"2\"/><path $S d=\"M8.5 15.5a5 5 0 0 1 0-7M15.5 8.5a5 5 0 0 1 0 7M5.6 18.4a9 9 0 0 1 0-12.8M18.4 5.6a9 9 0 0 1 0 12.8\"/>"
icon eye      "<path $S d=\"M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z\"/><circle $S cx=\"12\" cy=\"12\" r=\"3\"/>"
icon eyeoff   "<path $S d=\"M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2\"/>"
icon star     "<path $S d=\"M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z\"/>"
icon star-fill "<path fill=\"#000000\" fill-opacity=\"0.25\" stroke=\"#000000\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z\"/>"
icon trophy   "<path $S d=\"M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v1a3 3 0 0 0 3 3M17 6h3v1a3 3 0 0 1-3 3\"/>"
icon settings "<circle $S cx=\"12\" cy=\"12\" r=\"3\"/><path $S d=\"M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z\"/>"
icon search   "<circle $S cx=\"11\" cy=\"11\" r=\"7\"/><path $S d=\"M20 20l-4-4\"/>"
icon back     "<path $S d=\"M19 12H5M11 6l-6 6 6 6\"/>"
icon arrow    "<path $S d=\"M5 12h14M13 6l6 6-6 6\"/>"
icon pin      "<rect $S x=\"5\" y=\"3\" width=\"14\" height=\"18\" rx=\"3\"/><path $S d=\"M9 7h6M9 17h6\"/>"
icon check    "<path $S d=\"M5 12l5 5L20 7\"/>"
icon refresh  "<path $S d=\"M20 11a8 8 0 0 0-14.9-3M4 4v4h4M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4\"/>"
icon off      "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M6 6l12 12\"/>"
icon pause    "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M10 9v6M14 9v6\"/>"

mkdir -p "$CATALOG/LaunchBackground.colorset"
cat > "$CATALOG/LaunchBackground.colorset/Contents.json" <<'EOF'
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x20",
          "green" : "0x10",
          "red" : "0x0B"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Catalogue généré : $(ls -d "$CATALOG"/icon-*.imageset | wc -l | tr -d ' ') icônes"
