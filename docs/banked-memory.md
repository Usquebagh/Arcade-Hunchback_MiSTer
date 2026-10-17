# CPU-side CVS banked memory

Reference: pinned MAME CVS main_cpu_map, palette_r/w and character_ram_r/w,
and Kevtris v1.4 PAL sources, previously audited privately. The SystemVerilog
`cvs_main_memory` connects existing downloaded program/system RAM to new FLAG
views. The subsequent `cvs_main` assembly connects this boundary to the adapted
S2650; a downloaded synthetic program checks real memory and I/O responses.

| Window, mirrored in each 8 KiB CPU page | FLAG low | FLAG high |
| --- | --- | --- |
| 1400..14FF | 256-byte bullet RAM | 16-byte palette, aliases every 16 bytes |
| 1500..15FF | S2636 chip 3 interface | Character plane 3, selected 256-byte page |
| 1600..16FF | S2636 chip 2 interface | Character plane 2, selected 256-byte page |
| 1700..17FF | S2636 chip 1 interface | Character plane 1, selected 256-byte page |
| 1800..1BFF | 1 KiB attribute RAM | 1 KiB character-code RAM |

Each character plane has four independent pages. The char_page input is now
latched by `cvs_main_io` from extended-read address bits 6/7; rendering mode
is separately selected by bits 4/5. In MAME's larger character region the writable
1 KiB half is at plane_offset OR 0400 OR page_offset OR byte_offset. These modules
store only that writable half, not character ROM or the full graphics region.

Reads have one master-edge latency; outputs hold with read disabled. CPU RAM
same-address read/write forwards the new byte, an explicit implementation
contract requiring later Quartus inference review. The response-window selector
is registered with a read so the next address/FLAG cannot change the preceding
response. RAM has unspecified power-up state and is not reset-cleared. Tests
always populate memory before reading. Palette bytes are stored unmodified;
active-low RGB conversion belongs to the future video pipeline.

Sprite selection is chip-index order: 1500 selects bit 2, 1600 bit 1 and 1700
bit 0. Requests are qualified by FLAG low and read/write strobes. Byte address
and write data are exported; sprite_din must be supplied by the eventual selected
register device. S2636 registers, collision side effects and sprite drawing are
not modeled as ordinary RAM or claimed covered by this test.

The synthetic test fills every independent RAM view, character page and plane,
then reads all four CPU-page mirrors and every palette alias. It checks sprite
selection/read/write/idle isolation, held responses, program routing and FLAG-
independent system RAM. Mutations select the wrong FLAG view, alias character
pages, reverse sprite chip selection, and use a live response selector.

The new three-instance S2636 object/status bank now attaches to these sprite
ports in an actual-CPU synthetic assembly; eighteen readback signatures check
distinct chips, FLAG isolation, VRLE and completion read-clear. Normalized object
pixels and six within-chip collision pairs are checked separately. Full PVI
features and physical board timing remain unqualified; see [S2636](s2636.md).

Separate synchronous tile/code/attribute/bullet, three-plane glyph and palette
display ports now pass exhaustive reads, hold and CPU write-forwarding checks.
They do not follow the CPU char_page or FLAG. A normalized character pipeline
uses these actual memories; an actual CPU scene checks distinct glyph pages and
collision I/O. See [display contract and remaining gaps](character-video.md).

The pre-conversion source at commit `b212459^` used synchronous CPU writes and
returned stored RAM on a later CPU read. A simultaneous CPU read/write returned
`cpu_din` through the bus response bypass; the display port separately bypassed
a same-address write. The current regression now checks write/readback, explicit
zero clear, and simultaneous CPU read/write on screen, attribute, bullet,
palette, and each of the three character arrays. The existing display test
continues to cover same-edge write forwarding independently for all seven
display read paths. These are source-contract regressions; Quartus M10K
read-during-write mode still requires fitter/netlist review.

Missing: physical display arbitration, full S2636 semantics and Quartus memory
inference/CDC/timing. The required banked
memory coverage gap remains active until those pieces have meaningful checks.

CPU reset investigation: existing native diagnostics arise from unspecified
PSL/stack/internal state being evaluated before initialization, including
comparisons that do not affect the exercised instructions. This does not justify
a blanket warning suppression or forcing all hardware reset state to MAME's
initial image. Runtime diagnostics still return required WARNING; no reset
qualification improvement or complete unknown-state audit is claimed here.
