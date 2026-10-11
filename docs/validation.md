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
