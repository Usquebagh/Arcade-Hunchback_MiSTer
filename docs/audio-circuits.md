# Discrete audio circuit investigation

## Source and confidence

This is a derived circuit map from page 2 of the private, reverse-engineered CVS
v1.4 schematic. The source is retained under `docs/private/` and is not
redistributed. Schematic-derived values below are nominal calculations, not
measurements from a board or calibrated audio reference. The sheet warns that
some net names and traces may be wrong.

## Schematic signal map

The audio CPU's eight `SP_LAT` outputs divide into a four-bit DAC and four
discrete controls:

| Latch outputs | Schematic connection | What the circuit does |
| --- | --- | --- |
| `SP_LAT0..3` | 12 kΩ, 22 kΩ, 47 kΩ and 100 kΩ summing resistors, with a 100 kΩ shunt | Four-bit weighted analog input to the LM3900 mixer. This is separate from the byte DAC. |
| `SP_LAT4` and `/SP_LAT4` | CD4016 switches UD1B and UD1A | Selects the byte-DAC signal between the ICL8038 FM-sweep node and the MIX2 path. |
| `SP_LAT5` | CD4016 switch UD1D | Gates the ICL8038 square output into MIX2 through a 4.7 kΩ resistor. |
| `SP_LAT6` | 10 kΩ base resistor R71, BC337 TR2 and 10 µF C17 | Controls the upper LM3900 branch. That branch receives the NE555 output through D4 and 22 kΩ R65. The C17/R73 values are 10 µF and 220 kΩ, a nominal 2.2 s RC constant before transistor and amplifier loading. |
| `SP_LAT7` | 10 kΩ base resistor R72, BC337 TR3 and 10 µF C18 | Controls the lower LM3900 branch. That branch receives the `NOISE` net through inverter U1C, D3 and 22 kΩ R62. C18/R63 are 10 µF and 100 kΩ, a nominal 1.0 s RC constant before circuit loading. |

The NE555 uses R79=33 kΩ, R80=220 kΩ and C26=10 nF. Using the TI 555
astable equation, `f ~= 1.44 / ((RA + 2*RB) * C)`, gives approximately
304.4 Hz. C31=1 nF is connected to the control-voltage pin; it is not part of
that nominal frequency calculation. This is the oscillator frequency, not a
claim about the final pitch or envelope heard after the diode, LM3900, filters
and mixer.

The ICL8038 timing capacitor is C7=22 nF. Its surrounding network includes
R26=270 kΩ, R27=15 kΩ, R28=82 kΩ, R32=4.7 kΩ and D1. SP_LAT4 switches the byte
DAC output between the ICL8038 FM-sweep node and the MIX2 path; SP_LAT5 gates
the square-wave path. The triangle output is routed directly to MIX2, while the
sine output is not connected on this sheet. Because the frequency sweep input
is driven by the DAC in one switch state, there is no single fixed oscillator
frequency to calculate from C7 and R26 alone. It depends on the DAC transfer,
code, switch state and the ICL8038 FM response. R27 is the square-output pull-up
and R28 is the sine-adjust resistor; neither is a timing resistor. The `NOISE`
signal enters this page as a named net, so this sheet does not establish its
source spectrum.

The LM3900 paths also contain multi-pole RC networks and feed the shared mixer.
The listed 2.2 s and 1.0 s values are first-order component products, not
complete fitted envelope responses. Resistor loading, transistor state,
amplifier feedback, filters, pot settings and analog-switch resistance affect
the actual sound.

## Authenticated-ROM latch observation

The retained 450,000,000-master-cycle connected run used the local authenticated
Hunchback ROM, actual main/audio/speech CPUs, and the documented coin, start,
right and jump input windows. It reached 396 video fields and observed three
audio command/ack/read events. Its audio bus log contains 91,180 writes to the
discrete latch window:

| Address | Count | Data values seen |
| --- | ---: | --- |
| `1884` (`SP_LAT4`) | 30,398 | `00` only |
| `1885` (`SP_LAT5`) | 0 | no writes |
| `1886` (`SP_LAT6`) | 30,391 | `00` only |
| `1887` (`SP_LAT7`) | 30,391 | `00` only |

The aggregate discrete latch value remained zero in this run. This trace does
not identify which latch transitions Hunchback uses for bell, walking or jump
effects: those transitions did not occur under this stimulus. It also does not
prove that active-low behavior is absent. The capture is an execution
observation, not an expected sound transcript or board measurement. No
MAME-derived effect names are assigned to these outputs here.

## Implementation boundary

The latch decode and circuit paths are grounded in the schematic. Effect-to-bit
names, active polarity and the complete ICL8038 frequency remain unresolved.
The ICL8038, NE555/noise, envelopes, LM3900 filters, resistor-summing mixer and
analog gain are not yet modeled by the FPGA. Any later RTL approximation must
identify its assumptions and must not be described as calibrated board audio.

The NE555 equation is from the [Texas Instruments NE555 data sheet](https://www.ti.com/lit/ds/symlink/ne555.pdf).
The ICL8038 timing equations are in the [Renesas ICL8038 data sheet](https://www.renesas.com/en/document/dst/icl8038-datasheet).
