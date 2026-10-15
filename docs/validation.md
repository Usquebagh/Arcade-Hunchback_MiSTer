# Validation scope

The standalone digital audio bus and actual audio CPU have exhaustive decode/data
and directed clock/IRQ/RAM/signature baselines. Six added sound faults each hit
their designated assertion twice; the full configured campaign is now 90 and is
deferred until a frozen candidate. Analog/speech/connected audio and the physical
latch-data-bit/reference gaps remain required. See [audio digital boundary](audio-digital.md).

The user permits a lighter development workflow: focused checks and retained bug
regressions during implementation, with the full configured regression/mutation
campaign and Quartus gates reserved for a frozen candidate. The duplicate full
campaign after the directed scan-pause repair was interrupted deliberately. The
earlier full campaign proved 81 faults but had one surviving pause mutation; the
corrected directed pause then detected that fault twice in a targeted run. This
is not an all-82 current-snapshot mutation qualification.

The long actual-ROM diagnostic now retains title/game-field and scripted-input
observations with randomized power-up seeds. Its reset IRQ-counter bug has a
retained checkpoint assertion and seeded reproduction. These observations are
not a candidate or an independent game-reference PASS. See [ROM diagnostic](rom-observation.md).

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

## Provisional video and vblank CPU milestone, 2026-10-11

New checks `hunchback.video.timing.312`/`.317` compare every master edge against
an independent linear-time waveform oracle over two frames, run stalls and an
arbitrary-phase reset. The .317 check is now classified as synthetic parameter
stress coverage; 312 is the supported datasheet/board expectation.
`hunchback.video.irq` exercises the pending event latch
and all 1024 five-event blank/ack histories. `hunchback.video.cpu` connects the
actual synthesized VHDL CPU, actual SV memory/clock/timing/IRQ and a downloaded
synthetic program. It verifies PSU outside/inside blank, vector 03 ISR status,
HALT resume and two-frame rearm at fixed raster deadlines. Tool failures,
fixture noncompletion and timeouts remain ERROR, not successful mutation catches.

The first VS decode failed both profiles' continuous oracle at master cycle
41247, despite retaining the total VS width. Its wrap gap is now fixed and
retained as a deliberate mutation. All corrected focused baselines and lint
passed. See [video expectations, observations and gaps](video-timing.md).
The campaign adds ten faults (34 total); every fault still requires its exact
designated assertion twice. The generic framework is unchanged; its unit tests
are rerun after the core-specific connected adapter gains a video mode.

These tests establish a provisional timing/CPU boundary, not visible game video.
The initial 317 reading was a blurred-digit interpretation, corrected to 312
after the user's glyph comparison and waveform cross-check. It is no longer a
reference-conflict blocker; no HDL or test assertions changed. Original CVS pixel
clocks/display counters, arbitration, S2636 objects/register side effects,
character/bullet drawing, colour lookup and collisions remain unqualified.
The required video coverage blocker remains, as do physical input/audio/game/
MiSTer/PLL/constraint gaps and native CPU startup WARNING. Candidate preflight
must continue to block without invoking Quartus or producing an RBF.

## S2636 object/status and three-chip CPU milestone, 2026-10-11

Affected banked memory, main bus/connected, native CPU and fixed memory baselines
passed before new wiring. `hunchback.s2636.objects` implements an independent
geometric expanded-bit oracle, analytic duplicate starts and all six collision
pairs. It checks all objects/scales, zero-colour presence, zero-pattern completion,
read-clear/readonly/alias rules, VRLE/IRQ, field/line/last-line sampling, held pixels
and simultaneous read/event/ack contracts. Seventeen complete synthetic fields
are sampled pixel by pixel, with retained RTL/reference pixel diagnostics.

`hunchback.s2636.cpu` compiles the actual VHDL CPU and actual SV FLAG memory plus
three object/status engines. A downloaded synthetic program initializes every
used register through CPU instructions and produces eighteen expected readbacks,
checking chip selection, FLAG-high character isolation, VRLE/completion read-clear
and independently specified sampled pixels. Normalized scan timing and an IRQ to
resume HALT are fixtures, not physical board phase/IRQ claims. These baselines
and unsuppressed Verilator lint passed; Icarus indexed-array sensitivity notices
were individually reviewed and are retained, with all other findings blocking.

The first alias-test bookkeeping error and unsupported Icarus break statements
were classified FAIL/ERROR and corrected in the harness; they do not count as
mutation detection. The strengthened event-retention cases passed. Sixteen new
faults bring the campaign to fifty; each must hit its designated assertion twice.
The unchanged generic framework's unit tests are rerun for connected-adapter work.

