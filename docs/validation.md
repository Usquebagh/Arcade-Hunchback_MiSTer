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

## Next implementation gates

1. Audit a complete S2650 core or implement one against pinned instruction and
   cycle references, including indirect/indexed addressing, alternate registers,
   PSU/PSL, page wrap, stack, sense/flag, interrupts and all bus spaces.
2. Add FLAG/bank memory, input DIP/strobe wiring, S2636 registers and raster/
   character/sprite/bullet rendering with collision and independent pixel checks.
3. Add two audio CPUs, command interrupts, DAC/discrete and TMS5100 speech with
   justified timing/numerical expectations and explicit fidelity gaps.
4. Add MiSTer framework/download/reset/input/video/audio, legal PLL, full source
   inventory/QIP dependencies, QPF/QSF/SDC, CDC and TimeQuest endpoint review.
5. Pass the complete configured suite, mutation campaign and strict Quartus gates
   from one frozen snapshot before retaining a candidate for hardware testing.
