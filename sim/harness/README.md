# Stage 1 sound bench

Run from the repository root (Python 3 + numpy, GHDL, Verilator, make, g++):

```sh
python3 tools/sound_bench.py --rom /absolute/path/hunchbak.zip \
  --timeline sim/harness/timelines/smoke.csv \
  --output results/sound-smoke --duration 7
python3 tools/sound_bench.py --rom /absolute/path/hunchbak.zip \
  --timeline sim/harness/timelines/smoke.csv \
  --output results/sound-reset --duration 7 --reset-stress 8
```

Outputs must use a new directory under ignored `results/`. The runner reuses
`prepare_hunchback.validated/assemble` and its manifest; no alternate ROM parser.
It freezes and hashes build inputs, synthesizes the actual VHDL S2650 through
GHDL (only escaping the Verilog keyword `int`, like `check_connected.py`), then
builds the actual audio modules with `-j 32`. Cached builds live under
`results/sound-bench-build/`; source, tool or build-option changes invalidate them.
`-Wall` findings are retained in `compile.log` and the manifest. Warnings in the
new SV bench fail the build; existing RTL/vendor warnings remain visible.
The C++ driver compiles with `-Wall -Wextra -Werror`.

The first invocation benchmarks single-thread versus two-thread execution on
the fixed seven-second smoke timeline, verifies all five captures are identical,
and selects the faster configuration. `--threads N` benchmarks single-thread
versus N (two when N=1), then explicitly uses N. Measurements are cached by
source/tool identity, printed and included in each manifest. Build time is
excluded from reported simulation wall time.

`--x-random --seed N` uses `--x-initial unique --x-assign unique`,
`context.randReset(2)` and `+verilator+seed+N`. `--reset-stress N` additionally
runs seeds 1..N and retains every seed's captures/manifest. A failure is retained
in `reset-stress.json` and returns nonzero; no RTL is repaired by this harness.
Reset covers the 4096 download edges, then 576..5760 additional edges (3..30
192-edge audio CE periods, above the CPU's three-clock minimum). The PRNG also
chooses a release offset of 1..8728 ps in the low half-cycle.
**Coverage limitation:** the real shared reset resets the CE divider too.
Consequently the first audio CE is always active edge 191; this wiring cannot
randomize CE phase relative to release. The report explicitly records this gap.
Eight requested seeds are a smoke campaign; the contract calls for at least 32.

Edge zero denotes the first active master posedge after release; timeline rows
apply at `round(seconds * 57272724)`. Reported seconds use that same integer
edge origin, independent of simulator context time. `audio_cpu_cycle` counts
actual `ce_audio_step` pulses, at 57272724/192 = **298295.4375 Hz**; it does not
count the board oscillator. SENSE toggles after 75360 master edges. Command
updates preserve the main bus's rising-bit-7 rule. In particular smoke `0xff`
follows `0xe6`, so it generates no new trigger/IRQ.

The INTACK deadline is **9 audio CE periods (30.1714 us)** after a triggering
command: at most six steps to finish the longest indirect instruction, then
opcode acceptance and the registered INTER acknowledgement (two), plus one
period conservatively covering the command/IRQ register stages. This is an
unmasked, ready=1 CPU latency bound, not a bound on arbitrary masked firmware.
Masked or missing acknowledgements still fail; they are never excused by the
checker. Only rising INTACK edges qualify.

DAC events capture accepted memory writes before the active edge, including
full write bytes for all addresses in the shared contract. WAVs sample
pre-edge `sample_ce` and PCM values as synchronous consumers do (including the
last strobe at the duration boundary). `mix.wav` uses the real output stage,
with speech tied to zero; raw DAC WAVs are unfiltered `pcm8/pcm4`. No preview
gain or DC removal is applied. The runner reads all WAVs back with Python
`wave`, checks mono/16-bit/48 kHz and exact frame counts, and records per-second
RMS in signed-16-bit units, command event counts and interrupt times.

This is an RTL observation harness, not a MAME comparison PASS, native unknown
state proof, analog calibration, physical clock/CDC check or RBF candidate gate.
No ROM bytes or generated captures belong in Git.
