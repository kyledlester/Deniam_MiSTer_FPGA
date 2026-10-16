# Building

## Requirements

* Intel Quartus Prime Lite **17.0** (the MiSTer standard; the `sys/` framework targets it).
* Windows PowerShell for `scripts/build.ps1` (or use the Quartus GUI).
* Python 3 only for regenerating MRAs (`scripts/romtool.py`).

## Compile

* GUI: open `Deniam.qpf` and run *Processing > Start Compilation*.
* Command line: `powershell -ExecutionPolicy Bypass -File scripts\build.ps1`
  (optionally `-QuartusBin <path to quartus\bin64>`, or `-MapOnly` for a quick analysis & synthesis
  check). The script waits until no other Quartus job is running on the machine, runs the full
  flow, and writes `build/quartus.log` and `build/build-summary.txt` (resources, timing per clock,
  errors).

Either way the post-flow script `scripts/release_rbf.tcl` copies `output_files/Deniam.rbf` to
`Releases/Deniam_YYYYMMDD.rbf`. The MRAs name the core without the date (`<rbf>Deniam</rbf>`);
MiSTer loads the newest dated file in `_Arcade/cores/`.

Check the timing summary: every setup and hold slack must be positive (core clock
`emu|pll...general[0]` 100 MHz, sound clock `general[1]` 50 MHz).

## MRAs

The MRAs are generated, not hand-written:

```
python scripts/romtool.py mra                      # all sets (or --game logicpro, karianx, ...)
python scripts/romtool.py mracheck                 # needs the ROM zips and MAME region dumps in local/
```

## Verification

The core was developed against MAME 0.289 with a Python reference renderer, ModelSim benches and
MAME Lua capture scripts (frames, 68000 bus traces, sound-chip write streams). That tooling depends
on locally captured MAME data and ROM images and is not part of this repository; the results are
summarised in [VERIFICATION.md](VERIFICATION.md).
