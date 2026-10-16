# Verification

Everything was checked against MAME 0.289 (MAME's own ROM-region memory, rendered frames, 68000 bus
traces and Z80 chip-write streams as references, captured with Lua scripts). The tooling (Python
reference renderer, ModelSim benches, MAME Lua scripts) lives in the local, uncommitted
`local/devtools/`; ROM-derived data and MAME captures are never committed.

| # | What | Reference | Result |
| --- | --- | --- | --- |
| 1 | Hardware model (docs/HARDWARE.md as Python, `refrender.py`) | MAME's rendered pixels | **pixel-exact**: logicpro, karianx, logicpr2 - 12 attract + 12 gameplay frames each (72 frames), incl. flipped sprites and all four sprite priorities |
| 2 | MRAs (`romtool.py mracheck`: independent MRA interpreter incl. `repeat` and `map`) | MAME ROM regions (`dump_regions.lua`) | **identical** streams for all 5 sets (logicpro, croquis, croquisg, karianx, logicpr2) |
| 3 | RTL video (`render_tb.sv`: dnm_video + SDRAM arbiter + SDRAM model, real ROM images, fed with MAME state captures) | MAME's rendered pixels | **pixel-exact** on the same 72 frames; zero render overruns |
| 4 | Whole board from reset (`system_tb.sv`: dnm_core with the real ROMs) - 68000 bus trace | MAME bus trace (`bus_trace.lua`) | karianx: all **300,000** captured transactions identical (104 ms); logicpro: **242,548** identical, logicpr2: **287,460** identical - each through the first vblank interrupt (see note) |
| 4b | Whole board from reset - frames (`system_tb +DUMP`, `syscmp.py`) | MAME frames | karianx: frames 4-9 from power-on **identical**; logicpr2: frames 8 and 11-14 **identical**, frames 9-10 show text that the boot code draws while the frame is scanned out (every differing pixel equals MAME's next frame: raster vs MAME's per-frame snapshot) |
| 5 | Sound board (`sound_tb.sv`: Z80 + YM3812 + OKI with MAME's sound-latch commands replayed at MAME's times) | MAME's Z80 chip-write stream (`sound_trace.lua`) | Logic Pro, 11.8 s of attract: all **4,106** YM3812 / OKI / bank writes match MAME (the only difference: two register pairs written in swapped order at 11.27 s, where the YM timer interrupt fell ~90 us earlier relative to the music code); max time offset 0.1 ms |
| 5b | Audio levels (sound bench output, low-passed to 20 kHz) | `mame -wavwrite` (and a YM3812-only recording with the OKI writes neutralised by Lua) | OKI peaks 11008 / 18192 vs MAME 10954 / 18538, per-second RMS within 3-10 %; YM3812 RMS 1423 / 3300 vs MAME 1450 / 3179 |
| 6 | Quartus 17.0 full compile | timing analysis | all clocks meet setup and hold (core 100 MHz: +0.42 ns setup) |

Notes:

* Bus traces after the first interrupt: the benches run the raster at exactly MAME's 1/60 s
  (`DNM_MAME_TIMING`, simulation only; the core's own raster is 59.64 Hz), so interrupts arrive at
  the same time. FX68K and MAME's 68000 still differ by a few clocks over ~100 ms of code (the
  RTL was 0.74 us behind at the second interrupt), so a later interrupt is taken one polling-loop
  iteration apart; from there the two traces are the same program at a slightly different phase.
  This matches what the owner's Final Star Force core found.
* Frame numbering: the bench counts vblank starts, MAME's `frame_number` is one ahead of that at
  power-on; `syscmp.py` searches the captured MAME frames for the identical one.
* jtopl's internal clock divider only gets an initial value under the `SIMULATION` macro (on the
  FPGA it powers up at 0); the benches define it, otherwise the YM3812 stays X in ModelSim and the
  Z80 never gets its timer interrupt.
* MAME's `screen:pixels()` converts the indexed bitmap with the palette current at the time of the
  call, so frame N is compared with the palette of frame N+1.
* The 68000 runs at MAME's cycle schedule (cache misses are repaid, docs/ARCHITECTURE.md), which is
  what makes the bus traces line up transaction for transaction.
