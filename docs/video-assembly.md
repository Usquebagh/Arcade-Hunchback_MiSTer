# Provisional raster and composed video assembly

Expectations before implementation, 2026-10-11. Existing 2621 timing, normalized
PVI and character contracts remain the references; this document defines their
FPGA connection. This is a provisional coordinate hypothesis, not a board trace.
Kevtris v1.4 timing/counter sheet was inspected at higher resolution. Separate
U12AA/U12AB/U12CA PCK/PIXCLK circuitry has asynchronous preset/clear feedback;
counters reset by /HRST and /VRST. Propagation and PVI/display origins remain
unaudited. No simple divider substitutes for that circuit. MAME offsets (-26
horizontal, -5 vertical) are not silently added to the chip-coordinate engine.

## Scan contract

Reuse tested 312-line /16 timing. A labelled line begins on entering h=6.
Rotate h into x=0..226: h>=6 gives h-6, otherwise h+221. Lines 43..298 produce
y=0..255, one request per ce_position; other lines produce none. Visible is
provisional !blank (thus x<44 is blank). This 227x256 viewport is an integration
fixture, not the 240-pixel MAME viewport or verified CVS placement.

Delay raw line-start by two enabled master edges. The first edge after entering
line 43 lets PVI observe VRST falling and latch field state; the next prepares
row zero before the first pixel strobe at h=6. run=0 freezes timing/line-delay
state and masks consuming strobes. Downstream in-flight pixels may drain during
a pause. Reset clears delay state. A linear enabled-time oracle checks every
request/coordinate/line/visible level, frame boundaries, pauses and reset.

## Joined pixel contract

Three actual PVIs sample at edge N. At N+1 their registered pixels and accepted
x/y/visible/mode/scroll enter the actual character pipeline and shared FLAG RAM.
Output is valid at N+5 (six edges total). No previous pixel, live next coordinate
or injected sprite data may substitute. Sync levels travel through six registers
so valid output carries the accepted request's levels. Reset flushes valid;
payload holds between valid outputs. CPU PVI status side effects are preserved.
CPU SENSE/IRQ uses VRST, not composite horizontal/vertical blank. PVI IRQ remains
diagnostic; physical routing is unqualified.

## Actual-CPU composed fixture

A downloaded synthetic program initializes every used memory via actual CPU
instructions: all codes/attributes/bullets, palette, used RAM glyph, and PVI
descriptors/controls. Scan stays stopped during initialization; CPU acceptance
then stalls at a ready marker while one complete field executes. All 227x256
pixels must match independent geometry, blanking, palette and real PVI presence.
Three FF objects at (48,8), colours 0/2/4, overlap foreground and a four-pixel
bullet at x=45..48. Black presence participates. Collision must accumulate FF;
completion is 08 per chip. CPU resumes, reads FF, clears/reads 00 and reads all
three completion bytes. The stall is a fixture, not display arbitration.

## Local-ROM bootstrap

Use the authenticated parent image unchanged. An independent restricted
interpreter reads it at runtime, models its first RAM-clear loop and stops after
1024 writes. Supported semantics: absolute unconditional branch, status masks,
EOR-zero, register store, absolute indexed store and relative branch on register
nonzero. Unknown instructions fail preparation. No game bytes enter source.
Compare every actual accepted write's full address, FLAG and data with the model.
Every system RAM word must be cleared once with FLAG high and IRQ inhibited.
This is early bootstrap, not attract mode, cycle equivalence or full game boot.
Game/input/audio/PLL/integration/constraints and native unknown-state blockers
remain required. No unqualified RBF may be produced.

The strengthened scene explicitly downloads zero-valued character ROM planes
and a PROM whose low bits are (raw-pixel row XOR attribute low three bits).
For glyph pixel 7/attribute 83 this maps to palette 1; bullet uses 7, sprite mix
14. This distinguishes a one-byte graphics-address error and makes wrong-mode
ROM selection a deterministic pixel fault rather than an uninitialized read.

## Cold CPU regression and first observations

The first composed field passed. The unchanged real-ROM bootstrap failed its
first write at cycle 53060 with unknown address/data. GHDL synthesis correctly
omits upstream's simulation-only register initialization. A cold synthetic
reproduction failed at cycle 1555: EORZ R0 propagated unknown R0 into STRZ R1 and
the first indexed address. The fix makes that opcode's architectural self-XOR
result zero and sets only CC=zero; all other PSL bits retain their values. It
does not reset every register or suppress diagnostics. A strengthened cold test
checks two zero stores and an independently initialized PSL readback of 27.
Native CPU/ALU/synthesis/main-bus checks pass; the broader runtime WARNING remains.
The unchanged parent then passed all 1024 modeled writes. Those first failures
are retained; no expected byte stream was replaced with observed CPU output.

