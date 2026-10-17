# Discrete audio circuit investigation

## Source and confidence

This is a derived circuit map from page 2 of the private, reverse-engineered CVS
v1.4 schematic. The source is retained under `docs/private/` and is not
redistributed. Schematic values are nominal calculations, not measurements
from a board or calibrated audio recording. The sheet warns that some net names
and traces may be wrong.

## Schematic signal map

The audio CPU's eight `SP_LAT` outputs divide into a four-bit DAC and four
discrete controls:

| Latch outputs | Schematic connection | What the circuit does |
| --- | --- | --- |
| `SP_LAT0..3` | 12 kΩ, 22 kΩ, 47 kΩ and 100 kΩ summing resistors, with a 100 kΩ shunt | Four-bit weighted analog input to the LM3900 mixer. This is separate from the byte DAC. |
| `SP_LAT4` and `/SP_LAT4` | CD4016 switches UD1B and UD1A | Selects the byte-DAC signal between the ICL8038 FM-sweep node and the MIX2 path. |
| `SP_LAT5` | CD4016 switch UD1D and R35=150 kΩ | Gates the ICL8038 square output into MIX2. R34=4.7 kΩ is on the separate byte-DAC-to-MIX2 route. |
| `SP_LAT6` | 10 kΩ base resistor R71, BC337 TR2 and 10 µF C17 | Controls the upper LM3900 branch. It receives NE555 output through D4 and 22 kΩ R65. C17/R73=10 µF/220 kΩ gives a nominal 2.2 s RC constant before loading. |
| `SP_LAT7` | 10 kΩ base resistor R72, BC337 TR3 and 10 µF C18 | Controls the lower LM3900 branch. It receives `NOISE` through inverter U1C, D3 and 22 kΩ R62. C18/R63=10 µF/100 kΩ gives a nominal 1.0 s RC constant before loading. |

The NE555 uses R79=33 kΩ, R80=220 kΩ and C26=10 nF. The TI astable
equations give `f ~= 1.44 / ((RA + 2*RB) * C) = 304.44 Hz` and high duty
`(RA + RB)/(RA + 2*RB) = 53.49%`. This confirms the requested 304 Hz / 53.5%
sanity check. C31=1 nF is connected to the control-voltage pin and is not part
of the nominal frequency calculation. These values describe the oscillator,
not its final sound after the diode, LM3900, filters and mixer.

The ICL8038 timing capacitor is C7=22 nF. Its surrounding network includes
R26=270 kΩ, R27=15 kΩ, R28=82 kΩ, R32=4.7 kΩ and D1. The Renesas
`0.33/(R*C)` nominal equation with R26 and C7 gives about 55.6 Hz when the FM
node is at baseline. SP_LAT4 switches the byte DAC between the ICL8038 FM node
and MIX2; SP_LAT5 gates the square path through UD1D/R35. The triangle output
reaches MIX2 through R33=27 kΩ. The sine output is not connected on this
sheet. Since the DAC drives the FM node, the full frequency law depends on the
DAC transfer, switch state, D1/R32 network and ICL8038 response; the schematic
does not give a calibrated code-to-frequency curve. R27 is the square-output
pull-up and R28 the sine adjust, not timing resistors. `NOISE` enters as a named
net, so this page does not establish its source spectrum.

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

The observed latch value remained zero. This run does not identify which latch
transitions Hunchback uses for bell, walking or jump effects. It is execution
observation, not an expected sound transcript or board measurement.

## Implemented digital approximation and remaining gaps

`rtl/machine/cvs_discrete_audio.sv` supplies an explicitly approximate digital
counterpart. It models the 555 at 304.44 Hz / 53.49%, the ICL8038 as triangle
and square waves at a 55.6 Hz nominal baseline, and a linear 8 Hz/code FM sweep
from the byte DAC while SP_LAT4 selects that route. SP_LAT5 gates the square;
SP_LAT6 and SP_LAT7 gate the 555 and pseudo-random noise paths through one-pole
exponential envelopes using the nominal 2.2 s and 1.0 s RC constants. R33,
R35, R65/R62 and the SP_LAT0..3 resistances supply relative digital mix
weights. SP_LAT4's other state sends the byte DAC directly to MIX2. Speech is
summed as a separate channel.

The 555 frequency/duty and RC products are calculated from schematic values.
The 8 Hz/code FM law, LFSR noise spectrum, envelope loading, analog-switch and
transistor transfer, LM3900 filters, mix polarity/gain and final board response
are assumptions or remain unmodeled. The authenticated Hunchback run observed
only zero discrete latch values, so it has not established which writes trigger
bell, walking or jumping. Synthetic tests verify oscillator cadence, envelope
response and latch routing; they are not an effect transcript or calibrated
sound reference. Treat this as a schematic-topology engineering approximation,
not board emulation.

The NE555 equation is from the [Texas Instruments NE555 data sheet](https://www.ti.com/lit/ds/symlink/ne555.pdf).
The ICL8038 timing equation is in the [Renesas ICL8038 data sheet](https://www.renesas.com/en/document/dst/icl8038-datasheet).
