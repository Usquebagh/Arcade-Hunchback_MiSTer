# MiSTer shell integration

## Source and clock

The system shell in `sys/` and PLL scaffolding in `rtl/pll/` were copied from
the clean local MiSTer `Template_MiSTer` checkout at revision
`3ea1134cf05d62c2b1db30362277a823d739ced2`. The wrapper follows the installed
arcade-core `emu` port convention. Its PLL requests 57.272727 MHz from the
DE10-Nano 50 MHz reference, matching the four-times 14.318181 MHz CVS master
within the generated PLL's requested precision. The internal audio/video
models use the nominal 57,272,724 Hz constant; the 3 Hz PLL request difference
and board oscillator tolerance still require timing review.

The shared ioctl index-0 download feeds the existing 16-bit ROM windows. Core
reset stays asserted while the ROM download is active, until a complete image
has been observed, and until the PLL locks. Main, audio and speech CPUs use
independent ready inputs tied high for this shell. A nominal 380 Hz square-wave
SENSE is generated from the master clock and shared by audio and speech CPUs;
physical oscillator phase, drift and CDC are not qualified.

MiSTer reserves status bit 0 for soft reset, so menu options begin at status
bit 1. Both documented `R0` and template-style `R[0]` declarations are valid;
this core uses `R[0]`, and the shell consumes `status[0]`. The Orientation
option defaults to Rotate CW for the cabinet's vertical native raster; only
the two verified rotated framebuffer orientations are exposed because Native
mode does not produce a usable image. The Native option has therefore been
removed from the OSD. The `screen_rotate`
framebuffer writer uses MiSTer's DDRAM interface, and its `video_rotated`
state is fed back to HPS_IO so the OSD follows the game image. The MRA already
declares `<rotation>vertical</rotation>`. MAME's Hunchback map reads DSW3 at
extended port 6 and DSW2 at port 7;
the shell maps Coin A, Coin B, Lives and Meter Pulses to DSW2/port 7, and
Cabinet, Bonus Life, Registration and Registration Length to DSW3/port 6.
The MAME `hunchbak` input definition includes Registration and Registration
Length through `cvs_registration`; these are not inherited inert settings. Its
DSW2 bit 5 is labelled Unknown by MAME, with a comment identifying it as
"Meter Pulses" and values 2/5, so the OSD exposes that switch under the
documented circuit label. Other unused DSW bits remain fixed at their MAME
defaults. The [MAME CVS driver](https://github.com/mamedev/mame/blob/master/src/mame/misc/cvs.cpp)
is the compatibility reference. The behavioral shell check verifies the raw
bytes at the HPS boundary. Physical positions and electrical polarity of the
board's two DIP switch banks remain unaudited.

## Video and audio boundaries

The MiSTer pixel enable follows the scan position tick through horizontal and
vertical blanking. The schematic-derived scan currently emits 244 active
positions per row; the 227-to-240 horizontal resampling path was removed from
both the scan coordinate and rotation raster. `cvs_scan` selects source rows
8..255 from the 312-line field. `screen_rotate` measures a 248 by 244 buffer,
matching the native scan dimensions after rotation. This is an RTL/schematic
derivation; physical PCK/PIXCLK phases and origins remain open.

The top-level currently sums the provisionally scaled raw DAC8 and normalized
speech PCM channels with signed saturation. The raw DAC4 latch remains exposed
for diagnostics but is excluded from the audible mix: its observed attract
value is code 0, mapped to -32768 by the provisional offset-binary sampler,
which clipped the previous equal-gain sum to the negative rail. The DAC4
schematic bit significance/resistor weights, discrete oscillator path, analog
filtering and speech channel gain remain unverified; this is not calibrated
audio coverage.

The current hardware diagnostic image identifies itself as
`v261017-03-RESET-PROBE`. It turns the video white for 100,000,000 system-clock
cycles (about 1.75 s) when `status[0]` is observed. This visible hold is only a
probe; the game reset itself is stretched for 1,140,000 cycles (20 ms). A white
flash after selecting OSD Reset proves the status bit reached the FPGA. No
flash means the fault remains on the OSD/HPS-to-status path. RTL simulation
already verifies a momentary status pulse resets all three CPUs and restarts
the main CPU from its reset vector.

Joystick mapping follows the MRA button list's consecutive HPS bits starting
at bit 4: Jump, Start 2, Start 1, Coin occupy bits 4 through 7. The `jn`
defaults (`A,X,Start,Select`) and MRA defaults assign those logical slots to
the corresponding gamepad buttons. CVS reads all four controls from IN0:
Start 1/2 are bits 0/1, Coin 2/1 are bits 2/3, and P2/P1 jump are bits 4/5.
The MRA slots map Start 1 (HPS bit 6) to IN0 bit 0 and Start 2 (HPS bit 5) to
IN0 bit 1. A connected-ROM bus trace exposed that the HDL had those two
destinations reversed; the shell test now checks each individually. The
working red button is Jump at bit 4. The prior decoder also read Start 2 from
bit 8 and Coin from bit 9, despite the MRA emitting them at bits 5 and 7.
Direction inputs remain on IN1. MAME selects IN0/IN1/IN2/IN3 at
extended offsets 0/2/3/4 and DSW3/DSW2 at 6/7. The core decodes those offsets;
HPS controls feed IN0/IN1, IN2 (including MAME's uncertain SERVICE1 bit 0) and
IN3 are held high, and DSW2/DSW3 are wired to their matching MAME offsets.
Hunchback disables IN1 green buttons and IN3 vertical directions. The local-ROM coin regression drives
mapped `joystick_0[7]` through the shared HPS-to-CVS mapper, requires the actual CPU to
sample IN0, and checks system RAM byte 0x1c70 changes from 0 to 1; an identical
no-input run retains 0. This is frozen-ROM behavior coverage, not a physical
input wiring reference. Physical decode, cocktail
controls, DIP polarity/defaults and board switch wiring have not been
independently audited. This shell does not establish a general gameplay,
unchanged-ROM, MiSTer hardware or Quartus timing PASS.

`hunchback.mister.shell_behavior` drives the outputs of an interface-only HPS
fixture and checks the real wrapper's index-zero download hold/completion,
external/menu/user reset paths, two-clock reset release, active-low joystick
mapping and representative MAME DSW2/DSW3 bytes through the actual synthesized
S2650 and machine hierarchy. This checks wrapper behavior after the HPS
interface; it does not exercise the HPS serial protocol, real joystick routing,
physical controls or DIP switch placement/polarity.
