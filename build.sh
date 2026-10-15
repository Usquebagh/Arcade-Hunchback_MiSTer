#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
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
