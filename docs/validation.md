# Validation scope

Initial synthetic checks cover reset assertion/release/qualification, main/audio
enable count/cadence/phase/reset restart, all 20 KiB mapped program addresses,
one-edge read latency, ROM write protection, all 1 KiB system RAM addresses and
four mirrors, read hold and declared read/write/download collision forwarding.
MRA testing independently calculates every main address and verifies auxiliary
regions, CRC metadata and padding. Real parent-ROM size/CRC/SHA-1 verification is
a fixture/layout check, not a boot test.

Mutation requirements: held reset -> `reset_release`; main divider fault ->
`main_cadence`; lost program-page bits -> `rom_byte`; lost system-RAM mirror ->
`ram_mirror`. The runner requires two matching assertion failures and retains
bounded VCD replay. Wrong EPROM quarter in the MRA -> `mra_program_byte`; wrong
quarter in private image preparation -> `prepare_program_byte`. Both are tested
with synthetic bytes and require no game archive. Add new faults as
CPU/video/input/audio are implemented.

## Initial evidence, 2026-10-11

The installed Ubuntu 24.04 WSL toolchain executed the synthetic baseline and
unsuppressed lint successfully. The local parent ROM fixture passed authentication
and layout checks. All six deliberate faults then reached their designated
assertion twice with identical cycle/expected/observed evidence. The initial
held-reset mutation replaced the shift register with a constant and triggered an
unused-signal compilation warning instead of a runtime assertion. It was recorded
as an invalid experiment, then corrected to shift in a permanent one without
weakening lint. The corrected mutation was caught by `reset_release`.

The pinned MiSTer-BDSM framework's 17 unit tests passed. No runner code was changed.
The installed Quartus container image was verified present:
`sha256:42e6c06da3af486f9cfea74acb5c1af9b63a77d0f16e3bf093215216e209b7ad`.
This does not mean Quartus compiled or timing passed: the synthesis project does
not exist at this stage. Full regression/candidate requests must expose the
required missing coverage; Quartus and RBF generation remain blocked.

Full regression intentionally reports required SKIP for CPU, FLAG-banked memory,
video/S2636/collision, input, audio/speech/reference, ROM boot, MiSTer integration
and constraint review. Candidate preflight must return incomplete with no RBF
artifact. Verilator is predominantly two-state and does not establish X/Z,
metastability, CDC, physical PLL, analog circuit fidelity or hardware usability.
Actual tool versions and run results are retained privately in `results/`.
The v1.4 references additionally support a standalone U15L pin decoder. Its
32 possible input combinations have explicit expectations; a reversed address
group mutation must fail `pal_decode` twice. Full banked memory remains pending.

## Next implementation gates

1. Audit a complete S2650 core or implement one against pinned instruction and
   cycle references, including indirect/indexed addressing, alternate registers,
   PSU/PSL, page wrap, stack, sense/flag, interrupts and all bus spaces.
2. Complete display-side FLAG/bank memory, physical input DIP/strobe wiring,
   S2636 registers and raster/
   character/sprite/bullet rendering with collision and independent pixel checks.
3. Add two audio CPUs, command interrupts, DAC/discrete and TMS5100 speech with
   justified timing/numerical expectations and explicit fidelity gaps.
4. Add MiSTer framework/download/reset/input/video/audio, legal PLL, full source
   inventory/QIP dependencies, QPF/QSF/SDC, CDC and TimeQuest endpoint review.
5. Pass the complete configured suite, mutation campaign and strict Quartus gates
   from one frozen snapshot before retaining a candidate for hardware testing.

## Connected main CPU milestone, 2026-10-11

The existing banked-memory and native CPU bus baselines passed before changes.
`hunchback.main.bus` now checks all 256 raw input addresses, read-only bank latch
side effects, request acceptance, scroll inversion, collision command pulses,
audio bit-7 edges, memory/I/O isolation and held responses. The connected check
uses GHDL synthesis of the actual adapted CPU plus actual SV ROM, FLAG RAM, I/O
and clock divider in Icarus. It downloads a synthetic program, initializes status
in software and checks 24 expected CPU writes including 12 actual RAM readbacks,
character pages, FLAG views, raw inputs, sense, collision/audio/video commands
and external sprite routing. A 250-master-edge readiness stall and /96 request
qualification are checked. The tests are deterministic; seed is recorded but
does not select random stimuli. Four-state comparisons reject unknown signatures;
this is not a complete CPU unknown-state audit.

GHDL's generated Verilog uses `int` as a bare port identifier, a SystemVerilog
keyword. The adapter escapes that identifier only; no CPU logic is patched or
committed as generated Verilog. Native synthesis diagnostics and Icarus -Wall
findings remain candidate-blocking if unreviewed. SystemVerilog bus/memory modules
also have unsuppressed Verilator -Wall lint. Native CPU diagnostics remain a
required WARNING; physical synthesis and timing are still absent.

The first connected-stall experiment captured the live address before the
ready-low combinational mux had settled and failed `connected_stall`. The harness
now waits for that mux to settle before capturing the pending address, as the
native CPU bench already does. The assertion remains and no HDL was changed to
make it pass. The new program and exhaustive bus checks passed after correction.
Five new deliberate faults target I/O page bits, write-latched banking, repeated
audio triggers, live response-space selection and disconnected CPU FLAG. The
total campaign contains 24 faults, each requiring the designated assertion twice.
The initial disconnected-FLAG designation expected a later signature failure;
both runs instead failed the earlier sprite-write assertion at master cycle 5103
(expected 155, observed 180). That campaign entry correctly remained FAIL despite
detecting the fault. Its designation is now `connected_sprite_write`, reflecting
the first wrong external transaction; no assertion or HDL was changed. The
original report is retained and the final campaign must rerun from the revised
frozen snapshot.

Raw port compatibility does not establish physical input polarity/bit mapping,
the uncertain three-versus-four-bit port decode or MiSTer controls. Sprite routing
does not implement S2636 registers or graphics. Command latches do not implement
sound or collisions. Required coverage gaps remain; no game boot or RBF candidate
is claimed. Reports retain source/dependency hashes, versions and observations.
