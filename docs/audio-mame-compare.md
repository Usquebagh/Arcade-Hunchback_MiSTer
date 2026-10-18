# Sound section versus MAME: harness contract

Status: **expectations recorded before implementation.** Integration calibration
and comparison results are recorded below (2026-10-18).

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

## Reference version

Pinned-source findings (from `cvs.cpp` at `c806573e`, read 2026-10-18):

- The audio IRQ is asserted when bit 7 rises against the previous command
  (`audio_command_w_sync`) and cleared by the INTACK handler, which returns
  vector `0x03`. This is the same rule as the RTL.
- Writes of an unchanged command are ignored.
- Both sound CPUs run at 14.318181 MHz / 16.
- 0x1880–0x1883 take bit 7.
- The 4-bit DAC is `DAC_4BIT_R2R` with **D0 as the LSB**.
  `cvs_discrete_audio.sv` gives `dac4[0]` the *strongest* branch (12k), from
  the schematic. That is a significance conflict, so the waveform metrics
  will report it until the schematic reading is rechecked.
- 0x1840 writes also retune placeholder beeper 2, and 0x1884–0x1887 drive
  placeholder beepers.

The Ubuntu **MAME 0.264** package is not a valid stand-in for the pin:

- Its driver has a level-sensitive audio IRQ.
- Its main CPU runs at /16; the pin uses /8.
- Its speech CPU SENSE uses a ROM-clock hack.
- Its `s2650.cpp` differs by about 1,078 lines, including cycle counts and
  interrupt-check placement.

The pinned revision is built as a single-driver binary in WSL. 0.264 runs
are only for testing the tooling.

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

## Integration time origin and calibration (2026-10-18)

Directed MAME starts at `machine.time=0`: the main CPU is held by the HALT
read overlay with interrupts inhibited before its first instruction. The Lua
scheduler applies commands at absolute machine seconds, verified by
`start_seconds=0`, PC=0 and zero unexpected main commands. The RTL bench has
no main CPU. Its driver schedules edge zero at the first active posedge after
reset release, after downloading ROM and holding reset. Both use elapsed time
from machine start/reset release; no game initialization interval is added.
The default RTL prelude is 4096 download plus 576 reset edges (about 81.6 us),
excluded from WAVs and event timestamps. Physical release to logical edge zero
is less than one master period; reset pin sequencing does not enter the runner's
time calculation. Commands are rounded to the nearest 57,272,724 Hz master edge.
`timeline.csv` records these applied times, matching the manifest. The scorer
accepts only half a master period plus 1 ns CSV rounding against REF command
times and records `timeline_deltas_seconds`; event segmentation remains at REF
command boundaries. This does not compensate clock rate or interrupt latency.

Each WAV must still have exactly `round(manifest.duration_seconds * rate)`
frames. Across captures, a difference of at most 10 ms is accepted. Both event
and waveform comparisons stop at the common span, the minimum WAV frame count
divided by sample rate. `score.json.capture_span` records both lengths, signed
DUT-minus-REF difference and common duration. A larger difference is
NOT_SCORABLE; commands outside the common span are rejected. This accommodates
the pinned MAME WAV writer's extra sample without padding or resampling.

Noise-floor captures used the supplied pinned binary (`0.289 (unknown)`) and
seven-second directed `sim/harness/timelines/smoke.csv`: `results/mame-a` used
`-nothrottle`, `results/mame-b` used `-throttle`. Both used 48 kHz because the
scorer rejects unequal sample rates and does no resampling. Each completed
from 0 to 7 s, wrote 226,078 DAC events and 336,001 mono samples
(7.000020833333333 s). The WAV and DAC-event files were bit-identical across
throttle variants. The binary hash is retained in each manifest; the version
string alone does not authenticate the source pin.

Calibration used only those references, before any RTL comparison:

```sh
python3 tools/score_sound.py --calibrate results/mame-a results/mame-b \
  --output results/thresholds-calibrated.json
```

All observed errors were zero. The exact `3 * max(observed, numeric_floor)`
rule produced interval-ratio and envelope-correlation error limits of `3e-9`;
lag/onset/duration limits of `3e-6` ms; spectral distance `3e-6` dB; and pitch
error `3e-6` cents. These establish only repeatability of this deterministic
reference pair, not an empirical allowance for sample-rate changes, analog
noise or physical hardware. The tracked `sound_thresholds.json` is unchanged;
the lead owns any decision to adopt this local calibration.

The same seven-second RTL run (`results/rtl`, one simulation thread, revision
`unknown` with source hashes) completed in 78.68 s with 336,000 samples,
zero DAC events and no INTACK for `0xe6`. Its runner returned FAIL (exit 1).
The calibrated comparison (`results/score.json`) also returned FAIL (exit 1):

| Command | REF writes | RTL writes | Event match | Mix silence failure |
| --- | ---: | ---: | --- | --- |
| 0x40 | 407 | 0 | FAIL | no |
| 0x3f | 38,018 | 0 | FAIL | no |
| 0xe6 | 64,295 | 0 | FAIL | no |
| 0xff | 121,342 | 0 | FAIL | no |

The accepted span was exactly 7 s; DUT-minus-REF length was -1 sample
(-20.833333 us). Applied RTL command deltas were -3.492 ns, -7.683 ns, 0 and
0. The reference's pre-first-command writes remain outside command segments.

**Open discrepancy:** the expected mixed-WAV silence failure did not occur.
Both raw RTL DAC channels were constant -32768 (zero AC energy), but the real
mixed output ranged from -2574 to 2849, with whole-capture AC RMS 1551.684 in
PCM16 units. In the audible REF `0xe6` segment, REF/DUT AC RMS were
0.03653/0.04735 full scale. Thus `mix.wav` is not silent by the existing -50 dBFS
check, despite zero DAC writes. No audio samples, silence definition or event
assertions were changed to force the expected failure label. Event matching
and waveform differences still reject this capture. This mix activity remains
an RTL/audio investigation outside the harness integration scope.

The 20 scorer unit tests passed, including positive/negative 10 ms bounds,
one sample beyond either bound, common-tail exclusion and master-edge rounding.
Five disposable scorer mutations (reject exactly 10 ms, accept over 10 ms,
compare the longer tail, ignore event mismatch, ignore silence) each failed
their designated regression twice with assertion failures and no tool errors.
Existing five output-mutation classes also remained detected twice; these are
scorer proofs, not actual RTL mutation proofs. No reset files, RTL or tracked
thresholds were edited, and no candidate/hardware/analog claim follows.
