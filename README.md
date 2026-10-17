# Hunchback (CVS, 1983) for MiSTer FPGA

An FPGA implementation of Century Electronics' **Hunchback** arcade game for
the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki), based on
the original Century Video System (CVS) hardware. Play as Hunchback, avoid the
fortress obstacles and rescue Esmeralda.

<p align="center"><img src="docs/images/cabinet.png" alt="Hunchback upright cabinet"> <img src="docs/images/gameplay.png" alt="Hunchback on MiSTer"></p>

> **Beta / work in progress.** The core boots and plays on real MiSTer hardware.
> Video geometry, fonts, sprite alignment, controls, reset and cheats have been
> confirmed working. DAC audio and speech work; schematic-derived digital
> approximations now cover the 555, 8038, noise and envelope paths. The sound
> mix and effect triggers still need hardware listening and validation.

This core targets CVS hardware. Hunchback conversions for Galaxian, Scramble
and Donkey Kong hardware use different game ROMs.

## Sound

The core combines byte-DAC and speech audio with a schematic-derived digital
approximation of the original discrete sound paths. The 555 timing follows its
component values, but the 8038 FM curve, noise source, filter response, mix gain
and bell/walking/jumping trigger mapping are not calibrated against recordings.
See [the circuit analysis](docs/audio-circuits.md) for the assumptions and the
remaining gaps.

## Cheats

Cheats use MiSTer's standard HPS download path. The codes are included in the
MRA and were converted from Pugsy's Hunchback entries in the MAME cheat
collection; no separate `.cht` file is needed. Open **Cheats** in the MiSTer
OSD to enable them.

Available cheats are Infinite Credits, Infinite Time, Next Bell = Super Bonus
Now!, Invincibility, P1 Infinite Lives and P2 Infinite Lives. There is no
no-enemies cheat in the included set.

## Installation

Copy the dated core and its MRA to the MiSTer SD card:

| File | MiSTer SD-card destination |
| --- | --- |
| [hunchback_20261017.rbf](releases/hunchback_20261017.rbf) | `_Arcade/cores/` |
| [Hunchback (CVS).mra](releases/Hunchback%20(CVS).mra) | `_Arcade/` |
| Your own `hunchbak.zip` | `games/mame/` |

Launch Hunchback through the MRA. It expects the `hunchbak.zip` archive. **No
ROMs are included in this repository or in the RBF.** Supply your own legally
obtained ROM archive, and keep only one Hunchback RBF in `_Arcade/cores/`.
Older MiSTer installations may also support `_Arcade/mame/` as a legacy ROM
location.

## Build and tests

Quartus Prime Lite 17.0.2 for Cyclone V is used to build the core. Run:

```sh
git clone https://github.com/Usquebagh/Arcade-Hunchback_MiSTer.git
cd Arcade-Hunchback_MiSTer
bash build.sh
```

Each Quartus build generates a UTC timestamp in the OSD version line. The
result is an engineering build; broader validation is still in progress.

MiSTer-BDSM is needed only for the regression and mutation suite. Clone it
separately and set `MISTER_BDSM_PATH` to its checkout:

```sh
git clone https://github.com/Usquebagh/MiSTer-BDSM.git /path/to/MiSTer-BDSM
export MISTER_BDSM_PATH=/path/to/MiSTer-BDSM
bash tools/bdsm.sh test --suite smoke
bash tools/bdsm.sh test --suite lint
```

## Research and credits

CVS board research was informed by Kevtris's reverse-engineered technical
documentation. The private schematics, PAL/CUPL sources and JEDEC files are not
redistributed here. See [reference provenance](docs/references.md). MAME
contributors provided compatibility references for CVS ROM layout, memory
mapping and device behavior. The MiSTer framework and imported Arcadia CPU
modules retain their respective licenses; see [LICENSES](LICENSES/) and the
source notices.

## License

Original core and tools are BSD-3-Clause. Imported components retain their
upstream licenses and notices; see [LICENSE](LICENSE), [LICENSES](LICENSES/)
and the vendored component documentation.