Initial scan lint/compilation rejected empty diagnostic pin connections. HRST/CBF
are now explicit outputs; lint and the linear scan baseline pass. That tool
failure is not mutation detection. Physical placement remains unqualified.

The machine's partial downloader consumes main offsets 0000..7FFF and graphics/
lookup A800..C7FF from the existing draft image. Audio/speech and score PROM,
HPS delivery, image-load qualification and physical reset/CDC remain incomplete.
The restricted bootstrap model additionally passes independently enumerated
increment/decrement orders and rejects unknown opcodes or aliased clear closure.
This is not a complete CPU emulator. No game-ROM mutation campaign is claimed:
the pinned mutation entry point has no private-ROM fixture option. The retained
synthetic cold regression proves the discovered fault without embedding ROMs.

Twelve added mutations cover scan origin/line/viewport/pause, joined valid/coords/
mode/black presence/sync, partial graphics routing, CPU collision clearing and
cold self-XOR. Total 82; passing baselines and matching assertions twice are
mandatory. All physical timing, full PVI, machine IRQ timing, audio/input and
game/Quartus gates remain open. No qualified candidate or hardware result.


## Pending-line pause regression

The first 82-fault campaign exposed a surviving scan pause-mask mutation. Its
periodic 96-enabled/5-disabled burst pattern aligned to the /16 phase and never
stopped with the delayed line strobe pending. The waveform assertions were
correct but that stimulus lacked this edge. A directed seven-clock pause now
freezes exactly that pending state; the same line-delay assertion must reject
the unmasked strobe. The original failed campaign is retained. No RTL, assertion
or expected waveform was changed to pass, and the corrected frozen campaign
must rerun before this milestone is qualified.

## First real-ROM initialization call

`hunchback.rom.startup` extends coverage through the first initialization
subroutine and its return fetch. A separate restricted instruction model reads
the authenticated unchanged image at runtime. Its supported additions are
immediate register loads, unindexed register stores, absolute call/return,
decrement-and-branch and extended writes. Unknown registers, alternate banks,
indirection and unsupported instructions reject preparation. The independent
synthetic contract manually enumerates increment/decrement store order, FLAG
transitions, extended I/O and a return, and tests rejected inputs.

The parent produces 4142 memory writes and one extended I/O write: initial 1024
system clear, 16 palette writes, 1024 attributes, 1024 codes, 1024 bullet/PVI
clear writes, 18 PVI writes and 12 PVI writes. Every accepted address, FLAG and
data matches; memory and extended I/O spaces are distinguished. The actual CPU
then fetches the modeled post-call address. Scan stays paused and interrupts
stay inhibited. This proves execution of the first initialization routine; it
does not qualify subsequent routines, polling, IRQ release, a game frame or
audio/input. Expected streams and ROMs remain private, ignored runtime fixtures.

The user permits focused checks during development. The duplicate full mutation
campaign was stopped; retain its interrupted state and the earlier failed full
campaign alongside the passing directed pause proof. The full configured
campaign remains a candidate prerequisite, rather than a development-step loop.

Two fast model mutations exercise the new oracle's unindexed register source and
call return address, bringing the configured campaign to 84. Their first run
survived because a copied adapter imported its adjacent unchanged helper instead
of the core's mutated model. The oracle and connected startup preparation now
explicitly import the frozen core's model. Keep the failed experiment; it is not
successful fault detection. Assertions and expected semantics remain unchanged.
The first store-source mutant also changed the index register, destroying loop
control and producing a model-bound ERROR. It was replaced with a data-only
selection fault; errors are not catches. The corrected source and return faults
reach `startup_oracle_order` and `startup_oracle_return` twice with passing
baselines. Return mismatch diagnostics report the expected and actual addresses.

A private bounded continuation observed four interrupt acknowledgements and
known black/coloured RGB samples while startup repeats its frame-wait loop and
writes its counter to palette entry zero. The ROM counter indicates a
128-iteration delay; the short probe does not reach its end. Raw
records contain four unknown PSL-context-save writes. An Icarus diagnostic using
`$isunknown` on task concatenations miscounted known samples; those counters are
unreliable and corrected from the raw records, not treated as a core fault or
coverage PASS. Later IRQ/polling/game/unknown-state qualification remains open.
