#!/usr/bin/env bash
set -euo pipefail

image=${1:?The framework must provide its authenticated prepared image}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output="build/observe-audio-attract-${stamp}"

python3 tools/observe_hunchback.py --image "$image" --audio \
  --require-audio-activity --cycles 450000000 --seed 1 --output "$output"
grep -q '"audio_activity_assertion": {' "$output/observation.json"
echo "PASS: authenticated input-free ROM run produced varying nonzero full-machine audio output samples"
