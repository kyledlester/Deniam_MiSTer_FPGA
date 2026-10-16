# Architecture

```
                     clk_sys 100 MHz (dnm_pll) - everything is a clock enable of it
 HPS ioctl ──► dnm_loader ──► SDRAM (via dnm_sdram_arb), Z80 ROM (BRAM 64K x 8)
                                   ▲  ▲  ▲  ▲
           dnm_rom_cache (68000 ROM)┘  │  │  └ dnm_sprites
           OKI line cache (dnm_sound) ─┘  └── dnm_tilemap (BG, FG, text)
                          sdram.sv (ch1, 4-word bursts) ─── SDRAM 32 MB
 dnm_main (FX68K 12.5 MHz; BRAM work RAM, tilemap RAM, text RAM, sprite RAM, palette; I/O; IRQ 4;
           coin/display register; copy of the video registers in text RAM)
   ├─ video read ports ─► dnm_video (line buffers, priority mixer, palette lookup) ─► rgb
   └─ sound latch (16b) / chip host writes (16c) ─► dnm_sound (clk_snd 50 MHz: T80 6.25 MHz,
                                                  jtopl2 4.17 MHz, jt6295 1.04 MHz) ─► mono audio
 dnm_video_timing (400 x 262 @ 6.25 MHz) ─► vblank event at line 224: IRQ 4
 Deniam.sv: hps_io, pause, CRT Adjust, screen_rotate (vertical monitors), arcade_video
```

## Clocks

| Enable | Rate | Derivation |
| --- | --- | --- |
| ce_pix | 6.25 MHz | clk_sys / 16 |
| phi1/phi2 | 12.5 MHz 68000 | one phase every 4 clk_sys; every 3 while repaying cache-miss wait clocks |
| Z80 | 6.25 MHz | clk_snd / 8 |
| YM3812 | 4.1667 MHz | clk_snd / 12 |
| OKI | 1.0417 MHz | clk_snd / 48 |

All rates are exact (100 MHz = 4 x the board's 25 MHz crystal). The 68000's schedule is kept
exact despite program-cache misses: dnm_main reports each wait clock (a phi1 beyond the second while
AS is low) and dnm_clocks issues phases 3 clocks apart until the debt is repaid (the owner's Final
Star Force scheme). `pause` freezes the 68000, the sound section and the interrupt event; the raster
keeps running.

## Memory

| Data | Resource |
| --- | --- |
| 68000 program 1 MB | SDRAM, behind a 64 KB direct-mapped cache (4-word lines) in BRAM: a hit is a zero-wait-state access, a miss costs about 1-2 wait states |
| work RAM 64 KB, tilemap RAM 64 KB, text RAM 4 KB | BRAM, dual-ported (CPU / video) |
| palette 4 KB, sprite RAM (words 0-4 of 128 entries) | BRAM, CPU write / video read (both are write-only for the CPU on the PCB) |
| Z80 program 64 KB, RAM 2 KB | BRAM |
| characters, sprites, OKI samples (~7 MB) | SDRAM (docs/MRA_FORMAT.md) |

## Bus timing

The 68000 bus uses the owner's NA-1 FX68K transport (held request, registered DTACK) and a backend
that answers block-RAM reads (and program-cache hits) after 2 clocks and writes immediately.

## Video

`dnm_video` renders one line ahead of the raster. For board line y+1, `dnm_tilemap` draws the 320
visible pixels of BG, FG and text into three line buffers (41 tile fetches per layer: one
tilemap/text RAM read plus one SDRAM burst holding the three bit planes of two tile rows), and
`dnm_sprites` walks the 128 sprite entries from 127 down to 0, streaming each covering row's nibbles
from the sprite ROM at one nibble per clock (8-byte burst blocks) into the sprite line buffer with
MAME's first-claim-wins rule. The output side reads the four buffers per dot, applies the sprite
priority rule (docs/HARDWARE.md 6.6) and looks up the palette. The scroll / page registers and the
display enable are latched once per frame (MAME applies them per frame). Budget: a line is 6400
clk_sys; the busiest captured line needs about 47 sprite bursts and 670 nibbles, the tilemaps 123
bursts.

## Sound

deniam-16b: the Z80 sound board (latch with NMI, YM3812 IRQ on INT, OKI bank on port 07 bit 6).
deniam-16c (Logic Pro 2): the Z80 is held in reset and the 68000's writes to the OKI, its bank
register and the YM3812 are passed to the same chips as one-clock host strobes (toggle crossing to
clk_snd); the OKI status is copied back for the 68000's reads. The OKI sample ROM is read through an
8-byte line cache in front of SDRAM.

## Debug overlay

OSD Debug submenu; drawn at the top left of the picture.

| Line | Left 16 bits | Right 16 bits |
| --- | --- | --- |
| 1 | - | 68000 program address (24 bits) |
| 2 | frames (vblanks) | IRQ 4 acknowledges |
| 3 | sound-latch writes (68000) | sound-latch reads (Z80) |
| 4 | Z80 interrupts (YM3812) | program cache misses |
| 5 | YM3812 writes | OKI writes |
| 6 | render overruns | board config byte, `loaded` flag |

## Verification

See [VERIFICATION.md](VERIFICATION.md).
