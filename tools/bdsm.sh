#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command=${1:-test}
if (($#)); then shift; fi
exec python3 MiSTer-BDSM/mister-bdsm "$command" "$PWD" --adapter "$PWD/sim/bdsm/adapter.json" --output "$PWD/results" "$@"