Full PVI grid/score/sound/ADC and physical bus timing remain incomplete, as do
mid-object size changes, chip timing/origins, display arbitration, CVS characters/
bullets/colour mixer and cross-chip/background/bullet collisions. Native CPU
startup WARNING and required subsystem/physical input/audio/game/MiSTer/PLL/
constraint gaps remain. No functional game frame, ROM boot or Quartus candidate
is established by a synthetic sprite image. See [S2636 details](s2636.md).

## Normalized character/bullet/mixer milestone, 2026-10-11

`hunchback.memory.display` checks every actual shared RAM display word, independent
CPU state, held reads and simultaneous CPU forwarding. `hunchback.video.character`
uses an independent geometric decoder with five complete fields, every attribute/
raw-pixel/presence combination, bullet position, sprite nibble and palette byte.
Valid bubbles, back-to-back metadata, blanking, reset flush/retention and new
collision events during clear are retained regressions. Original HDL and oracle
implement a documented pinned-MAME compatibility boundary, not a completed
physical PAL/display-clock reproduction.

`hunchback.video.character.cpu` executes the actual synthesized VHDL CPU with
actual FLAG memory and renderer. CPU instructions initialize codes, attributes,
palette, bullets and distinct glyph pages. The fixture checks 192 pixels and
actual CPU collision FF/00 read-clear signatures after a HALT/IRQ resume. Raster,
sprite pixels and IRQ are explicit fixtures. There is no fake memory or mock CPU.

Twenty added mutations bring the configured campaign to 70 faults, each requiring
its designated assertion twice. Earlier compile/selection errors remain errors,
not mutation catches. Full PVI, board phases/origins, PAL equivalence, arbitration,
Quartus RAM inference, stars/effects, game boot, input/audio, integration and
timing gates remain incomplete. Required WARNING/SKIP still blocks every RBF.

## Provisional composed assembly and early bootstrap, 2026-10-11

`hunchback.video.scan` compares every request/coordinate/line strobe with an
independent enabled-time oracle over two 312-line frames, pauses and reset.
`hunchback.video.assembly` executes actual VHDL CPU and actual shared SV RAM,
scan, three PVIs and character pipeline. All 58112 normalized pixels, six-edge
valid/sync alignment, black presence, foreground/bullet collisions and five CPU
collision/completion readbacks match an independently specified synthetic scene.
The scan window/origin and CPU stall are explicit fixtures, not board timing.

The initial unchanged-ROM test failed its first RAM write with unknown state.
A cold synthetic reproducer retained that bug; the narrow EORZ R0 fix preserves
non-CC PSL and avoids simulation-only reset assumptions. The corrected local
parent then matched all 1024 independently modeled clear writes. Its restricted
oracle has separate increment/decrement/order and malformed-fixture contract
checks. Game bytes and generated expected streams remain ignored. This is early
bootstrap coverage; full game/attract/reference gaps remain required.

Twelve new faults bring the configured campaign to 82. Every fault must reproduce
its designated assertion twice. Generic framework remains pinned/unchanged;
unit tests run for connected-adapter work. Required native startup WARNING and
physical video/PAL/PVI/input/audio/game/MiSTer/PLL/constraint gaps still block RBF.
See [assembly expectations, regressions and remaining coverage](video-assembly.md).

## Connected digital audio milestone, 2026-10-11

`hunchback.audio.assembly` executes both actual VHDL CPUs with actual main/video
and audio SV memories. Five main commands under both FLAG states produce exactly
two audio IRQ/RETE entries, command reads and RAM/DAC signatures. Independent
ready stalls and neighboring auxiliary image isolation are checked. Two new
wiring faults each fail the designated assertion twice; the full configured
campaign is now 92 and was not rerun in full. Focused affected baselines and
block lint passed; required native unknown-state diagnostics remain WARNING.

The optional private connected-ROM diagnostic observes three real command
events/reads/acknowledgements during 450 million master edges. All 21 retained
fields match the prior frozen main-only observation. These are observations and
regression comparisons, not independent full-game/audio references. The native
audio trace retains six unknown RAM writes and two unknown indexed addresses.
No power-up initialization was added. Analog/PCM/speech, physical oscillator/CDC,
channel references and MiSTer/Quartus gates remain incomplete. See
[expectations, fault proofs and limits](audio-assembly.md).

## Raw DAC sampling milestone, 2026-10-11

`hunchback.audio.samples` independently checks rational 48k strobes, all 4096
raw channel level pairs, hold, input changes and arbitrary-phase reset. The
actual dual-CPU check verifies the connected sample outputs on every edge.
Four new faults reproduce designated assertions twice; the full configured
campaign is 96 and was not rerun. Focused affected baselines and lint passed.

