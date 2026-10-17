# Long-ROM diagnostic

The actual synthesized VHDL S2650 and actual SystemVerilog machine execute the
authenticated unchanged CVS parent. `tools/observe_hunchback.py` uses the pinned
MiSTer-BDSM inventory/snapshot helpers in an isolated Linux temporary directory.
CPU translation has only the established lexical `int` identifier escape.
There is no mock CPU, hierarchical RAM initialization, skipped ROM delay or
alteration of the game's instructions. Generated CPU, ROMs and captures remain
private and ignored. The generic framework is unchanged.

From WSL in the project directory:

```sh
python3 tools/observe_hunchback.py hunchbak.zip --seed 1 --cycles 450000000 --controls
```

The output directory defaults to an ignored timestamped directory under `build`.
It must not already exist. A private `observation.json` records frozen source and
dependency/tool identities, seed, archive/image hashes, independent initialization
reference, exact compiler command, all findings, observations and capture hashes.
The archive hash is checked before preparation and after execution. Maintained
source must stay unchanged during the run. Current captures are complete 244x248
native source fields (MAME-visible y=8..255), with pixel order and field length
checked before retention. Preview rotation preserves 244x248 geometry; its
optional integer scale is only for local readability. Older reports captured
before the native-pixel model retain their original 227x248 fields and are not
comparable to current output. This is a normalized software comparison, not
physical phase validation.

## Expected boundary and stimulus

Every memory/I/O write through the first initialization call must match the
independent runtime-ROM model, followed by the modeled return fetch. IRQ accounting
must be zero at this checkpoint because scan is paused and the call inhibits IRQ.
Later instructions, game state and pixels are observations, not expected-output
replacements or an independent CPU/game oracle.

Power-up uses Verilator `--x-initial unique`, `--x-assign unique`, randomized
register/memory initialization and an explicit seed. All warnings remain in
`compile.log`; `-Wno-fatal` permits a diagnostic executable without hiding them.
The 34 observed findings include generated-CPU unused bits and a PVI helper's
shadowed name. They remain unreviewed. This is two-state simulation and cannot
replace native four-state unknown diagnostics or any candidate gate.

The raw compatibility switch bytes are DSW2=0C and DSW3=0F from the pinned MAME
Hunchback definition. They enter machine ports `dsw1`/`dsw2` respectively. Inputs
are idle FF. Optional synthetic windows use these pinned active-low bits:

| Started field count | Input | Active mask |
| --- | --- | --- |
| 170 through 171 | IN0 coin 1 | 08 |
| 178 through 179 | IN0 start 1 | 01 |
| 700 through 1899 | IN1 right | 10 |
| Three fields every 160 fields starting at 800, after movement proof | IN0 jump | 20 |

The control run leaves inputs idle for at least 520 fields after Start, allowing
the roughly ten-second climbing intro to finish. It measures the player sprite's
source-Y coordinate at field 699, then keeps Right held until at least a four
pixel coordinate change is observed. Jump pulses are gated on that measured
movement proof. This is event-stimulus coverage only; it does not assert that
bell contact occurred.

The bus log records accepted writes and actual registered extended-read responses.
The pixel-derived coordinate check proves movement only when its baseline delta
is reported; input sample counts alone do not. Jump and bell behavior, reaching
the bell, and the physical switch matrix remain unqualified. No left input is used.
The default profile retains main/video execution. Optional `--audio` connects
the actual digital audio CPU/bus with nominal external SENSE; see
[connection checks, observations and gaps](audio-assembly.md). It produces raw
DAC/discrete events and [raw sampled channels](audio-samples.md), with calibrated
gain/filter/mixing, analog/discrete audio and speech still missing.

## Observations and retained counter regression

An initial default-zero diagnostic ran 180 million master clocks through startup
and displayed the Hunchback title/copyright text. Two randomized seeds then ran
300 million clocks with coin/start: 4143 independently modeled initialization
writes, 263 started fields, 1304 extended reads and four reads each during coin
and start windows. All 13 retained field captures matched byte for byte between
the seeds. This is consistency evidence, not an independent expected game frame.
The saved pre-arithmetic PSL context differs between seeds as expected from the
still incomplete unknown-state audit; it is not silently forced to zero.

The observer initially counted a seed-dependent IRQ pin value during reset.
Seed 2 reproduced `observe_reset_irq_count` at cycle 1947717, expected zero,
observed one. IRQ accounting now excludes reset and the checkpoint assertion is
retained. The same short seeded run reaches the checkpoint without that fault;
its subsequent first real IRQ is counted normally. The earlier erroneous counts
remain in their original reports, not rewritten as validated IRQ evidence.

A corrected 450-million-clock seed-1 run observed 396 started fields and 396 IRQ
acknowledgements, 22972487 pixels, 47967 writes and 1964 extended reads. Coin/start
were each sampled four times, right 30 times and jump six times. Captures progress
through title, PLAYER 1, score and a populated castle/game field. These milestones
are observations; full attract/gameplay equivalence and a physical video reference
are absent. One seed's later movement/jump run is not a multi-seed gameplay proof.

Use `tools/render_rom_observation.py` with Pillow to preview a completed report's
hash-matching capture. It rotates the image clockwise 90 degrees per pinned MAME's
ROT90 declaration, preserves the native 248x244 geometry, and affects the preview
only.

## Qualification still missing

The native CPU unknown-state/ISA/cycle audit, physical PCK/PIXCLK/display origins,
full PVI/PAL and collision behaviour, physical inputs, DAC/discrete/speech audio,
MiSTer/HPS/PLL/CDC integration, RAM inference and Quartus fitting/constraints/timing
remain incomplete. Neither a rendered game scene nor an OBSERVED_ONLY report
removes required SKIP/WARNING or replaces the frozen candidate regression and
mutation campaign. No RBF is generated by this diagnostic tool.
