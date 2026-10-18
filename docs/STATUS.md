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

1. Does `18d27d9` make INTACK assert on hardware? This is the primary next step.
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
