#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
# Give every engineering image a fresh, visible identifier so the on-screen
# version cannot silently lag behind the source used for the build.
build_id="v$(date -u +%y%m%d-%H%M%S)"
printf '`define BUILD_ID "%s"\n' "$build_id" > build_id.v
image=theypsilon/quartus-lite-c5:17.0.2
mkdir -p build
if ! docker run --rm -v "$PWD":/project -w /project -u "$(id -u):$(id -g)" "$image" \
    quartus_sh --flow compile Arcade-Hunchback > build/quartus.log 2>&1; then
    grep -E "^(Error|Critical Warning)" build/quartus.log | head -30 || true
    tail -20 build/quartus.log
    exit 1
fi
grep -E "Logic utilization|Total block memory bits|Total registers|RAM Blocks" \
    output_files/Arcade-Hunchback.fit.summary || true
