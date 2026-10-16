# ROM layout and MRA format

Reference: MAME 0.289 `sega/deniam.cpp` ROM_START blocks. Tool: `scripts/romtool.py` (never writes
ROM data into the repository; outputs go to `local/`).

## MAME regions

| Region | Size | logicpro / croquis / croquisg | karianx | logicpr2 |
| --- | --- | --- | --- | --- |
| maincpu | 0x100000 | ROM_LOAD16_BYTE pair, 2 x 256 KB (upper 512 KB zero) | even / odd, 2 x 512 KB | lp2-2 / lp2-1, 2 x 512 KB |
| audiocpu | 0x10000 | logicpro.r2 | snd | - (deniam-16c) |
| chars | 0x180000 | logicpro.r5, r6, r7 | bkg1, bkg2, bkg3 | log2-b01, b02, b03 |
| spritegfx | 0x400000 | ROM_LOAD16_BYTE r9 (even) / r8 (odd), 1 MB (rest zero) | 3 ROM_LOAD16_BYTE pairs (obj4/obj1, obj5/obj2, obj6/obj3), 3 MB | obj, 4 MB, ROM_LOAD16_WORD_SWAP |
| oki | 0x100000 | logicpro.r1, 512 KB (rest zero) | voi, 512 KB | log2-s01, 1 MB |

`logicpro`, `croquis` and `croquisg` differ only in the two program ROMs. MAME's parent of the three
is `croquis`; the core's main MRA is Logic Pro (owner's choice) and the Croquis sets are
alternatives. The Logic Pro and Croquis (Germany) MRAs search `<set>.zip|croquis.zip`; every part
carries its CRC, so split, merged and non-merged zips load (Main_MiSTer `FileOpenZip` tries the zips
in order and looks a part up by CRC before its name).

Main releases (`MRA/`): Logic Pro (Japan), Karian Cross (Rev. 1.0), Logic Pro 2 (Japan);
`MRA/_alternatives/_Logic Pro/`: Croquis (Korea), Croquis (Germany).

## Board config (ioctl index 1)

One byte before the ROM stream: bit 0 = deniam-16c (Logic Pro 2: no Z80, the 68000 drives the
sound chips), bit 1 = Karian Cross scroll offsets (docs/HARDWARE.md 6.3). Logic Pro / Croquis 00,
Logic Pro 2 01, Karian Cross 02.

## DIP switches (ioctl index 254)

One byte: the DSW port value as MAME (active low), default FF.

## ROM stream (ioctl index 0, hps_io WIDE=1)

| Stream | Length | Content |
| --- | --- | --- |
| 000000 | 100000 | maincpu (word) |
| 100000 | 180000 | chars (byte) |
| 280000 | 400000 | spritegfx (word) |
| 680000 | 100000 | oki (byte) |
| 780000 | 010000 | audiocpu (byte; deniam-16b only) |

Every region is padded to its full MAME size with `<part repeat="0x...">00</part>` (MAME regions
are zero-filled, and the sprite engine can address the whole 4 MB). Word regions are
`<interleave output="16">` with `map="10"` for the even (MAME offset 0) file and `map="01"` for the
odd one, so `ioctl_dout` is the big-endian word {region byte 2k, region byte 2k+1}. Logic Pro 2's
word-swapped 4 MB sprite file is a plain `<part>`: its file byte 2k+1 is region byte 2k, which is
exactly what WIDE=1 puts in `ioctl_dout[15:8]`. Byte regions: `ioctl_dout[7:0]` = even byte.

`romtool.py mracheck` re-interprets the MRA XML independently (including `repeat` and `map`) and
compares the stream with the layout built from MAME's own region memory (dumped with
`local/devtools/scripts/mame/dump_regions.lua`): PASS for all five sets.

## FPGA placement (dnm_loader.sv)

| Data | SDRAM word address | Order |
| --- | --- | --- |
| maincpu | 000000 | as is (big-endian words); read through dnm_rom_cache |
| chars | 080000 | {tile[15:0], row[2:1], plane[1:0]}: word = {row r byte, row r+1 byte} of ROM plane p; one 4-word burst = the three planes of two rows |
| spritegfx | 180000 | as is: word k = {region byte 2k, 2k+1} |
| oki | 380000 | as is: byte k = word k/2, byte k&1 (little-endian) |
| audiocpu | - | Z80 block RAM 64K x 8 |

`romtool.py images --game <set>` writes the exact SDRAM image the loader produces
(`local/<set>/sim/sdram.hex`) plus `audiocpu.hex`, used by the (local) simulation benches.
