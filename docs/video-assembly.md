# CVS raster and composed video assembly

Existing 2621 timing, normalized PVI and character contracts remain the
references; this document defines their FPGA connection. The output uses the
schematic-derived active pixel count, while exact board propagation phases remain
unmeasured.
Kevtris v1.4 timing/counter sheet was inspected at higher resolution. U12AA/U12AB
are clocked from 14.318 MHz and form PCK/PCK2 by divide-by-three; U12CA
rephases PIXCLK using /HRST. Display counters clear on /HRST and count PIXCLK.
The VRST field anchor
is line 43; the output viewport starts at line 51, an eight-line delta. MAME's
S2636 API uses `set_offsets(y, x)`, and the CVS driver calls `set_offsets(-5,
-26)`. Thus Y=-5 and X=-26. MAME anchors PVI rendering at visible y=8; the joined
core anchors its PVI counter at VRST y=0, eight lines earlier, so its effective
Y offset remains +3. The
actual PVI line counter advances through the eight cropped lines; adding eight
prevents object rows from being consumed before the first composed pixel. This
translation is checked in the joined PVI/character/collision scene; physical
counter propagation and phases remain unmeasured.

## Scan contract

Reuse tested 312-line /16 sync timing. A labelled line begins on entering h=6.
The 2621 emits 227 timing slots, and HRST covers h=6..49 (44 slots). The separate
display clock is 14.318 MHz / 3; outside HRST, 183 slots × 16 master clocks / 12
master clocks per pixel = 244 active pixels. The PVI and character pipeline both
consume this same native `pixel_x` counter (0..243); only the S2636 object start
applies MAME's X=-26 translation. Lines 51..298 select source rows
y=8..255 from the 256-line field, matching MAME's vertical crop. MAME's x=0..239
is retained as software presentation metadata only; no resampling maps it onto
the board raster. `cvs_rotation_raster` inserts only the low-DE separator required
by `screen_rotate`, so the source remains 244 pixels wide and the rotated buffer
is 248x244. The precise edge phase and analog blanking against U12/U9 remain
physical measurement gaps.

Delay raw line-start by two enabled master edges. The first edge after entering
line 43 lets PVI observe VRST falling and latch field state; subsequent edges
prepare row state before active PIXCLK samples begin at HRST release. Output crop begins at row 8 and
does not change the PVI field origin. run=0 freezes timing/line-delay
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

The full-machine wrapper exposes the scan's active-pixel enable separately from
its viewport-limited character request. The MiSTer shell delays the pixel CE by
six register stages to align with the N+5 RGB/DE/sync output. An independent field
oracle checks the /12 cadence and 244-pixel line width. This checks the synchronous
FPGA model; board-level setup/hold phase and analog display origins remain open.

## Actual-CPU composed fixture

A downloaded synthetic program initializes every used memory via actual CPU
instructions: all codes/attributes/bullets, palette, used RAM glyph, and PVI
descriptors/controls. Scan stays stopped during initialization; CPU acceptance
then stalls at a ready marker while one complete field executes. All 244x248
native source pixels must match independent geometry, palette and real PVI presence.
Three FF objects with programmed VC=8 render from screen line 11 with the fixed
PVI Y origin, colours 0/2/4, overlap foreground and a four-pixel
bullet at x=45..48. Black presence participates. Collision must accumulate FF;
completion is 08 per chip. CPU resumes, reads FF, clears/reads 00 and reads all
three completion bytes. The stall is a fixture, not display arbitration.

The OSD no longer exposes experimental sprite trims or layer blanking switches.
The CVS/MAME-compatible X=-26 and field-relative Y=+3 translations are fixed in
the renderer and feed both displayed object pixels and collision detection.

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
