#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
iverilog -g2012 -s mister_cheat_tb -o "$tmp/cheat.vvp" \
  "$root/rtl/machine/cvs_cheat_engine.sv" \
  "$root/sim/cpu/mister_cheat_tb.sv"
vvp "$tmp/cheat.vvp"
