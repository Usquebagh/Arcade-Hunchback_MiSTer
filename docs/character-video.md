# Normalized CVS character, bullet and mixing boundary

Expectations recorded before implementation, 2026-10-11. Compatibility reference:
MAME cvs.cpp at c806573e925ce00fe3e8d8fe417eba63f83275ce, private source SHA-256
f5774d7e58df8201efd683dce553ce4974b0e920e737951391b1b9d89f52773f.
The same revision's drawgfx.cpp, SHA-256
4b10a23600c1babd40cf0faa1b681de861c23c28f21d874f512f44d8ff03c27b,
explicitly establishes first plane = highest pixel bit, MSB-first columns and
scroll-copy translation. Sources and generated evidence stay private/ignored.
Kevtris schematic sheets 3/6 and CUPL U5F/U9K/U11D were inspected as circuit
evidence. The implementation below is a MAME compatibility boundary, not a
completed gate/phase-equivalent reproduction of those circuits.

## Independent expected behaviour

The normalized image is 256x256, 32x32 cells of 8x8. For x in [32,192), source
y is (output y - already-inverted scroll register) modulo 256; other strips
are fixed. The screen address is floor(source y/8)*32 + floor(x/8). Code and
attribute are independently fetched from actual shared FLAG RAM. Glyph row is
source y modulo 8, column x modulo 8. RAM selection thresholds in modes 0..3
are E0,C0,100,80: equality selects RAM, and mode 2 always selects ROM.
ROM has three 2048-byte planes. RAM has three 1024-byte planes containing
codes 80..FF, addressed by (code-128)*8+row, independent of CPU char_page.
Plane 1 contributes pixel bit 2; planes 2/3 contribute bits 1/0.

Lookup PROM address is raw pixel*256 + attribute. Its low three output bits
are reversed into palette bits 2..0. Background collision uses raw glyph bits,
not mapped colour: attribute bit 7 selects mask 6; otherwise low bits ==3
select mask 4; otherwise bit 0 clear selects mask 2; remaining attributes
select mask 0. A black mapped background may still be collision foreground.

Bullet byte zero disables drawing. For unscrolled output y >=8 and byte b>0,
four positions 248-b,247-b,246-b,245-b are drawn only if in [0,256).
Negative coordinates clip, without unsigned wrap. Bullet colour is palette 7.
Any S2636 presence overrides bullet/background, with palette 8 OR all three
colours; black objects retain presence. Stars and video effects are excluded.
Each chip is one {presence,colour} nibble, chip 1 lowest, consistent with the
existing object bank. Collision bits are pairs 1/2,2/3,1/3 at 0/1/2;
bullet/object bit 3; chips 1/2/3 against background at 4/5/6; bullet/background
bit 7. These logical bit assignments follow MAME, not unaudited PAL pin timing.
Collision events accumulate until reset or CPU clear, with new events winning
a simultaneous clear (declared synchronous contract).

Palette RAM remains active low: invert byte, then red bits 1:0, green 4:2,
blue 7:5. Diagnostic RGB expands two bits by replication to eight and three
bits as abcabcab. This is normalized digital output, not calibrated analog DAC.

## FPGA memory and pipeline contract

Separate synchronous display ports read tile code/attribute/bullet, three glyph
RAM bytes and palette. Each port reads on its enabled edge and otherwise holds.
Shared CPU/display same-address writes explicitly forward the new byte. This
contract needs Quartus RAM inference/timing review; it is not board arbitration.
Reads never initialize RAM. Fixtures populate every used byte through actual
CPU memory strobes. Reset does not erase RAM or downloaded ROM/PROM.

A pixel accepted at edge N produces valid output at N+4: tile read, glyph
read, PROM lookup, palette read, RGB/result. Metadata and valid bubbles travel
with that pixel; one request per master edge is supported synthetically. Blank
pixels output black/no collision events; valid still identifies their request.
Reset flushes in-flight pixels and clears outputs/status. Payload holds on
invalid cycles. Physical CVS pixel frequency, origin/crop, blanking, CPU stalls,
display arbitration, OPACK alignment and mid-frame write ordering remain open.

Tests must compare independently computed geometry/addresses/bitplanes and
mixing, exercise every mode boundary, all byte/bit and collision combinations,
variable stalls, back-to-back requests, simultaneous CPU/display access and
reset flush/retention. Important mutations must hit a designated assertion twice.
No new subsystem has a baseline until these checks execute. Existing CPU/native
diagnostic, full PVI, physical input/audio/game/MiSTer/PLL/constraint blockers
remain required. A synthetic composed image is not game boot or board accuracy.

## Actual-CPU connection expectations

A downloaded synthetic S2650 program must populate attributes/codes, bullets,
palette and two distinct glyph pages through actual FLAG memory and extended
I/O. Scan 24x8 pixels: RAM codes 80/C0 in pages 0/2 and ROM code 20, while the
CPU's final writable page is 1. Distinct plane patterns specify every raw pixel.
Two supplied sprite samples (three black objects and two coloured objects) plus
bullet/background overlaps must accumulate FF. After a fixture IRQ resumes HALT
via vector 03, actual CPU control/data reads must store FF then 00 in system RAM,
proving collision read/clear wiring. Coordinates, sprites and IRQ are fixtures;
physical raster/PVI alignment and composed game frames remain unqualified.

## First observations and retained coverage

Display ports passed exhaustive word/plane/page/alias checks and simultaneous
CPU forwarding. The first renderer compile correctly failed on unused colour
bits in the final presence-only stage. That stage now carries only three presence
bits; unsuppressed lint passes. No assertion or expected pixel was weakened.
Initial mistyped lint check identifiers were framework ERROR, never a baseline.

The normalized baseline compares five complete 256x256 fields, each mode and
scroll/fixed-strip boundaries, blanking, bubbles and changing sprite metadata.
Additional cases exhaust 256 attributes x 8 raw pixels x 8 presence masks,
256 bullet bytes x 256 x coordinates, all 4096 sprite nibbles, all 256 palette
bytes, clear/new-event priority, pipeline flushing and reset memory retention.
The synthetic image is byte-checked against the independent reference.
The actual-CPU test passed 192 RAM/ROM pixels with independent row expectations
and FF/00 collision read/clear signatures; page 1 is explicitly initialized
separately to make a wrong-page fault deterministic rather than an unknown read.

Twenty new faults target display page/forwarding/hold, scroll/strips, mode
thresholds, bitplanes/columns, PROM addressing/output wiring, sprite OR,
bullet clipping/top rows, foreground masks, palette polarity and both pixel/CPU
collision clearing, valid latency and held coordinate metadata. Each needs its designated assertion twice from a passing
baseline. Candidate blockers remain. Render with tools/render_sprite_diag.py
--kind character observed.log --expected expected.log --output results/<run>/preview.png.
