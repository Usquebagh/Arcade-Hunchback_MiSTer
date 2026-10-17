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

The retained 520,000,000-master-cycle connected run used the local authenticated
Hunchback ROM, actual main/audio/speech CPUs, and scripted coin, start, right
and jump inputs. Coin/start were pulsed at fields 170/178, Right was held for
fields 180..439, and Jump was pulsed at 240..242. It reached 458 video fields,
sampled all four inputs, recorded a coin-related RAM change, and observed five
audio command/acknowledgement/read events. It does not independently prove the
player reached the bell. Its audio bus log contains 91,185 writes to the
discrete latch window:

| Address | Count | Data values seen |
| --- | ---: | --- |
| `1884` (`SP_LAT4`) | 30,401 | `00` only |
| `1885` (`SP_LAT5`) | 0 | no writes |
| `1886` (`SP_LAT6`) | 30,392 | `00` only |
| `1887` (`SP_LAT7`) | 30,392 | `00` only |

All observed latch data values remained zero, including during the scripted
control windows. A follow-up run moved five three-field Jump pulses into active
gameplay (fields 300, 330, 360, 390 and 420). It sampled Jump 30 times, recorded
five main-to-audio commands, five audio acknowledgements and five reads at
`0x1800` (command bytes `E6`, `FF`, `CB`, `D0`, `DC`), but again observed only
zero-valued writes at `1884`, `1886` and `1887`, and no writes at `1885`. The
captured game scene progresses and the player changes position, but this run has
no independent marker proving the jump physics or bell-contact event occurred.

A focused 380,000,000-cycle run then pulsed Jump only at fields 300..302, after
gameplay had begun at field 256, and retained every frame from 296 through 305.
The input was sampled six times and three command/acknowledgement/read events
occurred. It still recorded no nonzero discrete-latch writes. The adjacent-frame
captures are retained, but the observer has no independent game-state signal
that certifies a jump arc or bell collision.

This rules out a generally dead main-to-audio command path: the audio CPU
receives commands, acknowledges their interrupts and reads the command byte.
The data-bit theory is also unsupported: both the schematic's `SP_D0` and MAME's
`data &= 1` for `1884..1887` agree with the RTL's `din[0]`; bit 7 belongs to the
separate `1880..1883` DAC window. The remaining supported explanation is that
the trace has not yet demonstrated the actual sound-effect events (especially a
jump or bell contact), even though it now reaches active gameplay and samples
Jump there. It is not evidence that those events certainly failed to occur.
This is execution observation, not an expected sound transcript or board
measurement.

## Implemented digital approximation and remaining gaps

`rtl/machine/cvs_discrete_audio.sv` supplies an explicitly approximate digital
counterpart. It models the 555 at 304.44 Hz / 53.49%, the ICL8038 as triangle
and square waves at a 55.6 Hz nominal baseline, and a linear 8 Hz/code FM sweep
from the byte DAC while SP_LAT4 selects that route. SP_LAT5 gates the square;
SP_LAT6 and SP_LAT7 gate the 555 and pseudo-random noise paths through one-pole
exponential envelopes using the nominal 2.2 s and 1.0 s RC constants. R33,
R35, R65/R62 and the SP_LAT0..3 resistances supply relative digital mix
weights. SP_LAT4's other state sends the byte DAC directly to MIX2. Speech is
summed as a separate channel. The weighted SP_LAT0..3 ladder is included once
in `discrete_pcm`; top-level `pcm4` is a separate raw diagnostic sampler and is
not added, avoiding a duplicate signal path.

The four-bit ladder keeps the schematic's 12k:22k:47k:100k conductance ratios
but is normalized so all bits set produce approximately +32761 digital counts.
That full-scale normalization is an explicit engineering gain choice because
the reverse-engineered sheet does not establish calibrated LM3900/mixer gain.
For the observed SP_LAT2-only toggling (code 0 to code 4), the expected ladder
swing is approximately 4355 counts, about 13.3% of full scale. This replaces
the earlier raw conductance scaling (about 512 counts for that bit). Byte-DAC
output remains signed full scale and speech is an independent signed channel;
their relative analog levels and final headroom are not measured. The sum can
therefore still clip when channels coincide.

The MiSTer output now passes the combined signed mix through a one-pole digital
AC-coupling filter at the 48 kHz sample cadence. Its coefficient is 4084/4096,
corresponding to a nominal 22.4 Hz corner, and prevents an idle offset-binary
byte-DAC code from pinning the output. The schematic's final output coupling
values are not legible enough to derive a board-specific cutoff, so this is an
engineering approximation. The retained DC-blocker regression verifies that
the observed SP_LAT2 transition remains a centered non-silent waveform.

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
