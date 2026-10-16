# Reused components and licences

The core is distributed under GPL-3.0-or-later (`LICENSE`); the MiSTer framework under its own
terms (`LICENSE.MiSTer`, GPL-2.0-or-later). All reused components are GPL-compatible.

| Component | Path | Source | Revision | Author(s) | Licence | Modifications |
| --- | --- | --- | --- | --- | --- | --- |
| MiSTer framework | `sys/` | MiSTer-devel/Template_MiSTer via the owner's Final Star Force core | `3ea1134` | Sorgelig et al. | GPL-2.0+ (see headers) | none |
| FX68K 68000 | `rtl/vendor/fx68k/` | github.com/ijor/fx68k via the owner's NA-1/NA-2 core | `0602ee4627b10f301298f2673d826cdd6baa9327` | Jorge Cwik | GPL-3.0-or-later | none (`microrom.mem`/`nanorom.mem` at repo root because the CPU `$readmemb`s them by name) |
| T80 Z80 | `rtl/vendor/t80/` | MiSTer-devel/ZX-Spectrum_MISTer `rtl/T80` via Neratte Chu | `d41751d0afc8abf75f31ff1094bf9731e7a1695c` | Daniel Wallner, MikeJ, TobiFlex, Sorgelig, brNX | BSD-style (file headers) | none; `T80s.vhd` instantiated |
| jtopl YM3812 | `rtl/vendor/jtopl/` | github.com/jotego/jtopl `hdl/` | `7ac0c819ad274e208206f2acccbbde80aa06ed1a` | Jose Tejada Gomez | GPL-3.0-or-later | none (only the OPL/OPL2 files; jtopl2 instantiated) |
| jt6295 OKI M6295 | `rtl/vendor/jt6295/` | github.com/jotego/jt6295 `hdl/` | `7d76b0be8cd8f85f3ae741178c9830b20e2071a1` | Jose Tejada Gomez | GPL-3.0-or-later | none (used with INTERPOL=0, so jtframe's FIR is not needed) |
| SDRAM controller | `rtl/vendor/sdram.sv` | GBA_MiSTer lineage via the owner's NA-1 -> NB-1 -> Neratte Chu cores | SHA-1 `a5c1f349e1dc9f23ddb600b59d95427c9f6b0500` | Sorgelig (hamsterworks parts) + owner's byte enables / refresh parameter | GPL-3.0-or-later | none here |
| CRT Adjust | `rtl/vendor/crt_adjust.sv` | MiSTer-CRT-Adjust (rmonic79) | SHA-1 `ddc1b6d311f26d50cc30ce1a83df9fc539830fbc` | Umberto Parisi | GPL-3.0-or-later | none |
| Pause | `rtl/vendor/pause.v` | JimmyStones/Pause_MiSTer via Arcade-Pacman_MiSTer | SHA-1 `d5a5effd1bf91ae788436639bae3c63b8fe40347` | Jim Gregory | GPL-3.0-or-later | none |
| 68000 bus glue | `rtl/dnm/dnm_cpu68k.sv`, `dnm_cpu_bus.sv` | owner's Namco NA-1/NA-2 core (`na1_cpu.sv`, `na1_cpu_bus.sv`) via Final Star Force | - | owner | GPL-3.0-or-later | module names |
| CRT Adjust glue | `rtl/dnm/dnm_crt_adjust.sv` | owner's Final Star Force core (`fsf_crt_adjust.sv`, from Neratte Chu / R-Shark) | - | owner | GPL-3.0-or-later | module name, H-Position limits for this raster |

Everything under `rtl/dnm/` not listed above and `scripts/romtool.py` were written for this project; the RAM primitives, clock enables, SDRAM arbiter, program cache, loader skeleton, overlay and OKI cache follow the owner's Final Star Force core.

MAME (BSD-3-Clause / GPL-2.0+) is used only as a reference (`sega/deniam.cpp` by Nicola Salmoria):
no MAME code is included.
