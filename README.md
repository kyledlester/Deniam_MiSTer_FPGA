# Deniam-16 for MiSTer

<img width="320" height="224" alt="image" src="https://github.com/user-attachments/assets/d667f1e5-6d69-46c4-8139-e69724b921a4" /> <img width="320" height="224" alt="image" src="https://github.com/user-attachments/assets/98c40032-412d-4511-a6eb-bc5dc0620887" />



A MiSTer FPGA core for the Korean company **Deniam**'s 68000-based arcade boards, **deniam-16b** and
**deniam-16c** (1996-1997), and the puzzle games that run on them: **Logic Pro** (released in Korea and
Germany as **Croquis**), **Logic Pro 2**, and **Karian Cross**. One core (`Deniam`) runs every supported
game; each game has its own MRA.

I created this core because I wanted to play these games on my MiSTer FPGA. I am posting it here and open
sourcing it for everyone to enjoy and give feedback/make improvements. This core was created with the
assistance of AI tooling.

**Status: beta.** All supported games boot, run their attract mode and are playable with graphics, controls and sound, on HDMI and on 15 kHz CRTs.

## Quick start

1. Copy the core from [`Releases/`](Releases/) (`Deniam_YYYYMMDD.rbf`) to
   **`/media/fat/_Arcade/cores/`**.
2. Copy the MRA files from [`MRA/`](MRA/) to **`/media/fat/_Arcade/`**.
   For the alternative sets, copy the `_Logic Pro` folder from
   [`MRA/_alternatives/`](MRA/_alternatives/) to **`/media/fat/_Arcade/_alternatives/`**.
3. Put the MAME 0.289 ROM zips in **`/media/fat/games/mame/`**. With split sets, Logic Pro and
   Croquis (Germany) also need **`croquis.zip`** (MAME's parent of the family; their own zips hold only
   the two program ROMs).
4. Load a game from the **Arcade** menu.

ROMs are not included. You must supply your own.

## Supported games

| Game | MAME set | Year | Genre | Board | Status |
| --- | --- | --- | --- | --- | --- |
| Logic Pro (Japan) | `logicpro` | 1996 | Puzzle (picture logic) | deniam-16b | Full game playable |
| Logic Pro 2 (Japan) | `logicpr2` | 1997 | Puzzle (picture logic) | deniam-16c | Full game playable |
| Karian Cross (Rev. 1.0) | `karianx` | 1997 | Puzzle | deniam-16b | Full game playable |


### Alternatives

These use the same core and the same board as the main set, with different program ROMs.

| Game | MAME set | Year | Parent game | Status |
| --- | --- | --- | --- | --- |
| Croquis (Korea) | `croquis` | 1996 | Logic Pro | Full game playable |
| Croquis (Germany) | `croquisg` | 1996 | Logic Pro | Full game playable |

**Logic Pro / Croquis:** In MAME `croquis` is the parent of the family. Here Logic Pro is the main MRA
and the two Croquis sets are alternatives; all three share every ROM except the program ROMs.

**ROM sets:** split, merged and non-merged MAME sets all work. The MRAs look in the set's own zip first
and then in the parent zip, and find every file by its CRC.

## Controls

Two players, each with a 4-way joystick and three buttons, wired as in MAME's driver:

| MiSTer button | Default pad button | Function |
| --- | --- | --- |
| Button 1 / 2 / 3 | A / B / X | Game buttons |
| Start | Start | Start (P1 / P2) |
| Coin | Select | Coin (P1 / P2) |
| Pause | L | Pause (see OSD) |

The cabinet's service switch is in the OSD (**Service Mode**).

## OSD

* **Aspect ratio**: Original (4:3), Full Screen, or the custom ratios.
* **Orientation** (the same selector as my other cores):
  * **Horizontal**: the normal picture.
  * **Vertical CCW / Vertical CW**: rotate the HDMI picture 90 degrees, for a monitor turned on its side.
  * **Flipped**: turns the picture 180 degrees, on HDMI and on the analog output.
