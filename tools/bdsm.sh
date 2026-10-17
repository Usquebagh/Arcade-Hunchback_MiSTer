#!/usr/bin/env bash
set -euo pipefail
core_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$core_root"
command=${1:-test}
if (($#)); then shift; fi
framework_path="${MISTER_BDSM_PATH:-$core_root/MiSTer-BDSM}"
runner="$framework_path/mister-bdsm"
if [[ ! -f "$runner" ]]; then
    cat >&2 <<EOF
MiSTer-BDSM was not found at: $framework_path
Clone https://github.com/Usquebagh/MiSTer-BDSM and set
MISTER_BDSM_PATH to that checkout, or place it at:
  $core_root/MiSTer-BDSM
EOF
    exit 2
fi
exec python3 "$runner" "$command" "$core_root" --adapter "$core_root/sim/bdsm/adapter.json" --output "$core_root/results" "$@"
