# Deniam-16 hardware (Logic Pro, Croquis, Karian Cross, Logic Pro 2) - technical specification

Reference: MAME 0.289 `src/mame/sega/deniam.cpp` (driver by Nicola Salmoria), `src/emu/tilemap.cpp`,
`src/emu/video/generic.cpp` (`gfx_8x8x3_planar`), `src/emu/emupal.cpp`
(`xBGRBBBBGGGGRRRR_bit0`), `src/devices/sound/okim6295.cpp`, `src/devices/machine/gen_latch.cpp`.
This document is the specification the FPGA core is built from. The video model (section 6) is
checked against MAME: a Python restatement of it (`local/devtools/scripts/refrender.py`) reproduces
MAME's own rendered pixels exactly for every captured frame (see section 10).

Deniam is a Korean company (Seoul); their arcade boards are called "deniam-16". MAME notes that
the hardware is "pretty much identical to Sega System 16" (68000, similar sprite chip concept,
xBGR-555 palette), but the memory map, tilemaps and sprite format are Deniam's own.

## 1. Games and board versions

| MAME set | Title | Date (title screen) | Board | MAME parent | Program ROMs | Scroll offsets |
| --- | --- | --- | --- | --- | --- | --- |
| `logicpro` | Logic Pro (Japan) | 1996/10/20 | deniam-16b | `croquis` | logicpro.r4 / .r3 (2 x 256 KB) | logicpro |
| `croquis` | Croquis (Korea) | 1996 | deniam-16b | - | sys_e0 / sys_o0 | logicpro |
| `croquisg` | Croquis (Germany) | 1996 | deniam-16b | `croquis` | r4.bin / r3.bin | logicpro |
| `karianx` | Karian Cross (Rev. 1.0) | 1997/04/17 | deniam-16b | - | even / odd (2 x 512 KB) | karianx |
| `logicpr2` | Logic Pro 2 (Japan) | 1997/06/20 | deniam-16c | - | lp2-2 / lp2-1 (2 x 512 KB) | logicpro |

All are ROT0 (horizontal) puzzle games. Croquis is the Korean/German release of Logic Pro;
`logicpro`, `croquis` and `croquisg` share every ROM except the two program ROMs. Undumped games on
the same hardware: GO!GO! (16b, 1995), Lottery Game (16c, 1997), Propose (16c, 1997).

The two board versions:

| | deniam-16b | deniam-16c |
| --- | --- | --- |
| Sound CPU | Z80 at 6.25 MHz | none |
| YM3812 / OKI M6295 | on the Z80 bus | on the 68000 bus |
| 68000 sound interface | 8-bit sound latch at C40000 | direct chip access (C40001, C40007, C40008-C4000B) |

The game-dependent "scroll offsets" are constants the video hardware (MAME: the driver init)
subtracts from the tilemap scroll registers (section 6.3).

## 2. Clocks

All from one 25 MHz crystal (MAME: values "verified" on PCB).

| Signal | Rate | Derivation |
| --- | --- | --- |
| 68000 | 12.5 MHz | 25 / 2 |
| Z80 (16b only) | 6.25 MHz | 25 / 4 |
| YM3812 ("SM64" clone) | 4.1667 MHz | 25 / 6 |
| OKI M6295, pin 7 high | 1.0417 MHz (sample rate 1.0417 MHz / 132 = 7891 Hz) | 25 / 24 |
| Pixel clock (not documented by MAME; System 16 style) | 6.25 MHz | 25 / 4 |

## 3. Video timing

