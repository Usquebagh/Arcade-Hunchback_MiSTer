# TMC0281 numeric coefficient ROMs

Numeric data in cvs_tms5100_tables.sv and the synthetic reference header
sim/bdsm/tms5100_reference.hpp are transcribed from MAME tms5110r.hxx at
c806573e925ce00fe3e8d8fe417eba63f83275ce, SHA-256
43b114437812a94073804617f78a4fd72e9874292dc9be44660cf7b8904f6480.

Source: https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/devices/sound/tms5110r.hxx

Preserve BSD-3-Clause copyright notices for Frank Palazzolo, Couriersud and
Jonathan Gevaryahu; see LICENSES/TMS5100-MAME-BSD-3-Clause.txt. Only numeric
T0280B_0281A_coeff data is imported: TI_0280_PATENT_ENERGY,
TI_0280_2801_PATENT_PITCH, TI_0280_PATENT_LPC, TI_0280_PATENT_CHIRP and TI_INTERP.
The case-address HDL and test logic are original. No MAME engine code or game
ROM bytes are included. No other chip variants are selectable.

Energy is unsigned seven bits, pitch unsigned eight, K signed ten and chirp
signed eight. Interpolation entries are shift counts. The chip's widths are
four energy bits, five pitch bits and K widths 5,5,4,4,4,4,4,3,3,3. Invalid
K slot/index and chirp addresses return zero. Case tables are combinational;
there are no inferred ROM initialization files or runtime research dependencies.

The independently addressed test oracle shares these pinned numeric facts.
It checks transcription/address/sign behaviour, not independent physical table
provenance. Upstream describes decap/patent validation; it is not an additional
board measurement performed in this project. Numeric-table PASS is not LPC,
interpolation, speech firmware, voice, RC frequency or analog fidelity PASS.
