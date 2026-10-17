# CVS implementation boundary

The reference is MAME `misc/cvs.cpp` at
`c806573e925ce00fe3e8d8fe417eba63f83275ce`. MAME is a compatibility reference,
not independent proof of physical board timing or analog audio fidelity.

## Implemented modules

`cvs_audio_bus` and `cvs_audio_cpu` provide a standalone MAME-compatible digital
sound-CPU boundary: actual 4 KiB ROM/128-byte RAM, command IRQ/read, byte DAC and
four DAC/discrete latches. Exhaustive bus and actual CPU/clock/IRQ checks pass.
`cvs_av_machine` connects actual main/video and audio CPUs with checked command
IRQ/read delivery. `cvs_audio_samples` exposes separate raw signed channels at
nominal 48k cadence with independent numeric checks. Physical DAC coding/weights,
calibrated gain/filter/mixer/discrete output, speech and physical clock/CDC
integration remain pending; the schematic latch-bit discrepancy is retained.
See [audio boundary](audio-digital.md), [connection](audio-assembly.md) and
[raw sampling](audio-samples.md).

`cvs_speech_bus` and `cvs_speech_cpu` add a standalone actual S2650 with 2 KiB
program, 4 KiB serial data, normalized CTL/PDC and external CTL-status/bit-consumer
interfaces. Independent exhaustive bus/serial checks and 17 actual-CPU signatures
pass. The speech engine and connection to the main machine remain pending;
fixtures do not provide LPC/voice or physical control/ROM clock qualification.
See [speech boundary](speech-digital.md).

`cvs_reset`: asynchronous reset assertion and two rising edges for synchronous
release. Reset also holds while PLL lock is absent, ROM download is active, or
the image is not loaded. PLL/loader flags must be synchronous to the master clock;
their physical CDC is not modeled by this unit. No reset-deassertion timing or
metastability proof is claimed by Verilator.

`cvs_clock`: assumed master = 4 x 14.318181 MHz = 57.272724 MHz. Main enable is
master / 32, audio/speech enable master / 64. The audio enable coincides with
every other main enable. Enables are combinational decodes of a registered phase
and are sampled on rising master edges. The tests inspect the settled strobe
before its consuming edge. This module does not establish PLL frequency or video
timing. An exact legal PLL configuration must be selected and checked later.

`cvs_video_timing`: a separately tested 2621 waveform subset with position /16,
horizontal reset, 312 lines, blanking and internal HS/VS interpretations. The
317-line test is synthetic parameter stress coverage. The blurred divider label
has been resolved as 312; board PCK/PIXCLK and display phases remain unaudited.
`cvs_vblank_irq` latches a
rising blank event until CPU acknowledgement. A synthetic actual-CPU assembly
tests SENSE, vector 03, HALT/RETE and rearm; phase-connected game video is pending.
See [video timing and qualification gaps](video-timing.md).

`cvs_s2636_objects` implements four normalized object engines, pattern/colour
mixing, duplicates and completion/collision/VRLE status, with a combinational CPU
read boundary and synchronous read-to-clear. `cvs_s2636_bank` has three instances
in existing 1500/1600/1700 chip-index order. A downloaded synthetic CPU program
initializes them through actual FLAG memory and checks eighteen readbacks and
sampled pixels. Full PVI features and physical/mixed game video remain incomplete;
see [S2636 contract](s2636.md). No fake sprite RAM replaces status side effects.

`cvs_character_video` is a normalized five-edge character/bullet/PROM/palette
pipeline. Separate synchronous ports read actual shared FLAG RAM. Synthetic
pixels and actual CPU initialization/collision reads have independent checks.
The renderer accepts already aligned sprite nibbles; physical PVI/raster alignment,
CVS PAL equivalence, arbitration, stars/effects and composed game frames remain
unqualified. See [character video contract](character-video.md).