* **Scandoubler Fx**: None, HQ2x, CRT 25%, CRT 50%.
* **DIP switches** from each MRA (coinage, difficulty, play time, demo sounds).
* **Service Mode**: holds the board's service switch (test menu).
* **CRT Adjust** for the native 15 kHz analog output (thanks to rmonic79/MiSTer-CRT-Adjust):
  * **CRT H-Size** (-12 to +10, 1 % per step), **CRT H-Position** (6 pixels per step) and
    **CRT V-Shift** (1 line per step). Off by default; the amounts are hidden while it is Off.
* **Pause options**: pause when the OSD is open, dim the picture after 10 s of pause.
* **Debug**: a status overlay (68000 address, interrupt, sound and frame counters) and a test pattern.

## Saves

The board has no EEPROM or battery-backed RAM: settings live in the DIP switches (OSD) and high scores
are not kept between power cycles, as on the original hardware.

## About the hardware

Although this hardware is noted as "pretty much identical to Sega System 16"; in practice the memory map,
tilemaps and sprites are Deniam's own:

* Motorola **68000** at 12.5 MHz (25 MHz crystal).
* **deniam-16b** (Logic Pro, Croquis, Karian Cross): a **Z80** sound CPU at 6.25 MHz with a Yamaha
  **YM3812** (OPL2) and an **OKI M6295** (ADPCM samples, two banks).
* **deniam-16c** (Logic Pro 2): the same two sound chips driven directly by the 68000, no Z80.
* Two scrolling 8x8 tilemaps (1024 x 512 pixels, built from 16 RAM pages), a text layer, 128 sprites
  drawn from run-length style rows in the sprite ROM with four priority levels, and a 2048-colour
  xBGR-555 palette.
* 320 x 224 visible, horizontal monitor.

The full technical specification is in [docs/HARDWARE.md](docs/HARDWARE.md).

## About the core

* One RBF for both boards. The MRA sends a board-config byte (16b / 16c, the game's scroll offsets);
  see [docs/MRA_FORMAT.md](docs/MRA_FORMAT.md).
* FX68K 68000 at MAME's exact cycle schedule, with the program ROM in SDRAM behind a cache (cache misses
  are repaid so the CPU never runs slower than the original); T80 Z80, jtopl YM3812 and jt6295 OKI.
* Line-based video renderer: both tilemaps, the text layer and the sprites with MAME's priority rules,
  drawn one line ahead of the beam.
* Native 15 kHz output for CRTs (15.625 kHz / 59.64 Hz from the 25 MHz crystal) with CRT Adjust, and
  the MiSTer scaler for HDMI, including rotation for vertical monitors.
* Timing closes on every clock domain.

### Known issues

* The video timing is not PCB-measured (and MAME has no raster model for this board); the core uses a
  System 16-style 400 x 262 raster at 6.25 MHz.
* Logic Pro 2's sound-test menu cannot change the selection: a bug of the original program.

More: [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

## Releases

Builds are in [`Releases/`](Releases/) as `Deniam_YYYYMMDD.rbf`. The MRAs name the core without the date
(`<rbf>Deniam</rbf>`), and MiSTer loads the newest dated file in `_Arcade/cores/`. You are welcome to
run your own build if you'd prefer.

## Building

Quartus Prime Lite 17.0. Open `Deniam.qpf` and compile, or run
`powershell -ExecutionPolicy Bypass -File scripts\build.ps1`. The post-flow script copies
`output_files/Deniam.rbf` to `Releases/Deniam_YYYYMMDD.rbf`. The MRAs are generated by
`scripts/romtool.py`. See [docs/BUILDING.md](docs/BUILDING.md).

## Documentation

* [Hardware specification](docs/HARDWARE.md)
* [Architecture](docs/ARCHITECTURE.md)
* [ROM layout and MRA format](docs/MRA_FORMAT.md)
* [Verification](docs/VERIFICATION.md)
* [Building](docs/BUILDING.md)
* [Known issues](docs/KNOWN_ISSUES.md)
* [Credits and licences](docs/REFERENCES.md)

## License

GPL-3.0-or-later (see [LICENSE](LICENSE)). The MiSTer framework in `sys/` keeps its own notices
([LICENSE.MiSTer](LICENSE.MiSTer)); reused components and their licences are listed in
[docs/REFERENCES.md](docs/REFERENCES.md).

No ROMs or other game data are included in this repository.
