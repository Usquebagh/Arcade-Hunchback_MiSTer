# Reference provenance

| Reference | Pin/access | Use and limits |
| --- | --- | --- |
| [MAME CVS source](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/mame/misc/cvs.cpp) | c806573e925ce00fe3e8d8fe417eba63f83275ce | CVS identity, ROM hashes/staggering, memory/I/O map, approximate clocks and device configuration; BSD-3-Clause, Mike Coates/Couriersud |
| [MAME Galaxian conversion](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/mame/galaxian/galaxold.cpp) | Same MAME revision | Distinguish `hunchbkg` from CVS; no shared-board assumption |
| [ArcadeRTFM Hunchback](https://arcadertfm.com/#hunchbak) | User-supplied shortcut, inspected 2026-10-11 | Discovery lead; dynamic page supplied no usable circuit document |
| [CVS schematics/PAL dumps thread](https://www.ukvac.com/forum/threads/new-years-treat.89639/) | Inspected 2026-10-11; anonymous attachments require login | Kevtris reverse engineering; v1.3 PDF and v1.4 ZIP advertised, not downloaded or verified |
| [MiSTer-BDSM](https://github.com/Usquebagh/MiSTer-BDSM) | 5c8988540c3a1c50cec9ccb06fc3f923e959b61a | MIT, generic frozen snapshot runner, mutation and candidate gates |

Private raw MAME research is excluded from Git. ROM identity constants contain
metadata only; game bytes never enter source. The draft MRA embeds only padding.
Audio references in MAME explicitly include placeholder beepers and approximate
speech RC frequency; they cannot justify an analog-accuracy PASS. The FPGA clock
and RAM forwarding contracts are implementation decisions, clearly distinct from
schematic measurements. No independent video/collision/input/audio board traces
are yet available. The schematics lead is useful but remains an access gap.
