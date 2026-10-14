#!/usr/bin/env bash
# Lance `swift <args>` dans LoLKit via Docker : pas besoin d'installer Swift sur Windows.
# Exemples : bash scripts/lolkit.sh test   |   bash scripts/lolkit.sh run lolkit live
# Chaque copie de travail (dépôt principal ou worktree) a son propre volume de compilation : des compilations
# lancées en parallèle depuis plusieurs worktrees ne se marchent pas dessus.
set -euo pipefail
cd "$(dirname "$0")/../LoLKit"
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"
ROOT="$(cd .. && pwd)"
if [ "$(basename "$ROOT")" = "App Esport en direct" ]; then
  VOLUME="faille-lolkit-build"
else
  VOLUME="faille-lolkit-build-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
fi
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$HOST_DIR:/LoLKit" \
  -v "$VOLUME:/LoLKit/.build" \
  -w /LoLKit \
  swift:6.2 swift "$@"
