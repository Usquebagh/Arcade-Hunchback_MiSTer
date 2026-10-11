# Reference provenance

| Reference | Pin/access | Use and limits |
| --- | --- | --- |
| [MAME CVS source](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/mame/misc/cvs.cpp) | c806573e925ce00fe3e8d8fe417eba63f83275ce | CVS identity, ROM hashes/staggering, memory/I/O map, approximate clocks and device configuration; BSD-3-Clause, Mike Coates/Couriersud |
| [MAME Galaxian conversion](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/mame/galaxian/galaxold.cpp) | Same MAME revision | Distinguish `hunchbkg` from CVS; no shared-board assumption |
| [ArcadeRTFM Hunchback](https://arcadertfm.com/#hunchbak) | User-supplied shortcut, inspected 2026-10-11 | Discovery lead; dynamic page supplied no usable circuit document |
| User-supplied `cvs_arcade_V1.3.pdf` from [CVS schematics/PAL dumps thread](https://www.ukvac.com/forum/threads/new-years-treat.89639/) | Received and six pages visually inspected 2026-10-11; SHA-256 c4a9ec98547f67742dc70b2ccc096753e6446d00c3c09dd768f27c3ae58d2161 | Kevtris reverse engineering, board circuits; see schematic audit |
| User-supplied v1.4 technical archive from the same thread | Received 2026-10-11; SHA-256 2e7f8ae87b01316d4cfedf10333acab402d26b703311ea8cc350079bf6dcba96 | Eight CUPL sources and replacement JEDs, two PROMs, revised PDF and audio designator photo; see PAL audit |
| [MAME JEDEC parser](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/lib/util/jedparse.cpp) | Same pinned MAME revision | Transmission and fuse checksum semantics; used for local integrity audit, not copied into project code |
| [MiSTer-BDSM](https://github.com/Usquebagh/MiSTer-BDSM) | 5c8988540c3a1c50cec9ccb06fc3f923e959b61a | MIT, generic frozen snapshot runner, mutation and candidate gates |
| [Signetics 2621 preliminary datasheet](https://amigan.yatho.com/2621USG.pdf) | Inspected 2026-10-11; SHA-256 89600ad2677f3c2a92bb7d7ad76030d2b6fef98b856193af39a95832881ce8ac | Manufacturer timing/pin diagrams; supported vertical total 312, corrected blurred-label reading in video timing notes; physical phase audit pending |
| [Valvo/Signetics 2636I preliminary datasheet](https://www.valoroso.it/file-share/documenti-manuali/Signetics-2636-PVI.pdf) | Relevant pages visually inspected 2026-10-11; SHA-256 5d5d24ace87a723b5f4a3d6ccb72a0451dafa75b07619a7903d4492ea12988da | Object/register/duplicate/status rules; board timing and full PVI remain incomplete |
| [MAME S2636 source](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/devices/machine/s2636.cpp) | Same pinned MAME revision; SHA-256 aef1f712c36809c2c35393fedeb9501f419d9c6ac2a973b1151b83ce5515d54d | BSD-3-Clause, Vas Crabb; compatibility cross-check, not copied renderer or independent physical proof |

Private raw MAME research is excluded from Git. ROM identity constants contain
metadata only; game bytes never enter source. The draft MRA embeds only padding.
Audio references in MAME explicitly include placeholder beepers and approximate
speech RC frequency; they cannot justify an analog-accuracy PASS. The FPGA clock
and RAM forwarding contracts are implementation decisions, clearly distinct from
schematic measurements. No independent video/collision/input/audio board traces
are yet available. The user-supplied six-sheet PDF is now available privately;
[schematic audit](schematic-audit.md) distinguishes inspected circuits from
remaining PAL-equivalence, timing and measurement gaps. The subsequent
[v1.4 PAL audit](pal-audit.md) records the newly supplied equations and checksum evidence.
