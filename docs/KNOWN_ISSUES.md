# Known issues and limitations

* **Video timing is not PCB-measured.** MAME has no raster model for this board (60 Hz, vblank at
  line 224). The core uses a System 16-style raster from the 25 MHz crystal: 6.25 MHz pixel clock,
  400 x 262, 15.625 kHz / 59.64 Hz. Native CRT output follows it.
* **Per-frame video registers.** Scroll, page select and display enable are latched once per frame
  (as MAME applies them); tilemap, text and sprite RAM are read live, line by line, like a raster
  board. If a game rewrote sprite or tilemap RAM in the middle of the visible frame the core would
  show the change from that line on, where MAME shows the whole frame at vblank. Seen only on
  Logic Pro 2's boot screen, where text appears a frame earlier on the lines already drawn.
* **Program ROM cache.** The 1 MB 68000 program runs from SDRAM through a 64 KB cache. A miss costs
  the 68000 about two wait clocks, repaid by briefly running it faster (dnm_clocks.sv), so over any
  stretch longer than a few microseconds the CPU runs exactly as fast as MAME's 68000.
* **Effects MAME does not emulate either.** Logic Pro's slight screen darkening after a coin (probably
  the palette's bit-15 shadow) and the 4 pixels of left-edge garbage of the real PCB are not
  reproduced; the core shows what MAME shows.
* **Logic Pro 2 sound test.** The original program's sound-test menu cannot change the selection;
  this is a bug of the real PCB (MAME notes it), not of the core.
* **Logic Pro DIP switches** follow MAME, which uses the Logic Pro 2 settings for Logic Pro and
  Croquis and marks them as possibly wrong.
* **Sprite row length.** A sprite row is read for at most 512 bytes (MAME's limit in the normal
  direction; MAME has none for flipped sprites). Real data always ends a row long before.
* **68000 timing vs MAME.** FX68K and MAME's 68000 differ by a few clocks over long stretches of
  code, so a vblank interrupt can occasionally be taken one polling-loop iteration earlier or later
  than in MAME. This has no visible effect.
* **Sound levels** follow MAME's mix (YM3812 x 0.6, OKI x 1.0) and were measured within a few
  percent of `mame -wavwrite`; loud passages where both chips peak together can clip slightly
  sooner than MAME's floating-point mixer.
