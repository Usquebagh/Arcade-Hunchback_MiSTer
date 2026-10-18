# Status

Updated 2026-10-18. Full investigation notes:
[audio-interrupt-handover.md](audio-interrupt-handover.md); circuit analysis:
[audio-circuits.md](audio-circuits.md).

## Current state

Engineering beta (`ENGINEERING_UNQUALIFIED_NOT_A_CANDIDATE`). Last deployed
image `v261018-001032`, SHA-256
`201A2C14D014C560E438E35F3B19470DFCC2A3C5B26D74A070A6FCA0DA4A418A`, synced to
`releases/hunchback_20261017.rbf`.

| Area | Hardware state |
| --- | --- |
| Video geometry, sprites, fonts, rotation (CW/CCW) | Works (HDMI only; CRT untested) |
| Controls, coin/start, OSD reset, DIPs, cheats | Works |
| Speech (TMS5100) | Works at game start. **Silent** when the player falls |
| Sound effects (bell, walking, jumping) | **Never heard** |
| Timing | Not closed: worst setup −0.580 ns, hold +0.246 ns. The STA summary TNS (−8.542 ns) and the text report (−29.873 ns) disagree; this has not been audited |
| Candidate coverage | Nine gates SKIP (cpu, banked_memory, video, input, audio, audio_reference, game_boot, mister_integration, constraints) |

## The sound problem

Sound path: the main CPU writes a command. A **rising edge of bit 7** raises
the audio CPU IRQ. The audio S2650 takes vector `0x03`, runs the effect and
writes `SP_LAT0..3` (0x1880–0x1883, 4-bit weighted DAC) and the byte DAC
(0x1840). From the ROM, gameplay sound is almost all toggling of `SP_LAT2`.
`SP_LAT4..7` (discrete gates) are never set by this game.

The on-screen Audio Probe on hardware shows:

- command trigger: lit
- audio IRQ raised: lit
- nonzero command: lit
- **INTACK: never asserts**
- PSU-II interrupt inhibit: never set
- heartbeat: pulses

**The audio CPU never acknowledges an unmasked, valid interrupt on silicon. The
same RTL does acknowledge it in simulation.** Speech failing on a fall may have
the same cause; this is unconfirmed.

**Leading hypothesis:** a sim/silicon divergence from undefined reset state.
The S2650 async reset did not initialise control `state`, the request
handshake (`req_i`) or `intack`, and `reset_na` is held low, so the
synchronous `state <= sOPCODE` was not guaranteed to run. Commit `18d27d9`
initialises all three in the async branch. With that change the focused
authenticated-ROM replay enters the interrupt correctly (`0xe6` and `0xff`
commands, II set at INTACK). **This has not been tested on hardware.** The
magenta "eligible IRQ sample" probe bar is also untested. Read the result
like this:

- magenta lit, cyan black: the CPU reaches a sampling boundary but fails to
  enter INTACK.
- magenta black, green lit: inspect the CPU state, clock enable and the
  request/ack gate.

## Root cause found in simulation (2026-10-18, not yet hardware-confirmed)

**The S2650s never load their opcode at address 0 on hardware.** The opcode
at address 0 is meant to be loaded during reset: `sgs2650.vhd:952` forces
a read of address 0 while `reset` is high, and line 877 latches the result
with `ri <= dr`. That latch sits in the clocked branch, which only runs once
`reset_na` is high (line 847).

- Every `sim/cpu` testbench releases `reset_na`, waits 4 clocks, then
  releases `reset`, so the opcode gets loaded.
- `Arcade-Hunchback.sv:186` wires `.reset(core_reset), .reset_na(!core_reset)`,
  so both release on the same edge and the load never happens.

The first instruction executed is therefore the power-up value of `ri`. On an
FPGA that is zero, a 1-byte instruction. The audio program starts with a
3-byte branch, so the CPU starts at address 1, runs the branch's operand
bytes as opcodes and wanders out of ROM. That gives zero DAC writes and no
INTACK.

Evidence, from the actual audio RTL, the GHDL-synthesised CPU and the
authenticated ROM (diagnostic in `~/hunchback-work/diag`, not committed):

| Release | Initial state | DAC writes before `0xe6` | After | INTACK |
| --- | --- | --- | --- | --- |
| Together (MiSTer top) | zero | 0 | 0 | never |
| Together | random seeds 1–5 | 0 | 0 | yes, wrong routine |
| Together | random seeds 6–8 | 40,441 | 3,823 | yes |
| Staggered (testbenches) | zero + seeds 1–8 | 40,441 | 3,823 | yes |

40,441 equals pinned MAME's count for the same timeline. The earlier
"simulation acknowledges" results came from staggered-release benches and
randomised state. The `18d27d9` state/`req_i`/`intack` initialisation is
in all of these runs and does not fix it.

The main and speech CPUs share the same reset wiring, so they also skip their
opcode at address 0. They appear to survive it, since the game and its
start-of-game speech run, but their startup is not as designed either.

**Proposed fix (awaiting approval, since it is an RTL change):** in the top
level, hold `reset` at least 4 clocks after `reset_na` releases, matching the
testbenches. Add a zero-init, top-level-ordered reset regression. Then
hardware-test it.

## Ruled out (don't revisit without new evidence)

| Hypothesis | Evidence |
| --- | --- |
| Mixer drops the 4-bit DAC | RTL read: `nibble_mix` summed ungated, matches schematic |
| Gain too low | Was real (0.8% FS), fixed; still silent |
| DC offset railing the mix | Was real, fixed by `cvs_audio_dc_blocker` before the saturating sum; still silent |
| Discrete circuits missing | Implemented in `cvs_discrete_audio.sv`; the game never gates them |
| Audio ROM at wrong download offset | MRA layout verified: `6c.sdp1` lands at 0x8000 |
| Audio CPU not running/clocked/in reset | Probe: fetching, address moving, CE and SENSE running |
| PSU-II masking | Probe: II never set |
| Command never sent | Probe: trigger and nonzero command lit |
| Command latch not reset | Disproved; the startup writes `0x40`/`0x3f` are legitimate |

## Open questions

1. Does the staggered reset release (above) make INTACK assert and produce
   sound on hardware? `18d27d9` alone does not, even in simulation.
2. Why does speech work at start but not on a fall?
3. Schematic `SP_D0` vs MAME bit 7 (0x1880–3) / bit 0 (0x1884–7) for the
   latch data bit. Unresolved; no physical measurement.
4. ICL8038 frequency cannot be derived from the schematic (the current
   value is an estimate). It is irrelevant unless the game uses it.
5. The timing report discrepancy, then timing closure.

## Lessons that cost the most time

- Stale binaries: verify the card SHA-256 and the OSD build ID every time.
- More than one `hunchback*` RBF in `_Arcade/cores/` loads the wrong core.
- The ~10 s climb intro after start: scripted tests must wait past field ~700
  and prove the player sprite moves before trusting any input.
- A sim PASS that encodes the same assumption as the RTL proves nothing. Check
  idle states, and check that the trace covers the moment the behaviour
  happens.
