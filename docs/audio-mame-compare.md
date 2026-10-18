# Sound section versus MAME: harness contract

Status: **expectations recorded before implementation.** Nothing here has run yet.

## Purpose and reference class

The harness compares the RTL sound section (audio S2650, audio bus/latches,
raw samples, discrete/DAC mix, output stage) with MAME `hunchbak` for the same
sequence of sound commands. Reference class: **MAME compatibility** at the
pinned revision `c806573e925ce00fe3e8d8fe417eba63f83275ce`. If the installed
MAME binary differs, record its version and treat it as a separate, weaker
reference until the CVS driver and the S2650/DAC devices are confirmed unchanged.

What a PASS means: the audio CPU program reacts to each command the way MAME
does. It then writes the same DAC values in the same order with matching
timing, and the resulting waveform has the same shape. What a PASS does
**not** mean:

- **Not analog accuracy.** MAME's CVS discrete sound is a placeholder and its
  DAC levels are uncalibrated.
- **Not the schematic `SP_D0` versus bit-7 question.** Both sides use bit 7
  for 0x1880–0x1883, so agreement on that is not evidence.
- **Not the hardware INTACK fault.** Simulation already acknowledges the
  interrupt. Only the reset-stress mode below targets that fault class.

## Inputs

A **command timeline**: a list of `(time, byte)` command writes. It comes from
one of two places:

- **Directed:** a hand-written list. Each command of interest is followed by
  enough silence for its effect to finish (default 3 s).
- **Replay:** captured from MAME during a scripted game. The script runs coin,
  start, the ~10 s climb intro, then right/jump to the bell. It must show that
  the player sprite moves before it trusts the input.

Both implementations receive the same bytes at the same times. Each derives
its interrupt from its **own** rule. The RTL rule (`cvs_main_io.sv`) is: a
trigger fires on a rising edge of bit 7 against the previous command, and the
IRQ clears on the rising edge of INTACK. MAME's rule must be read from the
pinned `cvs.cpp` and written in this document before the comparison is
trusted. If the rules differ, that difference is itself a finding. Do not
make the bench copy MAME's rule.

ROM: the user's local `hunchbak.zip`, authenticated by `tools/rom_manifest.json`.
No ROM bytes, captures or WAVs enter Git.

## Outputs per run (under ignored `results/`)

- `dac-events.csv`: `seconds, audio_cpu_cycle, address, value`, one line per
  write to 0x1840, 0x1880–0x1883 or 0x1884–0x1887. Both sides produce this
  file. MAME's comes from a Lua write tap on the audio CPU program space.
- `irq-events.csv` (RTL only): `seconds, command, trigger, irq, intack, ii`.
- `mix.wav`: 48 kHz, mono, signed 16-bit. RTL: `cvs_audio_output.audio_pcm`
  with speech connected (stage 2) or held at zero (stage 1). MAME: `-wavwrite`.
- `dac8.wav`, `dac4.wav` (RTL only): the raw `pcm8`/`pcm4` channels.
- `manifest.json`: source hashes, ROM hash, MAME version, seed, timeline,
  Verilator flags, wall time.

## Scoring (`score.json` plus a summary table)

1. **Event match (primary, exact).** Split both event streams at each
   command. Per command, the sequence of `(address, value)` must match exactly.
   Inter-write intervals are converted to seconds with each side's documented
   audio-CPU clock and compared. Every per-command interval ratio is reported.
   A constant clock-ratio offset is listed as a separate finding, never
   quietly divided out.
2. **Waveform match (secondary).** Remove DC and normalise RMS per clip
   (absolute gain is not a reference). Align the clips by cross-correlation
   inside a ±20 ms window, then report:
   - onset error and duration error (ms);
   - correlation of the 10 ms RMS envelopes;
   - log-spectral distance between STFTs (46 ms frames);
   - dominant-pitch tracking error in cents.
3. **Silence check.** For every command where MAME produces sound, the RTL
   clip's RMS must be above a floor. A silent clip fails outright, whatever
   its other metrics say. This is the actual hardware symptom, so it must be
   impossible to mask.

Thresholds are set before any RTL comparison, from a **noise-floor** run:
MAME against itself at a different sample rate and with throttling on. They
are written into this document and never loosened to make a run pass.

## Mutation proofs (each must fail its designated metric twice)

| Mutant | Must fail |
| --- | --- |
| `dac4` latch takes bit 0 instead of bit 7 | event match |
| `dac4[2]` stuck at 0 | event match and silence check for the SP_LAT2 effects |
| IRQ never raised (trigger tied low) | event match and silence check |
| Audio CE halved | event interval ratio |
| `nibble_weighted` branch weights reversed | waveform spectral distance |

## Reset stress (targets the hardware INTACK fault class)

The same bench runs with Verilator `--x-initial unique --x-assign unique`
over at least 32 seeds of `+verilator+seed`. Each seed also uses a randomised
reset length and release phase relative to the audio CE. Every command with
bit 7 rising must produce INTACK within a bounded number of audio-CPU cycles.
A seed that never acknowledges is a reproduction and becomes a permanent
regression. This approximates power-up and synthesis divergence; it does not
prove what silicon does.

## Stages

1. Audio CPU only (speech PCM tied to zero); directed bell/walk/jump commands.
2. Speech machine connected; commands include the fall-off-edge speech.
3. Replay timelines from scripted MAME gameplay.
4. Register as a BDSM check (`hunchback.audio.mame_compare`). It is
   local-only because it needs the ROM and MAME.
