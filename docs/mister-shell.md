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

## Video and audio boundaries

The MiSTer pixel enable follows the scan position tick through horizontal and
vertical blanking. It is delayed to match the existing five-master-edge RGB,
display-enable and sync pipeline. The normalized 227 by 256 viewport is
provisional, and the actual board PCK/PIXCLK phases and origins remain open.
The 227:256 original aspect option represents this provisional viewport.

The top-level currently sums the independently scaled raw DAC8, raw DAC4 and
normalized speech PCM channels with signed saturation. This is only a digital
bring-up mix. The DAC4 schematic bit significance/resistor weights, discrete
oscillator path, analog filtering and speech channel gain remain unverified;
this connection does not constitute calibrated audio coverage.

Joystick mapping follows the pinned MAME Hunchback input-port bit assignments.
Physical decode, cocktail controls, DIP polarity/defaults and board switch
wiring have not been independently audited. This shell does not establish a
gameplay, unchanged-ROM, MiSTer hardware or Quartus timing PASS.
