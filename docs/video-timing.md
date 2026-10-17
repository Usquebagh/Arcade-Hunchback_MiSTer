# Provisional CVS video timing boundary

Expectations recorded before HDL implementation, 2026-10-11. This is a
datasheet-derived digital timing subset with declared FPGA reset/enable semantics.
It is not a qualified CVS raster or a full pin-compatible 2621 replacement.

Primary reference: Signetics, Universal Sync Generator (PAL) 2621, preliminary
specification, printed pages 3-6 (five-page scan including cover), downloaded from
https://amigan.yatho.com/2621USG.pdf. SHA-256:
`89600ad2677f3c2a92bb7d7ad76030d2b6fef98b856193af39a95832881ce8ac`.
The scan and inspection crops remain private and ignored. The supported vertical
total is 312: the waveform explicitly labels 311,312,1,2. An initial reading of
the blurred block label as 317 was overstated as a source conflict. On the user's
2026-10-11 correction, comparison with the diagram's other degraded 2 glyphs
supports reading it as 312 too. The default HDL was already 312 and is unchanged.
The 317 configuration is retained solely as a synthetic parameter stress test,
with its existing check ID; it is not an alternate CVS or 2621 timing hypothesis.

Kevtris v1.4 schematic, main-board timing sheet (PDF page 5), shows X1=14.318 MHz,
U13AA/U13AB producing 3.579 MHz into U13D/2621 CLK. The separate U12AA/U12AB
74S112s are clocked from the 14.318 MHz net (not the 3.579 MHz 2621 clock).
Their JK/NAND feedback forms the PCK/PCK2 divide-by-three chain; U12CA samples
that phase on /HRST to produce the line-aligned PIXCLK. The 2621 PCK pin is
unconnected. The 74LS161 display counters clear on /HRST and count PIXCLK.

This gives 227 sync-generator slots per line but 244 active display pixel periods:
HRST covers 44 slots, leaving 183; each slot spans 16 master clocks, while
PIXCLK is one pulse per 12 master clocks, so 183*16/12=244. The count is an
integer because the active interval is phase-aligned by HRST. MAME's 0..239
visible X range is a software crop, not the board's raw pixel count. The FPGA
now models the /12 pixel enable and native 244-wide active span; its exact edge
phase relative to the board's flip-flop propagation and analog blanking still
needs measurement. The model does not infer that the raster is a complete
physical PCK/PIXCLK implementation.

The sync-generator model samples one slot every 16 master edges, using the
existing assumed master=4*14.318181 MHz. Horizontal labels are 0..226. A line
counter labelled 1..V_LINES advances on entering horizontal position 6, matching
the VRST edge annotations. The display path separately emits one pixel enable
every 12 master clocks outside HRST, yielding 244 active X positions per line.
Independently transcribed waveform intervals are:

| Signal | Asserted interval, inclusive start/exclusive end |
| --- | --- |
| HRST | horizontal [6,50) |
| internal HS, exposed as negative hsync | horizontal [11,28) |
| horizontal CBF | horizontal [31,40) |
| VRST | lines [1,43) |
| internal VS, exposed as negative vsync | line 11 position 28 through line 15 position 11 |
| provisional CBLNK | HRST OR VRST |

Separate HS/VS are internal waveform interpretations for future digital output;
CSYNC, odd/even output, CK2/CK4 pin phase and color-burst suppression are excluded.
CBLNK's OR interpretation and all edge associations need independent board audit.
No graphics viewport, pixel output, collision, S2636 register logic, interlaced
output or analog propagation model is implied. MAME uses a 256x256 bitmap, visible
x=0..239/y=8..255, 50 Hz and a nominal 2500 us vblank; it does not provide these
raw timing constants. At the assumed board clock, the 312-line model computes
50.5414 Hz rather than exact MAME 50 Hz. This remains a clock/board validation
question, not a disagreement about the datasheet's line count.

Synchronous FPGA reset establishes h=0, line=V_LINES and divider=0; after six
position ticks it enters line 1. This is a deterministic preframe convention,
not the 2621 test-reset pin's documented counter-zero behaviour. `run=0` freezes
the divider/counters and deasserts consuming strobes. All outputs are synchronous
clock-domain logic; no output is used as a generated clock. `line_start` and
`frame_start` qualify the consuming master edge, not a level-wide reset pulse.

Planned independent test: derive h and line from a linear position-tick index,
compare every master edge across multiple frames at 312 and in the synthetic
parameter stress configuration, exercise run
stalls and reset at a nonzero phase, count frame/line periods and pulse widths,
and check all transcribed intervals. Tests must not infer expected constants
from the HDL. Faults target divider phase, horizontal/vertical wrap, vertical
reset width and blanking combination; each must fail its designated assertion
twice. New timing has no baseline until those checks execute successfully.

Required video coverage remains incomplete until board clocks/phases,
display arbitration, character/sprite/bullet pixels,
collision logic, vblank/interrupt CPU connection and MiSTer output have meaningful
checks. PLL/CDC/Quartus constraints and hardware measurement remain separate gates.

## Vblank interrupt expectations, before implementation

Pinned MAME ties main SENSE to screen vblank, asserts the main interrupt at its
rising edge, and clears it on interrupt acknowledgement, returning vector 03.
The planned synchronous `cvs_vblank_irq` holds a pending interrupt until intack,
does not retrigger during one high interval, and rearms after low. If a new edge
and acknowledgement coincide, the new event wins (explicit FPGA contract; no
claim of physical simultaneity ordering). Reset clears pending/history.

The connected synthetic test will use the actual VHDL CPU, actual SV memory,
clock enables, provisional 312 timing and pending latch. CPU reset is held until
the initial blank interval ends, a test-fixture sequencing choice. A downloaded
bootstrap branches over an ISR at vector 03; software initializes status and
halts. Expected stores: PSU=00 outside blank, ISR PSU=A1 (SENSE high, interrupt
inhibit set, stack depth one), then marker D7, resumed PSU=80 and marker 22.
Exactly one acknowledgement per blank interval and a second-frame rearm must
be observed. CPU intack is a held level between machine-step enables, not
assumed to be a one-master-edge pulse. This test does not establish physical
MiSTer reset/loader behaviour or qualify physical board clock/display phases.

## Executed implementation checks

The 312 timing and synthetic 317 parameter checks, the 1024 five-event IRQ histories and the actual-CPU
vblank assembly passed their first corrected baselines with seed 1. Every
master edge across two full frames is compared to an independent linear-time
oracle, including run stalls and a restart at nonzero phase. Expectations are
deterministic; the seed does not select randomized stimulus. CPU connection
checks observed all seven expected stores and two acknowledged interrupts.

The first implementation incorrectly treated a labelled line as h=0..226 while
the line counter advances at h=6. VS consequently had a six-position gap and
an extra tail, although its integrated width was correct. The independent
continuous-time oracle failed `vertical_sync` in both profiles at master cycle
41247 (expected negative-sync level 0, observed 1); bounded VCD replay agreed.
The decode now covers the first line's h=0..5 tail and excludes that tail on
the final line. Both corrected profiles passed without changing expectations.
`vsync_wrap_gap` deliberately reintroduces the first gap as a retained regression.

Ten new mutations cover /16 phase, horizontal wrap, nominal and stress totals,
VRST width, blanking OR, VS wrap, HS start and two IRQ edge/level faults. The
complete campaign now has 34 faults, each requiring two matching designated
assertion failures from a passing baseline. Required startup diagnostics and
subsystem gaps still block any RBF; no Quartus or hardware result is claimed.
