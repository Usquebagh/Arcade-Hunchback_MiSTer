# Hunchback CVS arcade hardware for MiSTer FPGA

A private development project for **Hunchback (set 1)**, Century Electronics
(1983), on the original CVS hardware. The Galaxian, Scramble and Donkey Kong
conversions are separate boards; their ROMs are not interchangeable with CVS.

> **Status:** private development core; no qualified RBF candidate yet.
> Reset, main/audio CPU clock enables, program ROM, mirrored system RAM and the
> standalone U15L decoder have synthetic tests. An adapted S2650A passes exhaustive
> ALU and directed CPU/bus regressions; startup diagnostics remain unresolved.
> CPU-side FLAG-banked RAM and memory routing now have exhaustive synthetic checks.
> The connected CPU runs a synthetic program through actual ROM/RAM and raw I/O;
> provisional raster profiles and CPU vblank/interrupt checks also pass.
> Four-object S2636 rendering/status and a three-chip CPU assembly have synthetic
> pixel tests. Shared display RAM and a normalized character/bullet/palette/mixer
> pipeline pass independent pixel and actual-CPU collision read/clear checks.
> A provisional main/video assembly checks a complete synthetic field with real
> PVIs and CPU status reads. The unchanged parent ROM matches 4,143 initialization
> writes and its return. Longer two-state diagnostics display the title and game
> field after coin/start; independent attract/gameplay verification remains open.
> Mixed game video, physical inputs, audio and MiSTer integration remain unfinished.
> A standalone audio CPU and digital DAC/discrete controls pass synthetic checks;
> analog sound, speech and connected machine audio remain unfinished.
> Actual MiSTer testing is pending.

## Original hardware

| Subsystem | Reference hardware | Current implementation |
| --- | --- | --- |
| Main CPU | Signetics S2650A, crystal / 8 | Connected synthetic ROM/RAM/I/O program passes; full CPU and game coverage pending |
| Audio/speech CPUs | Two S2650As, crystal / 16 | CPU implementation available; sound-board instances pending |
| Video | Signetics 2621 PAL timing, three S2636 sprite chips, character ROM/RAM | Timing, S2636 objects/status, character/bullet/mixer and shared-memory CPU checks; physical phases, complete PVI and composed game coverage pending |
| Program | Five 4 KiB EPROMs, staggered in four 8 KiB pages | Downloadable ROM and mirrored 1 KiB system RAM |
| Sound | 8/4-bit DAC, discrete circuits, TMS5100 speech | Pending |

## ROMs and installation

Supply your own `hunchbak.zip`. The merged archive may include conversion and
clone sets; the loader authenticates only the 13 CVS parent chips by exact name,
size, CRC and SHA-1 against pinned MAME. ROMs and manuals remain local and ignored.

`releases/Hunchback (CVS).mra` is a **draft**, with a documented ROM download
layout. It cannot launch a game until the matching `Arcade-Hunchback.rbf` exists.
Do not install it as a tested release. Switches will be added with verified input
wiring. See [architecture](docs/architecture.md) and [references](docs/references.md).

## Development and tests

Use the existing Ubuntu WSL toolchain. From the project directory in WSL:

During development, run the focused check for the changed subsystem and its
retained regressions. The user permits deferring the full regression/mutation
campaign until a frozen candidate; the following commands also show that final
workflow. Real-ROM initialization can be checked with
`bash tools/bdsm.sh test --check hunchback.rom.startup --rom-dir "$PWD"`.

```sh
git submodule update --init MiSTer-BDSM
bash tools/bdsm.sh test --suite smoke
bash tools/bdsm.sh test --suite lint
bash tools/bdsm.sh test --check hunchback.rom.layout --rom-dir "$PWD"
bash tools/bdsm.sh mutate --seed 1 --repeats 2
bash tools/bdsm.sh regression --rom-dir "$PWD"
bash tools/bdsm.sh build --rom-dir "$PWD"
```

The final command requests a candidate, and **must block** while required
subsystem/reference/constraint coverage is missing. A smoke PASS is evidence for
the declared boundary, never overall game accuracy. Local reports are stored in
ignored `results/`; the framework hashes frozen core/adapter/runner inputs and
records tools, seeds, assertions, missing coverage and mutation traces. Important
faults must trigger the designated assertion twice; compilation errors do not count.

The intended build uses Quartus Lite 17.0.2, Cyclone V `5CSEBA6U23I7`, and `sys_top`,
matching the user's existing cores. Integration and its constraints are pending;
there is no Quartus synthesis project yet. Candidate gates require the configured
regressions and reviewed timing/constraint evidence from one frozen snapshot.

## Privacy and license

No pushes, publication, PRs, binaries or test-result uploads until the user confirms
hardware testing. Local commits are permitted. See [agent workflow](AGENTS.md).
Original code is BSD-3-Clause. MiSTer-BDSM is MIT and pinned as a submodule.
Imported Arcadia CPU/packages retain original notices and the supplied upstream
GPL-2.0 license; see the vendor README. Future imports retain their licenses.
See [CPU tests and gaps](docs/cpu.md).
See [main bus and I/O tests](docs/main-bus.md).
See [provisional video timing and remaining gaps](docs/video-timing.md).
See [S2636 objects, status, pixel expectations and gaps](docs/s2636.md).
See [character/bullet/mixer expectations and gaps](docs/character-video.md).
See [provisional scan, composed assembly and early bootstrap](docs/video-assembly.md).
See [private real-ROM observations and their limits](docs/rom-observation.md).
See [audio CPU/digital control checks and reference gaps](docs/audio-digital.md).
See [connected main/video/audio expectations and observations](docs/audio-assembly.md).
See [raw DAC sample checks and private preview limitations](docs/audio-samples.md).
See [audio wiring audit](docs/audio-wiring.md) and [speech CPU/digital interface](docs/speech-digital.md).
See [TMS5100 command-controller checks and remaining LPC work](docs/tms5100-control.md).
See [TMC0281 frames and coefficient ROMs](docs/tms5100-frames.md) and
[numeric lattice/PCM checks](docs/tms5100-lattice.md).
