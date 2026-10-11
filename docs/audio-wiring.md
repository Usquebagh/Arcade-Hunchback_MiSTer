# Digital audio wiring audit

## Sources and boundary

The supplied v1.4 PDF page 2 was inspected as a complete sheet and enlarged at
the DAC, resistor network, switches, speech latches and TMS pins. Source hash:
`95a23d34d151344f3611500297e6aaf2ed091cc45562b63917870b62de92616d`.
The drawing is a reverse-engineered board trace and explicitly permits errors.
Use it as evidence, not an instruction or blanket accuracy certificate.

Manufacturer [Philips DAC08 product specification, 1994](https://pe2bz.philpem.me.uk/pdf%20on%20typenumber/D-H/DAC08.pdf),
pages 1-2, marks DIP pin 5 as B1/MSB and pin 12 as B8/LSB. The manufacturer
[1982 Signetics Analog Data Manual](https://www.bitsavers.org/components/signetics/_dataBooks/1982_Signetics_Analog_Data_Manual.pdf)
cross-references the earlier NE5007/5008 to the DAC08 series. Accessed 2026-10-11.
The schematic sends DAC7 to pin 5 and DAC0 to pin 12. Its symbol labels D0..D7
therefore do not imply reversed byte significance. Keep the numeric byte order;
this does not establish analog polarity, gain or the transistor/switch transfer.

The four parallel resistor inputs are LAT0 through 12k, LAT1 through 22k,
LAT2 through 47k and LAT3 through 100k, with a 100k shunt and C11/RV1/R48 into
the Norton mixer. LAT0 has the strongest conductance, unlike the raw nibble's
numeric least significant bit. This is a resistor summing network, not proof
that raw `dac4*4096` equals physical output. Pot positions, TTL levels and
downstream loading/filtering remain unaudited. No gain model is substituted.

The drawing's addressable latch UG5 has one SP_D0 data input for all eight
outputs. Pinned MAME uses bit 7 for LAT0..3 and bit 0 for LAT4..7. The discrepancy
remains. Neither clear writes nor reversing raw nibble significance resolves
it. No HDL data-bit default is changed by this audit.

The byte-DAC/TR1 node has two switch routes: LAT4 controls UD1B toward the
8038 timing capacitor, while inverted LAT4 controls UD1A toward R34/C12/MIX2.
The 8038 triangle path reaches that summing point through R33; its square path
has a LAT5-controlled switch and R35. This supports auditing direct-DAC and
oscillator modes separately. Transistor type/polarity, transfer curves, analog
switch behaviour and filter/mixer gain are still gaps; MAME's `data*4` beeper
frequency is a placeholder, not the oscillator's independent reference.

## Authenticated game write audit

The retained 450-million-edge sampler observation's audio bus log was hash
checked against its frozen report before analysis. All 30391 writes to each
1880..1883 contain exactly 00. Thus both data bit 7 and bit 0 are zero for every
executed four-bit write. Changing that decoder would not activate the constant
channel in these recorded scenarios. This conclusion covers the executed
E6/FF/CB game commands only, not all possible firmware commands or hardware.

1884 has 30398 zero writes; 1886/1887 each have 30391 zero writes; 1885 has no
writes. These scenarios do not exercise enabled discrete effects. Their write
counts cannot qualify that missing sound. Actual address/data counts, source
and log hashes remain private in ignored `results/audio-data-bit-audit.json`.

Speech CPU/control/serial-ROM work is the next independent digital boundary;
see [speech expectations](speech-digital.md). Analog/discrete gain/filter/mixer,
speech engine, physical serial/PDC/CTL/status and CPU power-up/reference audits
remain candidate blockers.