MAME: `set_refresh_hz(60)`, `set_vblank_time(0)`, `set_size(512, 256)`, visible area
x 188-507, y 0-223 (320 x 224; the comment notes x 192-511 "looks better but doesn't match
hardware"). The vertical blank starts at line 224, which is also when the 68000 gets its interrupt.

MAME does not model a raster. The core uses a System 16-like raster built from the 6.25 MHz pixel
clock (not PCB-measured):

| | |
| --- | --- |
| Dots per line | 400 (visible 320) -> 15.625 kHz |
| Lines per frame | 262 (visible 224, lines 0-223) -> 59.64 Hz |
| Vertical blank / IRQ 4 | starts at line 224 |
| Board x of output dot d | 188 + d (d = 0..319) |

Sync placement is a MiSTer/CRT choice: H active 0-319, front porch 320-335, HSync 336-365 (4.8 us),
back porch 366-399; V active 0-223, front porch 224-231, VSync 232-234, back porch 235-261.

## 4. 68000 memory map

Full 24-bit decode as MAME (`base_main_map` + `main_map`); everything else is unmapped (reads 0,
writes ignored). All ports are 16 bits wide; 8-bit input ports read with the upper byte 0
(confirmed: MAME returns `00ff` for a word read of an idle input port).

| Address | R/W | Function |
| --- | --- | --- |
| 000000-0FFFFF | R | program ROM (1 MB region; logicpro / croquis load 512 KB, the rest reads 0) |
| 400000-40FFFF | R/W | tilemap RAM ("videoram", 64 KB = 16 pages x 2048 words) |
| 410000-410FFF | R/W | text RAM (64 x 32 words) + video registers at 4100A2-4100AD (6.2) |
| 440000-4407FF | W | sprite RAM (128 x 8 words); reads 0 |
| 840000-840FFF | W | palette RAM (2048 words); reads 0 |
| C40000 (byte, D15-8) | W | 16b: sound latch (to the Z80) |
| C40001 (byte, D7-0) | R/W | 16c: OKI M6295 |
| C40002-C40003 | R/W | coin / display control (read back the last written value) |
| C40004-C40005 | W | IRQ 4 acknowledge (any write) |
| C40007 (byte) | W | 16c: OKI ROM bank (bit 0) |
| C40008 / C4000A (D15-8) | W | 16c: YM3812 address / data |
| C44000-C44001 | R | SYSTEM port |
| C44002-C44003 | R | P1 port |
| C44004-C44005 | R | P2 port (writes ignored) |
| C44006-C44007 | R | reads 0 (unused) |
| C4400A-C4400B | R | DSW |
| FF0000-FFFFFF | R/W | work RAM 64 KB |

Coin / display control (C40002): bit 0 coin counter; bit 5 display enable (0 = the screen is black;
MAME's comment says "bit 6" but tests 0x20); other bits unused. Power-on value 0.

Interrupts: one source, IRQ 4 (autovector), asserted at the start of vertical blank
(`irq4_line_assert`) and held until the program writes C40004.

## 5. Inputs

All active low (bit = 0 when pressed).

| Bit | SYSTEM | P1 / P2 |
| --- | --- | --- |
| 0 | Coin 1 | Button 1 |
| 1 | Coin 2 | Button 2 |
| 2 | Service mode (held, `PORT_SERVICE_NO_TOGGLE`) | Button 3 |
| 3 | Service 1 (service coin) | - |
| 4 | Start 1 | Down |
| 5 | Start 2 | Up |
| 6 | - | Right |
| 7 | - | Left |

The joysticks are 4-way. DSW (MAME default FF):

| Bits | Karian Cross | Logic Pro / Croquis / Logic Pro 2 |
| --- | --- | --- |
| 2-0 | Coinage: 0 Free Play, 1 2C1C, 2 3C1C, 3 1C2C, 4 3C2C, 5 1C3C, 6 2C3C, 7 1C1C | same |
| 4-3 | Difficulty: 0 Hard, 1 Very Easy, 2 Easy, 3 Normal | Play Time: 0 Fastest, 1 Slow, 2 Fast, 3 Normal |
| 5 | Demo Music: 0 Off, 1 On | Difficulty (bits 6-5): 0 Hardest, 1 Easy, 2 Hard, 3 Normal |
| 6 | unused | (Difficulty, see above) |
| 7 | Service Mode: 0 On, 1 Off | Demo Sounds: 0 Off, 1 On |

MAME notes that the Logic Pro DIPs may be wrong (it uses the Logic Pro 2 ones).

## 6. Video

### 6.1 Overview

Three layers and sprites, drawn in this order (later layers on top):

1. **BG** tilemap, 8x8 tiles, 128 x 64 tiles (1024 x 512 pixels) built from 4 pages, opaque.
2. **FG** tilemap, same format, pen 0 transparent.
3. **TX** (text) tilemap, 8x8 tiles, 64 x 32 tiles, not scrolled, pen 0 transparent.
4. **Sprites**, 128, run-length style row data straight from the sprite ROM, 4 priority levels.

The palette has 2048 entries: tile layers use 0-1023 (8 entries per colour code), sprites 1024-2047
(16 per code).

### 6.2 Video registers (in text RAM)

The scroll and page registers are ordinary words of text RAM (they sit in text row 1, columns
17-22, outside the visible area):

| Text RAM word (byte address) | Register |
| --- | --- |
| 0x51 (4100A2) | FG scroll X |
| 0x52 (4100A4) | BG scroll X |
| 0x53 (4100A6) | FG scroll Y (bits 7-0) |
| 0x54 (4100A8) | BG scroll Y (bits 7-0) |
| 0x55 (4100AA) | FG page select: 4 nibbles, nibble n = VRAM page of tilemap page n |
| 0x56 (4100AC) | BG page select |

### 6.3 BG and FG tilemaps

Effective scroll (`xo`, `yo` = game scroll offsets: logicpro sets BG 0x00D/0, FG 0x009/0;
karianx BG 0x10D/0x80, FG 0x109/0x80):

    sx = (scrollx - xo) & 0x1FF          sy = ((scrolly & 0xFF) - yo) & 0xFF

Screen pixel (X, Y) (board coordinates, X = 188..507, Y = 0..223) shows tilemap pixel
`tx = (X + sx) & 0x3FF`, `ty = (Y + sy) & 0x1FF`. With `col = tx >> 3`, `row = ty >> 3`:

    page  = (col >> 6) | ((row >> 5) << 1)                 (tilemap page 0..3)
    vpage = page_select >> (4 * page) & 0xF                 (VRAM page 0..15)
    attr  = videoram[vpage * 0x800 + (row & 0x1F) * 64 + (col & 0x3F)]
    tile  = attr (all 16 bits)                              colour = (attr >> 6) & 0x7F
    pen   = chars pixel (tile, ty & 7, tx & 7)              palette index = colour * 8 + pen

The tile number and the colour code overlap (bits 12-6 are both). BG draws every pen; FG skips
pen 0.

### 6.4 Text layer

`attr = textram[(Y >> 3) * 64 + (X >> 3)]`, tile = `attr & 0xF1FF`, colour = `(attr >> 9) & 7`,
pen = chars pixel (tile, Y & 7, X & 7), palette index = colour * 8 + pen (entries 0-63), pen 0
transparent.

### 6.5 Character ROM ("chars", 3 x 512 KB, 65536 tiles)

`gfx_8x8x3_planar`: tile t row r is byte `t * 8 + r` of each of the three ROMs; bit 7 is the left
pixel. pen = (ROM3 bit << 2) | (ROM2 bit << 1) | ROM1 bit, where ROM1/2/3 are the files loaded at
region offsets 0, 0x80000, 0x100000 (MAME's first plane offset, RGN_FRAC(2,3), is the pen MSB).

### 6.6 Sprites

Sprite RAM: 128 entries of 8 words.

| Word | Bits | Use |
| --- | --- | --- |
| 0 | 7-0 | start Y (the sprite covers lines start+1 .. end) |
| 0 | 15-8 | end Y |
| 1 | 8-0 | X position |
| 2 | 6-0 | width: row pitch in words |
| 2 | 8 | flip X |
| 3 | 15-0 | sprite ROM word address bits 15-0 |
| 4 | 5-0 | colour (palette 1024 + colour * 16) |
| 4 | 7-6 | priority |
| 4 | 12-8 | sprite ROM word address bits 20-16 |
| 5-7 | | unused (System 16 zoom words; not used by these games) |

Drawing (MAME `draw_sprites`), for entry e from 127 down to 0:

    sx    = (word1 & 0x1FF) + 127, minus 512 if >= 512; plus 1 if flip X
    start = word3 + (word4 bits 12-8) << 16                  (word address in the 4 MB ROM)
    for y = starty+1 .. endy:
        a = 2 * start + 2 * width * (y - starty)           (byte address; row 0 is never drawn)
        walk bytes a, a+1, a+2, ... (flip X: a, a-1, a-2, ...), 2 nibbles per byte:
            normal order: high nibble then low nibble; flip X: low then high
            nibble F: the first one is a start marker, the second ends the row (no pixel, x unchanged)
            other nibbles: pixel at (sx + x, y), x += 1; nibble 0 is transparent
        at most 512 bytes per row (MAME safety limit, normal direction)

The pixel position is not wrapped: pixels outside the visible window (X < 188 or X > 507) are
dropped. Every non-transparent nibble inside the window **claims** its screen pixel: once a pixel
has been claimed by a sprite, no later-drawn (lower-numbered) sprite can draw there, whether or
not the claiming sprite was itself visible. The claiming sprite is visible over the tile layers
according to its priority:

| Priority (word4 bits 7-6) | Visible where |
| --- | --- |
| 0 | never (BG is opaque, so "below everything" hides the sprite completely) |
| 1 | no FG and no TX pixel |
| 2 | no TX pixel |
| 3 | always |

So per screen pixel: the highest-numbered sprite with a non-transparent pixel there decides; if its
priority lets it through, its colour is shown, otherwise the tile layers (TX if opaque, else FG if
opaque, else BG).

Sprite ROM ("spritegfx", 4 MB): 16b boards load ROM pairs with `ROM_LOAD16_BYTE` (even file at
even bytes) at 0, 0x100000, 0x200000; Logic Pro 2 loads one 4 MB file `ROM_LOAD16_WORD_SWAP`
(region byte 2k = file byte 2k+1). Unloaded parts read 0.

### 6.7 Palette

2048 words, MAME format `xBGRBBBBGGGGRRRR_bit0`: R = bits 3-0 << 1 | bit 12, G = bits 7-4 << 1 |
bit 13, B = bits 11-8 << 1 | bit 14; 5 bits per channel expanded to 8 as `(v << 3) | (v >> 2)`.
Bit 15 (probably System 16-style shadow/highlight) is not emulated by MAME and not used by the
games.

### 6.8 Display enable

When C40002 bit 5 is 0 the whole picture is black.

### 6.9 Known MAME deviations from the PCB

* Logic Pro: inserting a coin makes the screen slightly darker until the next scene change on the
  PCB; not emulated (probably the bit-15 shadow).
* Logic Pro / Logic Pro 2 show 4 pixels of garbage at the left edge on the PCB (MAME's visible area
  starts 4 pixels left of the "nice" 192).
* No flip screen (no DIP, no cocktail mode).

## 7. Sound, deniam-16b (Z80 board)

Z80 at 6.25 MHz:

| Z80 address | Function |
| --- | --- |
| 0000-F7FF | ROM (64 KB file; top 2 KB hidden by RAM) |
| F800-FFFF | RAM 2 KB |

| Z80 I/O port (A7-A0) | Function |
| --- | --- |
| 01 R | sound latch (reading clears "data pending") |
| 02 / 03 W | YM3812 address / data |
| 05 R/W | OKI M6295 status / command |
| 07 W | OKI ROM bank: bit 6 selects the 256 KB half of the sample ROM |

Unmapped reads return 0. NMI = sound latch "data pending" (set by the 68000 write, cleared by the
Z80 read, `generic_latch_8`); INT = YM3812 IRQ.

## 8. Sound, deniam-16c (no Z80)

The 68000 drives the chips directly: OKI at C40001, OKI bank at C40007 bit 0, YM3812 address / data
at C40008 / C4000A (upper byte). The YM3812 IRQ is not connected. MAME notes that Logic Pro 2's
1 MB sample ROM has four banks but bit 0 alone selects among the first two (the program writes
only 0 and 1). The bank is reset to 0 at machine reset.

## 9. Mixing

Mono: YM3812 x 0.60 + OKI x 1.00 (MAME routes). The OKI bank register is 0 after reset.

## 10. Verification of this document

`refrender.py` implements sections 6.2-6.8. Against MAME 0.289 captures (`capture_frames.lua`:
shares + rendered bitmap) every frame is identical: logicpro, karianx and logicpr2, 12 attract
frames each (frames 100-4800), covering flipped sprites and all four priority levels. One capture
detail: MAME's `screen:pixels()` converts the indexed bitmap with the palette current at the time
of the call, so frame N's pixels are compared with frame N+1's palette.
