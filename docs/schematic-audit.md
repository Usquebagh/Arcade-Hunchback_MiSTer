# CVS schematic audit

Source received from the user on 2026-10-11: `cvs_arcade_V1.3.pdf`,
6,453,285 bytes, six pages. SHA-256:
`c4a9ec98547f67742dc70b2ccc096753e6446d00c3c09dd768f27c3ae58d2161`.
The original and rendered inspection crops remain in ignored `docs/private/`.
The PDF is reverse engineering credited "RE/drawn by kevtris". Its filename
says V1.3; individual sheet title blocks say V1.00 and date 2025-12-30.
Use this exact source identity, not an assumed sheet revision. The sheets warn
that net names were guessed and may be wrong, and that untraced paths may remain.
This is circuit evidence; it is not a measured reference or an instruction source.

## Page inventory and inspected evidence

| PDF page | Sheet title | Development use |
| --- | --- | --- |
| 1 | CVS Arcade ROM Board | Five main EPROMs, three character EPROMs, sound/speech EPROMs, connectors and cartridge logic |
| 2 | CVS Arcade Audio Board | Two S2650A CPUs, local oscillator/divider, command/interrupt wiring, 4/8-bit DAC paths, ICL8038, noise/tone/filter/mixer circuitry and TMS5100 |
| 3 | CVS Arcade Main Board 4 | Character/video RAM, attribute/scroll selection and display memory arbitration |
| 4 | CVS Arcade Main Board 1 | Main S2650A, two system RAM chips, inputs/DIPs, latches, CPU handshake and PAL decoders |
| 5 | CVS Arcade Main Board 2 | Crystal/dividers, 2621N timing, three 2636N devices, raster counters, colour DAC/output |
| 6 | CVS Arcade Main Board 3 | Character RAM/ROM selection, shift registers, bullet path and palette/colour lookup circuitry |

All six full pages were rendered and visually inspected. Clock, CPU, speech,
interrupt and PAL regions were also inspected at higher resolution. Extracted
PDF text includes duplicated hidden net labels; visual wire connections take
precedence over text search results.

## Consequences for current HDL and references

1. The original CVS hardware target is supported: one main S2650A, two sound-board
   S2650As, three 2636N sprite devices and a 2621N timing device. The Galaxian/
   Scramble/Donkey Kong conversions remain separate implementations.
2. Main-board page 5 shows X1 labelled 14.318 MHz and U13AA/U13AB 74S112 logic
   producing a net labelled 3.579 MHz. Main CPU page 4 takes an inverted CK2
   timing net. Trace the 2621 timing/polarity and CPU clock path fully before
   claiming schematic-verified CPU phase/cycle accuracy. Current /8 main frequency
   remains a pinned-MAME expectation, not a completed circuit derivation.
3. Audio page 2 has its own X1 labelled 14.318 MHz and UG6 74LS161 feeding SC_CLK.
   Thus the two boards have separate oscillators. The existing shared-master
   enable alignment is an FPGA implementation contract; it does not demonstrate
   physical phase locking. Preserve relative-clock/drift scenarios in connected
   command tests, and account for command crossing/reset before integration.
4. System RAM is drawn as two 2114 devices on main-board page 4. The schematic
   establishes physical wiring but PAL-derived chip enable/write/read control
   still needs equations. Current logical mirroring remains MAME compatibility
   evidence. FPGA synchronous read latency and write-through forwarding are
   implementation choices, not measured 2114 timing.
5. Audio page 2 gives actual discrete hardware instead of MAME's placeholder
   beepers: ICL8038, analog switches, RC sections and mixer/amplifier connections.
   Derive event/channel control and circuit-informed expectations before replacing
   placeholders. Resistor/capacitor tolerances and independent board captures are
   still needed for calibrated fidelity claims.
6. TMS5100 on page 2 has RC/pitch components and CTL/PDC wiring. A fixed nominal
   speech oscillator remains an approximation; no speech synthesis HDL exists.
7. Audio page 2 UF6B 74LS74 is clocked by SCMD7 and its inverted output goes to
   UK5 /INTREQ. Follow ROM/cartridge connectors to identify each CPU's role before
   mapping these guessed SP/SC signal names onto MAME device names. Do not resolve
   any apparent naming difference by changing an expected test without evidence.

## Remaining circuit gaps

The PDF supplies PAL pin connections and type identifiers, including PAL10L8,
PAL12L6 and PAL14H4 devices, but not internal logic equations or fuse maps.
Address decode, RAM/video arbitration, cartridge/protection and collision-related
logic cannot be fully derived from a PAL outline. The user subsequently supplied
the v1.4 ZIP with all eight CUPL sources and replacement JED files; see
[PAL audit](pal-audit.md). The missing-equations gap is now resolved, while
equivalence, connected implementation and hardware validation remain pending.
Retain explicit subsystem/reference/constraint blockers until meaningful checks
replace them. No RBF candidate or timing result is established by this audit.
