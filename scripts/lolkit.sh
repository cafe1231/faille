#!/usr/bin/env bash
# Lance `swift <args>` dans LoLKit via Docker : pas besoin d'installer Swift sur Windows.
# Exemples : bash scripts/lolkit.sh test   |   bash scripts/lolkit.sh run lolkit live
set -euo pipefail
cd "$(dirname "$0")/../LoLKit"
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "$HOST_DIR:/LoLKit" \
  -v faille-lolkit-build:/LoLKit/.build \
  -w /LoLKit \
  swift:6.2 swift "$@"