An authenticated private game sample log renders 377099 stereo frames after
independent cadence/scaling validation against actual DAC events. The preview
uses explicit mean removal and half gain; its four-bit channel is constant
under these stimuli. A changed masked initial audio phase bit and different
byte-DAC event timing are retained, reinforcing power-up/reference limitations.
Raw scaling and a preview do not qualify physical gain/filter/mixing, discrete
audio or speech. All native unknown-state/MiSTer/Quartus blockers remain. See
[raw sample expectations and preview scope](audio-samples.md).

## Speech digital boundary and audio audit, 2026-10-12

`hunchback.speech.bus` exhausts decode/program protection, payload/status/control
values, pointer loads, serial bit order/wrap and declared ready/reset/forwarding
priorities. `hunchback.speech.cpu` executes the actual CPU with downloaded ROM,
17 independent device-write signatures and actual serial memory consumption.
The external CTL read bit must not be replaced by a raw busy flag. Eight new
faults reproduce designated assertions twice; the full configured campaign is
104 and remains deferred. Focused affected checks and lint passed.

A frozen unchanged-ROM probe reaches speech address/control/PDC writes under
explicit external status/SENSE fixtures, without consuming speech bits or
generating voice. Native unknown-state, physical bus/protocol, LPC/voice,
three-CPU machine, analog and MiSTer/Quartus gates remain incomplete. The
authenticated game bus audit separately shows only zero four-bit/discrete
write data under the executed stimuli; no decoder change activates that path.
See [speech expectations and limitations](speech-digital.md) and
[pin/wiring audit](audio-wiring.md).

## TMS normalized command controller, 2026-10-12

Standalone command checks now cover PDC edge selection, CTL directions and
read-bit/dummy/serial handshakes. A separate actual S2650 assembly verifies
eight firmware status signatures, two starts/one reset, shared CTL2/8 and PDC
polarity, /192 and a stalled talk-output read. External datapath talk status is
still synthetic. Five new faults reproduce their assertions twice; an earlier
noncompiling request mutation remains an excluded ERROR. Full configured
regression and 109 mutations remain deferred. The pinned runner is unchanged,
and all 17 framework units pass. See [expectations and coverage](tms5100-control.md).
TMC0281 frame/coefficients/LPC/stop/drain/voice, physical timing, three-CPU
machine, analog/audio references, native runtime, MiSTer and Quartus gates
remain incomplete. No RBF candidate is qualified by these command checks.

## TMC0281 frames, numeric ROMs and lattice, 2026-10-12

Frame checks cover all energy/pitch/repeat values, legal K indices, atomic
4/10/28/49-bit frames and upper-K retention. The actual serial-memory assembly
checks downloaded synthetic frames, wrap, pointer-write priority/retry and
issued-response reset. Numeric ROMs have exhaustive address/sign tests with
shared pinned upstream numeric facts. The serial lattice passes an independent
wide-integer recurrence, all energy/excitation input pairs, changing captured
parameters, every reset position and exhaustive PCM quantization. Eleven new
faults reproduce twice across the two components. A corrected ROM-inversion
designation is separately proved; the initial mismatched campaign is FAILED.
Configured mutations total 120; complete regression/campaign and Quartus are
deferred. The generator's cadence/interpolation/LFSR/chirp/stop-drain and voice,
three-CPU connection and MiSTer top/project remain missing, with all existing
physical/native/runtime/analog/reference blockers retained. The installed
Quartus Docker image exists and the clean local Template_MiSTer framework is
identified at 3ea1134cf05d62c2b1db30362277a823d739ced2; neither is an integration
or timing PASS. See [frame expectations](tms5100-frames.md) and
[lattice expectations](tms5100-lattice.md).

## MiSTer reset status and Hunchback DSW mapping, 2026-10-15

The MiSTer template reserves status bit 0 for `R[0]` reset. The wrapper's
Coin A option previously overlapped that bit, and its menu coin/lives byte and
cabinet/bonus/registration byte were connected to the opposite machine inputs:
MAME reads DSW3 at extended port 6 and DSW2 at port 7. Options now use bits 1
through 11, and the corrected port order is checked at the actual machine
boundary. The shell behavioral check also covers index-zero download reset,
external/menu/user reset, two-clock release and active-low joystick mapping.
The full configured smoke suite passes on this change. Four targeted faults
(ROM-ready reset gating, joystick polarity, DSW order and status-bit overlap)
each fail their designated assertion twice. RTL lint and CPU synthesis pass;
the existing native CPU unknown-value diagnostic remains WARNING. Physical
DIP positions/polarity, HPS protocol, PLL, board video/audio/game reference,
the complete mutation campaign and Quartus timing remain required blockers;
this change does not qualify an RBF candidate. See [MiSTer shell expectations](mister-shell.md).
