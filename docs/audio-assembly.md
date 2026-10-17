# Main/video and digital audio assembly

## Expectations recorded before implementation

The provisional assembly must use both actual S2650 CPUs, actual main FLAG RAM,
video assembly and audio bus. Main program bytes remain at image 0000..7FFF;
audio program bytes at 8000..8FFF must reach audio ROM addresses 000..FFF.
Other auxiliary image windows must not overwrite the audio program. Speech is
not implemented. The command byte and single-edge event connect directly from
main I/O to the audio bus. No FLAG predicate, extra command queue or fake CPU
may replace this path.

These are synchronous FPGA/MAME compatibility contracts, not board clock/CDC
measurements. Main and audio enables are /96 and /192 of the shared master.
External audio SENSE remains a fixture. Separate physical oscillators, analog
sound, speech, physical decode and calibrated channel references remain gaps.

The independent synthetic sequence is 40,9B,DA,40,C6 through actual main WRTC
instructions: five latch updates, only two rising-bit-7 interrupts. The first
pair uses FLAG=0, the second FLAG=1. Actual audio interrupt code must read 9B
then C6, write those bytes to its RAM and byte DAC and acknowledge twice. DA
updates the command without retriggering. Instructions delay the next update
until after the first audio command read. Audio ready is stalled at that read;
main ready is stalled before the second triggering write. Neither rejected
transfer may take effect. RAM is initialized only by CPU instructions.

The test checks actual accepted transfers and retained read data, two real IRQ
entries/returns, main/audio cadence, final latches and event counts. ROM bytes
are synthetic and independent of game firmware. Existing main/video and audio
baselines remain required; this test adds the connection, not new board accuracy.

## Executed synthetic connection

`cvs_av_machine` composes the existing main/video machine with the actual audio
CPU/bus. It retains the main debug/pixel ports and exposes actual audio bus,
IRQ and DAC/discrete signals. A second clock-enable instance uses the same
master/reset contract; it is not a second physical oscillator model.

`hunchback.audio.assembly` passed in four-state Icarus with both synthesized
actual VHDL CPUs and actual SV memories. The first attempt had a testbench
wildcard-port elaboration error; that remains an ERROR, not a simulated failure
or mutation catch. The corrected test passed. Its hostile neighboring download
bytes do not overwrite audio code. Both ready stalls retain the expected event
counts and data, and the repeated-high command produces no extra IRQ.

Two new mutations corrupt the command's low bit and incorrectly filter the
audio trigger by main FLAG. Each fails its designated assertion twice after
passing baselines, with matching bounded trace replays in disposable framework
snapshots. The configured full campaign is now 92; only these two were run at
this milestone. A first targeted launch lacked adapter helper files and remained
an ERROR; the corrected launch supplies the complete adapter directory.

Affected main/audio bus and actual-CPU tests, clock, memory, native CPU bus,
scan, existing complete synthetic video field, authenticated ROM bootstrap and
block lint passed. The actual mixed hierarchy compiles with Icarus `-Wall`; only
the existing individually reviewed PVI full-array sensitivity notices are
accepted. The broad native CPU runtime diagnostic remains required WARNING.
All 17 pinned framework unit tests passed after running from its package root.

## Connected private game observation

Run in WSL, retaining all outputs in ignored `build/`:

```sh
python3 tools/observe_hunchback.py hunchbak.zip --audio --controls \
  --cycles 450000000 --seed 1 --output build/observe-av-seed1-play
```

This frozen diagnostic executes unchanged authenticated main and audio ROMs.
It checks the same independent 4143-write initialization checkpoint before
enabling scan. The subsequent game and audio behaviour remains OBSERVED_ONLY.
The external 380 Hz SENSE fixture uses integer rational timing against the
nominal master; no analog oscillator is synthesized or qualified.

The 450-million-edge run observed 396 started fields/396 main acknowledgements,
three audio command events/acknowledgements/command reads, 31568 byte-DAC writes,
121564 four-bit latch writes and 91180 discrete-control writes. All 21 retained
fields and the complete 12-write main-command timeline match the prior main/video
observation. This is a frozen regression comparison, not an independent frame
or sound reference. Coin/start/right/jump sampling remains four/four/30/six.

