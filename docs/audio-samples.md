# Raw DAC sampling contract

## Independent expectations before implementation

This stage converts the two already-latched raw DAC buses into separate signed
16-bit digital samples. It does not mix channels, model discrete controls or
interpret raw latch order as measured resistor weights. The physical DAC bit
significance, four-bit latch data conflict, gain/filter/mixer, speech and channel
reference gaps in `audio-digital.md` remain required candidate blockers.

The numeric contract is deliberately explicit: `pcm8 = dac8*256 - 32768` and
`pcm4 = dac4*4096 - 32768`. Code 80/8 is digital zero; codes 00/0 are -32768 and
FF/F are 32512/28672. These are offset-binary scaling equations for raw channels,
not calibrated board voltages or a claim that the physical DAC uses this coding.
Each channel holds its value between sample strobes; no gain, normalization,
DC removal, interpolation or analog filtering is hidden in the HDL.

At the nominal integer master frequency 57272724 Hz, an accumulator adds 48000
per enabled master edge. It emits a single-edge sample strobe when the running
sum reaches/exceeds the master frequency, subtracting that frequency once.
From reset, edge `n` emits iff `floor(n*48000/57272724)` differs from the previous
edge. The first strobe is edge 1194; intervals are 1193 or 1194 master edges.
Reset clears accumulator, strobe and both outputs to zero. Sampling uses raw
DAC input values present before the accepted master edge; a DAC latch changed
on that same edge is observed by the next sample. The shared master and nominal
sample rate remain implementation contracts, not physical oscillator/CDC proof.

The test must independently compute strobes from linear edge counts, exhaust
all 256 by 16 raw combinations, check signed levels and held outputs, inject
input changes between strobes and test reset at arbitrary accumulator phases.
Important faults in cadence and either channel equation must fail designated
assertions twice. Actual CPU assembly checks must continue passing when these
outputs are connected. No raw-ROM event stream is adopted as a channel oracle.

## Executed checks

`hunchback.audio.samples` checks all 4096 raw byte/nibble pairs with an integer
linear-time oracle, input changes and arbitrary-phase resets. It passed with
zero Verilator `-Wall` findings. `hunchback.audio.assembly` now checks the same
sample contract in four-state simulation on every master edge, consuming DAC
values produced by both actual CPUs. A write coincident with a sampling edge
must not prematurely replace the old DAC value.

Four new faults (exact-wrap comparator, either signed midpoint and disconnected
byte-DAC sampler input) each fail the designated assertion twice with matching
bounded trace replays. The exact-wrap mutation fails at master test cycle
4772728; a short test of only a few sample intervals would miss this boundary.
The configured full campaign is 96; these four were proved, not the full campaign.
Affected CPU/bus, clock/memory, scan/assembly/bootstrap and lint checks passed;
17 pinned framework unit tests passed. Required native diagnostics remain WARNING.

## Private game samples and playback

The audio-enabled frozen observer now records `audio-samples.log` from actual
HDL outputs and hashes it alongside the DAC/event logs. The 450-million-edge
run observed 396 fields and all three actual audio command reads/acknowledgements.
It records 377099 stereo sample frames at nominal 48000 Hz. All 21 saved video
fields and the complete main-command timeline match the prior observation.
Compiler findings remain the same 35 unreviewed notices; no candidate is qualified.
One frozen observer limitation string still lists PCM as absent: that wording
predates the raw-sampling update. Actual raw samples are recorded and checked
here; calibrated mixing remains absent. The original report is retained and
future observer wording is corrected, without rewriting its evidence.

```sh
python3 tools/render_audio_observation.py \
  build/observe-av-samples-seed1-play/observation.json \
  --output build/observe-av-samples-seed1-play/raw-dac-preview.wav --preview
```

The renderer requires completed authenticated sample and DAC logs. Each sample
timestamp must equal the independent rational-rate expression, and its values
must match the raw DAC events strictly before that edge. It then writes byte
DAC on the left and four-bit latch on the right. This stereo layout is a
diagnostic, not the board mixer. Default output preserves the raw scaled values;
`--preview` subtracts each whole-record channel mean and applies gain 1/2.
This preview has zero clipped samples. Source/renderer/log/WAV hashes, rates,
channel ranges and transforms are recorded in the ignored sidecar JSON.

The byte-DAC channel varies from -32768 to 32256. The four-bit channel stays at
-32768 throughout these game stimuli and becomes zero in the DC-removed preview.
Its numerous register writes are not evidence of a varying real-ROM waveform.
Synthetic exhaustive level coverage does not replace missing physical/firmware
stimulus coverage for that channel. Discrete-control audio and speech are absent.

The first masked write to the still uninitialized audio work byte 1023 is 00 in
this run versus 01 in the prior same-seed hierarchy. Subsequent index values and
byte-DAC event timing/count differ (31551 writes versus 31568). No CPU, ROM, RAM
reset policy or audio input logic was changed to force this state. This is
consistent with changed randomized power-up layout across simulator hierarchies,
and reinforces the native unknown-address limitation. Both streams are retained;
neither is substituted for an independent expected waveform. The new raw sampler
has no feedback into the audio CPU or command path.

Calibrated DAC bit significance, physical four-bit data/weight conflict,
analog/discrete/mixer/filter, speech CPU/TMS5100, phase/drift/CDC, independent
firmware/channel references, MiSTer outputs and Quartus gates remain incomplete.
The WAV is a private raw-channel preview; no RBF candidate is produced.