`cvs_scan` keeps the tested 312-line, 227-slot sync waveform and separately
emits the schematic-derived 244 active pixels per line (rows y=8..255), preparing
PVI rows two enabled edges after line entry. MAME's 240-column range is a software
crop, not the physical pixel count. `cvs_video_join`
delays metadata one edge to match registered PVI pixels before the character
pipeline; output/sync alignment is six edges. `cvs_machine` connects actual CPU/
FLAG RAM, clock enables, VRST SENSE/IRQ, scan, three PVIs and character/collisions.
A synthetic CPU program checks the complete field and status I/O. This is an
assembly under explicit assumptions, not a qualified CVS/MiSTer top or measured
placement. The unchanged parent passes an independently modeled early RAM-clear
loop after fixing cold synthesized EORZ R0; full game boot remains a required gap.
See [assembly and limitations](video-assembly.md).

`cvs_memory`: 32 KiB downloadable program storage, synchronous one-edge reads;
ROM selected when address bits 12:0 < 0x1400 in each 8 KiB CPU page. ROM is not
CPU-writable. System RAM at 0x1c00..0x1fff mirrors into all four CPU pages. Same
address RAM read/write and ROM download/read explicitly forward the new byte.
That forwarding is a declared adapter implementation contract and must be checked
against inferred Quartus RAM behaviour; it is not a board measurement. Read output
holds with read enable low. RAM power-up contents are unspecified. Tests always
write RAM before reading. 0x1400..0x1bff returns FF at this boundary; this is
temporary unimplemented video memory, not a claim that the board has open bus there.

The supplied six-sheet Kevtris schematic is indexed in
[schematic audit](schematic-audit.md). It shows separate main-board and audio-board
14.318 MHz oscillators. The current shared-master enable phase alignment is an
FPGA contract, not a property of the original boards. CPU frequency expectations
remain MAME-derived until the full divider/timing paths have been audited.

## Planned full map

| Window in each page | FLAG low | FLAG high |
| --- | --- | --- |
| 0x0000..0x13ff | Program ROM | Program ROM |
| 0x1400..0x14ff | Bullet RAM | Palette RAM |
| 0x1500..0x15ff | S2636 #3 | Character RAM plane #3 |
| 0x1600..0x16ff | S2636 #2 | Character RAM plane #2 |
| 0x1700..0x17ff | S2636 #1 | Character RAM plane #1 |
| 0x1800..0x1bff | Attributes | Character codes |
| 0x1c00..0x1fff | System RAM | System RAM |

Extended I/O reads select input strobes and character bank/mode. Extended writes
control scroll. Nonextended control reads return collision flags; writes latch
audio commands. Nonextended data reads clear collisions; writes select video
effects. Vblank drives main sense and interrupt; sound CPUs use an approximate
380 Hz sense oscillator. A synthetic main CPU connection now checks the declared
one-edge memory/I/O protocol and /96 machine-step transfers; provisional vblank
connection also has synthetic CPU checks. Physical bus/video timing and
sound-board timing remain pending. See [main bus](main-bus.md).

## Draft ioctl index-0 layout

| Offset | Length | Region |
| --- | --- | --- |
| 0x0000 | 0x8000 | Main program, FF gaps between 0x1400 and next page |
| 0x8000 | 0x1000 | DAC audio CPU `6c.sdp1` |
| 0x9000 | 0x0800 | Speech CPU `5b.bin` |
| 0x9800 | 0x1000 | Speech data `8a.sp1` plus 0x0800 zero padding |
| 0xa800 | 0x1800 | Character planes CP1, CP2, CP3 |
| 0xc000 | 0x0820 | Lookup and colour PROMs |

Total 0xc820 bytes. For CPU page p and chip c, 1024-byte EPROM quarter p goes
to p*0x2000 + c*0x400. The MRA uses offset/length slices; a separate synthetic
oracle calculates the expected byte from CPU address bits. ROM preparation
validates the private archive independently of the MRA. The real downloader is
not implemented, so hardware-side MRA consumption remains uncovered.
