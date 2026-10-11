# CVS v1.4 PAL reference audit

User-supplied archive `century_video_system_tech_infoV1_4.zip`, received
2026-10-11, SHA-256:
`2e7f8ae87b01316d4cfedf10333acab402d26b703311ea8cc350079bf6dcba96`.
All supplied files, source equations, fuse maps, binary PROMs, photographs,
PDFs, inspection code and detailed reports remain in ignored `docs/private/`.
U15L CUPL source SHA-256:
`45ef8fc45563d41c648079e8f29044b3c31180709ca6464f18834ee41423950b`.
Revised PDF SHA-256:
`95a23d34d151344f3611500297e6aaf2ed091cc45562b63917870b62de92616d`.
Archive instructions are reference material only; no physical bypass or ROM
modification described by the readme was performed.

## Supplied logic and intended implementation boundaries

| Location | Inspected CUPL function | Current HDL coverage |
| --- | --- | --- |
| U15L | Eight active-low address groups from A10/A11/A12 and two bus selects | Standalone combinational pin model; exhaustive 32-input test |
| U15H | System/bullet RAM and palette controls | Pending |
| U15J | Palette and character-plane read/write controls | Pending |
| U15K | Program/background reads and three object requests | Pending |
| U14K | Attribute/video RAM controls and reset arbitration | Pending |
| U11D | Eight collision outputs | Pending |
| U5F | Colour selection and feedback | Pending |
| U9K | Shift-register modes and feedback | Pending |

Eight CUPL sources and eight replacement JEDs are present. Sources declare
g16V8; JED headers identify g16v8s. These are supplied replacement GAL images,
not assumed raw fuse maps of the original PAL types drawn in the schematic.
All eight have 2194 fuses; both their transmission and packed fuse checksums
were verified using the semantics of pinned MAME `src/lib/util/jedparse.cpp`.
Integrity checks do **not** prove JED/source equivalence, original-board accuracy,
output-enable behaviour, hazards or propagation timing. Such checks remain pending.

| JED | Transmission checksum | Fuse checksum |
| --- | --- | --- |
| CVS_11D | D210 | 3836 |
| CVS_14K | CA52 | 34B2 |
| CVS_15H | C273 | 3013 |
| CVS_15J | CA26 | 3338 |
| CVS_15K | BADC | 2BD6 |
| CVS_15L | F12A | 461F |
| CVS_5F | E188 | 3C0D |
| CVS_9K | D9C2 | 3848 |

The two supplied PROMs match the existing pinned parent ROM metadata: `82123.bin`
is 32 bytes with CRC b5221cec, matching `82s123.10k`; `82185.bin` is 2048 bytes
with CRC c205bca6, matching `82s185.10h`. SHA-1 also matches both. No MRA or private
ROM preparation change is needed for these alternate filenames.

## U15L model contract

`cvs_decode` takes raw active-low DEC5/DEC6 and A12:A10. Both select inputs high
deselect every output. Either select input low enables exactly one output:
address high group 000 selects PAL_DEC7, through 111 selecting PAL_DEC0.
The harness independently lists the eight input clauses, checks all 32 cases,
and captures combinational traces. Reversing the group number must fail the
`pal_decode` assertion twice. This is one PAL pin boundary, not a connected
memory bus or banked-memory implementation. Existing required CPU/banked-memory/
video/input/audio/integration/constraint blockers remain in place.

## Revised schematic

The supplied v1.4 PDF still has six sheets, whose title blocks say V1.00.
Extracted text comparison against v1.3 finds changed generation timestamps and
an added "Measured 380Hz" note on the audio sheet. That sheet was rendered and
visually reviewed; this supports the nominal sound-board sense oscillator value
previously recorded in MAME. Text comparison is not proof of identical wire
geometry on every page. Sound-board designator photograph is available for
component tracing; detailed component audit remains pending.