The real main CPU sent E6, FF and CB at cycles 194624900, 203716292 and 353434436.
The connected audio CPU read those bytes at 194629988, 203720996 and 353439524.
Both main FLAG states appear in these events; none was filtered by RAM bank.
The observer retains separate accepted bus and command/ACK/DAC event logs with
hashes. IRQ pin values during reset are excluded from both counters. Short
seed-2 checks passed the retained reset counter assertion in both observer
profiles. One seed's full connected game observation does not qualify all
firmware paths, startup states or phase/drift conditions.

The audio-enabled Verilator build retains 35 unreviewed findings, including the
generated CPU's C++ keyword `int` notice in addition to the prior unused-bit and
PVI shadowed-name findings. They are not suppressed or candidate-qualified.

## Native unknown-state investigation

An ignored four-state instruction/read trace reproduces the prior 1.5-million-
edge three-pair audio-ROM probe: six unknown RAM writes and no unknown DAC/
discrete write values. It also exposes two unknown indexed read addresses.

Four writes save uninitialized bytes 100C/100D into 100F/1010 and restore them;
the preceding actual reads establish their origin. Byte 1023 is also read before
initialization: a mask retains an unknown low bit, arithmetic/indexing then
produces an unknown ROM read address, and the index is stored back. The actual
bus returns FF for that unresolved address in this simulation; this is not
evidence of a defined physical read. Known output latch values therefore do
not establish independence from power-up state. RAM/CPU initialization was not
changed. These remain limitations requiring concrete-state/path and board
reference audits, not a reason to reset all work RAM or discard diagnostics.

Analog/discrete synthesis, calibrated PCM, resistor/DAC bit significance,
speech CPU/TMS5100, physical oscillators/CDC, complete CPU/game/video references,
MiSTer integration and Quartus constraint/timing gates remain incomplete. No
RBF candidate or audible output is produced by this milestone.

The following [raw-sampling milestone](audio-samples.md) adds separate PCM ports
and a private preview without qualifying physical channel gain/mixing or removing
these blockers. Its changed power-up phase observation is retained separately.

## Full-ROM audio output and current engineering mix

The MRA loads `6c.sdp1` (CRC `f9ba2854`) at image offset `0x8000`; the audio
CPU window is `0x8000..0x8fff`, matching the 4 KiB ROM image. The authenticated
local archive run through the actual main, audio and speech machine hierarchy
completed 450,000,000 master cycles and 396 video fields. The audio CPU made
397,200 writes including 39,719 byte-DAC writes, 158,880 four-bit latch writes
and 119,157 discrete-control writes. The input-free trace had no audio command
IRQ/read events. At 48 kHz, the top-level engineering sum produced 377,099
nonzero samples, 123 distinct levels, and a range of -32768..-1. This is a
digital activity regression on the authenticated game ROM, not proof of an
audible hardware output or calibrated sound.

The first top-level mix included the raw four-bit latch at equal gain. In the
observed attract state, DAC4 code zero was mapped by the provisional
offset-binary sampler to -32768, clipping the mixed output to the negative rail
for most samples. The engineering mix now uses the byte DAC plus speech PCM;
the DAC4 latch remains available for diagnostics until its physical weighting
and analog path are established. The shell regression forces a non-clipped
byte-DAC sample alongside DAC4=-32768 and checks both MiSTer audio channels.

OSD reset is declared as `R[0],Reset;`. The MiSTer documentation specifies
`R{Index}` and the current template uses `R[0]`; other official cores still use
`R0`, so the legacy spelling is not a sufficient explanation for the hardware
failure. `status[0]` enters the asynchronous reset assertion and `cvs_reset`
stretches it for 1,140,000 system clocks (20 ms), then synchronizes release.
The shell regression asserts a momentary status pulse resets all three CPUs
and restarts the main CPU at its reset vector while leaving ROM-load state
separate. The deployed `v261017-03-RESET-PROBE` image holds a white video marker
for 100,000,000 system clocks after status bit 0 is observed, to distinguish
HPS status delivery from reset-chain behavior on hardware.
