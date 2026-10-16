# Deniam-16 (Logic Pro / Croquis / Karian Cross / Logic Pro 2) for MiSTer

A MiSTer FPGA core for the Korean company **Deniam**'s 68000-based arcade boards, "deniam-16b" and
"deniam-16c", and the puzzle games that run on them: **Logic Pro** (1996, released in Korea and
Germany as **Croquis**), **Karian Cross** (1997) and **Logic Pro 2** (1997). One core (`Deniam`)
runs every supported game; each game has its own MRA.

I created this core because I wanted to play these games on my MiSTer FPGA. I am posting it here and open sourcing it for everyone to enjoy and give feedback/make improvements. This core was created with the assistance of AI tooling.

**Status: beta, for testing on real hardware.** Developed and verified in simulation against MAME (pixel-exact video, matching CPU bus traces and sound-chip write streams); not yet confirmed on a physical MiSTer.

## Quick start

1. Copy the core from [`Releases/`](Releases/) (`Deniam_YYYYMMDD.rbf`) to
   **`/media/fat/_Arcade/cores/`**.
2. Copy the MRA files from [`MRA/`](MRA/) to **`/media/fat/_Arcade/`**.
   For the Croquis sets, copy the `_Logic Pro` folder from
   [`MRA/_alternatives/`](MRA/_alternatives/) to **`/media/fat/_Arcade/_alternatives/`**.
3. Put the MAME ROM zips (MAME 0.289 sets) in **`/media/fat/games/mame/`**.
4. Load a game from the **Arcade** menu.

ROMs are not included. You must supply your own.

## Supported games

| Game | MAME set | Year | Board | Notes |
| --- | --- | --- | --- | --- |
| Logic Pro (Japan) | `logicpro` | 1996 | deniam-16b | main set of the Logic Pro / Croquis family |
| Karian Cross (Rev. 1.0) | `karianx` | 1997 | deniam-16b | |
| Logic Pro 2 (Japan) | `logicpr2` | 1997 | deniam-16c | |

### Alternatives

| Game | MAME set | Year | Parent game |
| --- | --- | --- | --- |
| Croquis (Korea) | `croquis` | 1996 | Logic Pro |
| Croquis (Germany) | `croquisg` | 1996 | Logic Pro |

### ROM notes

* **Split, merged and non-merged** MAME sets work: the MRAs look in the set's own zip first and
  then in the parent zip, and find every file by its CRC.
* MAME's parent of the Logic Pro family is `croquis`. With split sets, `croquis.zip` must be
  present for Logic Pro and Croquis (Germany), because their zips hold only the two program ROMs.

## About the hardware

* Motorola **68000** at 12.5 MHz (25 MHz crystal).
* deniam-16b: **Z80** sound CPU at 6.25 MHz with a Yamaha **YM3812** (OPL2) and an **OKI M6295**;
  deniam-16c: the same two sound chips driven directly by the 68000.
* Two scrolling 8x8 tilemaps (1024 x 512, built from 16 RAM pages), a text layer, 128 sprites drawn
  from run-length style sprite ROM rows, four sprite priority levels, a 2048-colour xBGR-555
  palette.
* 320 x 224 visible, horizontal monitor.

MAME notes that the hardware is "pretty much identical to Sega System 16"; in practice the memory
map, tilemaps and sprites are Deniam's own. The full technical specification is in
[docs/HARDWARE.md](docs/HARDWARE.md).

## About the core

* One RBF for all games. The MRA sends a board-config byte (16b / 16c, scroll offsets); see
  [docs/MRA_FORMAT.md](docs/MRA_FORMAT.md).
* Full video: both tilemaps, the text layer, sprites with their priorities, palette, display enable.
* Sound: YM3812 and OKI M6295 (with sample-ROM banking), mixed with MAME's levels (mono, on both
  channels).
* Native 15 kHz output for CRTs (15.625 kHz / 59.64 Hz), with optional **CRT Adjust** (H-size,
  H-position, V-shift) thanks to rmonic79/MiSTer-CRT-Adjust.
* OSD options:
  * **Aspect ratio** (Original / Full Screen / custom).
  * **Orientation**: Horizontal, **Vertical CCW / Vertical CW** (rotates the HDMI picture for a
    monitor turned on its side), **Flipped** (180 degrees, also on the analog output).
  * **Scandoubler Fx**: None, HQ2x, CRT 25%, CRT 50%.
  * DIP switches (from each MRA), **Service Mode**, pause options, and a Debug submenu (status
    overlay, test pattern).

## Controls

4-way joystick, three buttons, Start, Coin, and a Pause button (MiSTer mapping).

## Verification

Developed against MAME 0.289; details in [docs/VERIFICATION.md](docs/VERIFICATION.md).

## Documentation

* [docs/HARDWARE.md](docs/HARDWARE.md) - hardware specification (from MAME `deniam.cpp`)
* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - core structure
* [docs/MRA_FORMAT.md](docs/MRA_FORMAT.md) - ROM stream and SDRAM layout
* [docs/BUILDING.md](docs/BUILDING.md) - building the RBF and the MRAs
* [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)
* [docs/REFERENCES.md](docs/REFERENCES.md) - reused components and licences

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)); the MiSTer framework in `sys/` under its own terms
([LICENSE.MiSTer](LICENSE.MiSTer)).
