# Actual speech CPU, clock and engine assembly

## Expectations recorded before implementation

Connect the actual adapted S2650, speech bus and normalized TMS5100 engine.
Command remains seven bits. Return engine CTL read bit zero to the CPU, with
the existing bus inversion. Feed actual bus CTL/PDC to the engine and its ROM
request to the actual bus; no external TALK or bit-consumer fixture substitutes
for the engine. Generate /192 CPU enables and independent nominal 7750 Hz
logical sample enables from the shared master. CPU ready stalls cannot pause
the speech sample clock. SENSE remains external pending physical-clock audit.

Download program bytes 9000..97FF into 2 KiB program ROM; download 9800..A7FF
into 4 KiB serial ROM using address minus 9800. All other image windows are
isolated. Global reset retains ROMs. Engine software RESET retains the CPU's
serial pointer. Main/audio/character/PROM downloads must not corrupt speech.

The actual-CPU synthetic fixture executes the eight independently specified
status/direction signatures C2,C2,42,C2,C2,C2,C2,C2 from the existing controller
assembly, with real SPEAK/TEST TALK/OUTPUT/RESET writes. Its final command is
SPEAK; after the eight signatures the actual CPU explicitly writes a ninth
zero pointer marker and then halts. Final pointer is zero. Download a
stop-only nibble F at byte zero and zero elsewhere. A 512-edge ready stall must
retain the pending talk-output CPU read. After the final SPEAK, the real engine
must consume exactly four bits, report exactly one decoded stop frame and
eventually drop TALK, then continue emitting idle samples. Zero-energy active
samples are zero PCM; idle samples are signed -1. All PCM/accepted CPU data/
addresses must remain known in this bounded four-state fixture. The stop
sentinel catches an incorrectly offset serial downloader and alias writes at
the first character/PROM boundary; no inferred RAM or
hierarchical ROM initialization is permitted.

An authenticated unchanged-ROM observation must freeze the whole source before
compiling, load untouched program/data through these ports, use exact bounded
command/SENSE stimuli and retain sample/control/serial logs and identities.
Its generated voice remains OBSERVED_ONLY unless a separate justified oracle
checks it. Shared-clock/RC approximations, physical CS/CTL1/PDC/aliases/CDC,
native CPU broad diagnostics, analog mixing and three-CPU/MiSTer/Quartus gates
remain explicit limitations.
