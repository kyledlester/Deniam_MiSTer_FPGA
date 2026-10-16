#!/usr/bin/env python3
"""Deniam core ROM tool (never writes ROM data into the repository; outputs go to local/).

  romtool.py mra [--game SET|all]                 write MRA/*.mra (MRA/_alternatives for the others)
  romtool.py mracheck [--game SET] [--romdir DIR] rebuild the ROM stream by interpreting the MRA XML
                                                  the way Main_MiSTer does and compare it with the
                                                  layout built from MAME's own region dumps
                                                  (local/<set>/regions, scripts in local/devtools)
  romtool.py images --game SET [--romdir DIR]     local/<set>/sim/: sdram.hex (SDRAM image as the
                                                  loader writes it), audiocpu.hex, stream.bin

Stream layout and SDRAM placement: docs/MRA_FORMAT.md.
"""
import argparse, os, sys, zipfile, zlib
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROMDIR = os.path.join(os.path.expanduser("~"), "Downloads", "mame", "roms")

# stream regions: name, stream offset, length, kind ('word' = 16-bit region, 'byte')
LAYOUT = [
    ("maincpu",   0x000000, 0x100000, "word"),
    ("chars",     0x100000, 0x180000, "byte"),
    ("spritegfx", 0x280000, 0x400000, "word"),
    ("oki",       0x680000, 0x100000, "byte"),
    ("audiocpu",  0x780000, 0x010000, "byte"),
]

COINAGE = ('0,1,2', 'Coinage', 'Free Play,2C1C,3C1C,1C2C,3C2C,1C3C,2C3C,1C1C')
LOGIC_DIPS = [
    COINAGE,
    ('3,4', 'Play Time', 'Fastest,Slow,Fast,Normal'),
    ('5,6', 'Difficulty', 'Hardest,Easy,Hard,Normal'),
    ('7', 'Demo Sounds', 'Off,On'),
]
KARIAN_DIPS = [
    COINAGE,
    ('3,4', 'Difficulty', 'Hard,Very Easy,Easy,Normal'),
    ('5', 'Demo Music', 'Off,On'),
    ('7', 'Service Mode', 'On,Off'),
]

# part lists per region: words = list of (even file, odd file) pairs or ("plain", file); bytes = files.
# A region shorter than its stream slot is padded with zeros (MAME regions are zero-filled).
LOGICPRO_COMMON = {
    "chars": ["logicpro.r5", "logicpro.r6", "logicpro.r7"],
    "spritegfx": [("logicpro.r9", "logicpro.r8")],
    "oki": ["logicpro.r1"],
    "audiocpu": ["logicpro.r2"],
}
LOGICPRO = dict(year="1996", manufacturer="Deniam", category="Puzzle", cfg=0x00, dips=LOGIC_DIPS,
                board="deniam-16b", short="Logic Pro")
GAMES = {
    "logicpro": dict(LOGICPRO, name="Logic Pro (Japan)", parent="croquis",
                     files=dict(LOGICPRO_COMMON, maincpu=[("logicpro.r4", "logicpro.r3")])),
    "croquis": dict(LOGICPRO, name="Croquis (Korea)", parent=None,
                    files=dict(LOGICPRO_COMMON, maincpu=[("sys_e0", "sys_o0")])),
    "croquisg": dict(LOGICPRO, name="Croquis (Germany)", parent="croquis",
                     files=dict(LOGICPRO_COMMON, maincpu=[("r4.bin", "r3.bin")])),
    "karianx": dict(name="Karian Cross (Rev. 1.0)", parent=None, year="1997", manufacturer="Deniam",
                    category="Puzzle", cfg=0x02, dips=KARIAN_DIPS, board="deniam-16b", short="Karian Cross",
                    files={"maincpu": [("even", "odd")], "chars": ["bkg1", "bkg2", "bkg3"],
                           "spritegfx": [("obj4", "obj1"), ("obj5", "obj2"), ("obj6", "obj3")],
                           "oki": ["voi"], "audiocpu": ["snd"]}),
    "logicpr2": dict(name="Logic Pro 2 (Japan)", parent=None, year="1997", manufacturer="Deniam",
                     category="Puzzle", cfg=0x01, dips=LOGIC_DIPS, board="deniam-16c", short="Logic Pro 2",
                     files={"maincpu": [("lp2-2", "lp2-1")], "chars": ["log2-b01", "log2-b02", "log2-b03"],
                            "spritegfx": [("plain", "obj")], "oki": ["log2-s01"]}),
}
# Owner's choice: Logic Pro is the main set of the Logic Pro / Croquis family (MAME's parent is
# croquis); the Croquis sets are alternatives.
MAIN_SETS = {"logicpro", "karianx", "logicpr2"}


def zips_for(game):
    g = GAMES[game]
    names = [game] + ([g["parent"]] if g["parent"] else [])
    return [n + ".zip" for n in names]


def read_file(zips, name, crc=None):
    """Resolve a part like MiSTer's MRA loader (Main_MiSTer FileOpenZip): try each zip of the list in
    order; inside a zip, look the file up by CRC first (merged sets), then by name."""
    for z in zips:
        if os.path.exists(z):
            with zipfile.ZipFile(z) as zf:
                if crc is not None:
                    for info in zf.infolist():
                        if info.CRC == crc:
                            return zf.read(info)
                if name in zf.namelist():
                    return zf.read(name)
    raise FileNotFoundError(f"{name} not found in {zips}")


def file_info(game, romdir, name):
    for z in zips_for(game):
        p = os.path.join(romdir, z)
        if os.path.exists(p):
            with zipfile.ZipFile(p) as zf:
                if name in zf.namelist():
                    i = zf.getinfo(name)
                    return "%08x" % i.CRC, i.file_size
    raise FileNotFoundError(name)


def stream_len(game):
    return 0x780000 if "audiocpu" not in GAMES[game]["files"] else 0x790000


# ----------------------------------------------------------------------------- MRA writer
def mra_text(game, romdir):
    g = GAMES[game]
    lines = []
    lines.append("<!--")
    lines.append(f"  {g['name']} - {g['manufacturer']} {g['year']} - MRA for the Deniam MiSTer core.")
    lines.append(f"  MAME set {game} (MAME 0.289 sega/deniam.cpp, {g['board']}). No ROM data is embedded in this file.")
    lines.append("  Generated by scripts/romtool.py mra ; layout documented in docs/MRA_FORMAT.md.")
    lines.append("")
    lines.append(f"  ioctl index 1: board config byte {g['cfg']:02X} (bit 0 = deniam-16c, bit 1 = Karian Cross scroll offsets).")
    lines.append("  ioctl index 0 stream (hps_io WIDE=1; 16-bit regions arrive as big-endian words):")
    for name, off, ln, kind in LAYOUT:
        if name in g["files"]:
            lines.append(f"    {off:06X}-{off + ln - 1:06X}  {name:9s} MAME region '{name}' ({kind}, zero padded)")
    lines.append("")
    lines.append("  DIP switches (index 254): byte 0 = DSW, MAME port value (active low).")
    lines.append("-->")
    lines.append("<misterromdescription>")
    lines.append(f"    <name>{g['name']}</name>")
    lines.append(f"    <setname>{game}</setname>")
    if g["parent"]:
        lines.append(f"    <parent>{g['parent']}</parent>")
    lines.append("    <rbf>Deniam</rbf>")
    lines.append("    <mameversion>0289</mameversion>")
    lines.append(f"    <year>{g['year']}</year>")
    lines.append(f"    <manufacturer>{g['manufacturer']}</manufacturer>")
    lines.append(f"    <category>{g['category']}</category>")
    lines.append("    <players>2</players>")
    lines.append("    <joystick>4-way</joystick>")
    lines.append("    <rotation>horizontal</rotation>")
    lines.append("    <buttons names=\"Button 1,Button 2,Button 3,Start,Coin,Pause\" default=\"A,B,X,Start,Select,L\"/>")
    lines.append("")
    lines.append("    <switches default=\"FF\" base=\"16\">")
    for bits, name, ids in g["dips"]:
        lines.append(f"        <dip bits=\"{bits}\" name=\"{name}\" ids=\"{ids}\"/>")
    lines.append("    </switches>")
    lines.append("")
    lines.append("    <rom index=\"1\">")
    lines.append(f"        <part>{g['cfg']:02X}</part>")
    lines.append("    </rom>")
    lines.append(f"    <rom index=\"0\" zip=\"{'|'.join(zips_for(game))}\" md5=\"None\">")
    for name, off, ln, kind in LAYOUT:
        if name not in g["files"]:
            continue
        lines.append(f"        <!-- {off:06X} {name} -->")
        used = 0
        for p in g["files"][name]:
            if isinstance(p, tuple) and p[0] == "plain":
                crc, sz = file_info(game, romdir, p[1])
                lines.append(f"        <part name=\"{p[1]}\" crc=\"{crc}\"/>")
                used += sz
            elif isinstance(p, tuple):
                ce, se = file_info(game, romdir, p[0])
                co, so = file_info(game, romdir, p[1])
                lines.append("        <interleave output=\"16\">")
                lines.append(f"            <part name=\"{p[0]}\" crc=\"{ce}\" map=\"10\"/>")
                lines.append(f"            <part name=\"{p[1]}\" crc=\"{co}\" map=\"01\"/>")
                lines.append("        </interleave>")
                used += se + so
            else:
                crc, sz = file_info(game, romdir, p)
                lines.append(f"        <part name=\"{p}\" crc=\"{crc}\"/>")
                used += sz
        if used < ln:
            lines.append(f"        <part repeat=\"0x{ln - used:X}\">00</part>")
    lines.append("    </rom>")
    lines.append("</misterromdescription>")
    return "\n".join(lines) + "\n"


def mra_path(game):
    g = GAMES[game]
    fn = g["name"] + ".mra"
    if game not in MAIN_SETS:
        return os.path.join(ROOT, "MRA", "_alternatives", "_" + g["short"], fn)
    return os.path.join(ROOT, "MRA", fn)


# ----------------------------------------------------------------------------- MRA interpreter
def stream_from_mra(path, romdir):
    """Interpret the MRA's index-0 <rom> the way the MiSTer main binary does (subset used here:
    parts with name/crc, hex data parts with repeat, interleave output=16 with map)."""
    root = ET.parse(path).getroot()
    rom = [r for r in root.findall("rom") if r.get("index") == "0"][0]
    zips = [os.path.join(romdir, z) for z in rom.get("zip").split("|")]
    out = bytearray()

    def part_bytes(p):
        rep = int(p.get("repeat", "1"), 0)
        if p.get("name") is None:
            return bytes.fromhex("".join(p.text.split())) * rep
        d = read_file(zips, p.get("name"), int(p.get("crc"), 16) if p.get("crc") else None)
        if p.get("crc") and "%08x" % zlib.crc32(d) != p.get("crc"):
            raise ValueError(f"CRC mismatch {p.get('name')}")
        return d * rep

    for el in rom:
        if el.tag == "part":
            out += part_bytes(el)
        elif el.tag == "interleave":
            width = int(el.get("output")) // 8
            parts = [(part_bytes(p), p.get("map")) for p in el.findall("part")]
            n = len(parts[0][0])
            # map is written MSB first; output byte i = digit i from the right; digit v != 0 means
            # the part's byte v-1 of each unit goes there (Main_MiSTer rom_data)
            words = n // max(1, sum(c != "0" for c in parts[0][1]))
            buf = bytearray(words * width)
            for data, m in parts:
                digits = [int(c, 16) for c in reversed(m)]
                per = sum(v != 0 for v in digits)
                for w in range(words):
                    for lane, v in enumerate(digits):
                        if v:
                            buf[w * width + lane] = data[w * per + v - 1]
            out += buf
    return bytes(out)


def stream_to_words(stream):
    """ioctl_dout sequence (WIDE=1): word i = stream[2i] | stream[2i+1] << 8"""
    return [stream[i] | (stream[i + 1] << 8) for i in range(0, len(stream), 2)]


# ----------------------------------------------------------------------------- expected layout
def expected_stream(game):
    """The stream the core expects, built from MAME's region dumps (bytes in region order):
    'word' regions as ioctl words {region 2k, region 2k+1} (= stream bytes 2k+1, 2k), 'byte' as is."""
    reg = os.path.join(ROOT, "local", game, "regions")
    out = bytearray(stream_len(game))
    for name, off, ln, kind in LAYOUT:
        if name not in GAMES[game]["files"]:
            continue
        d = open(os.path.join(reg, name + ".bin"), "rb").read()[:ln]
        if kind == "word":
            sw = bytearray(ln)
            sw[0::2] = d[1::2]
            sw[1::2] = d[0::2]
            d = bytes(sw)
        out[off:off + ln] = d
    return bytes(out)


# ----------------------------------------------------------------------------- loader model
def sdram_image(stream):
    """dnm_loader.sv as Python: returns {word address: 16-bit value}"""
    words = stream_to_words(stream)
    img = {}
    for wi, d in enumerate(words):
        a = wi * 2
        if a < 0x100000:
            img[a >> 1] = d
        elif a < 0x280000:
            o = a - 0x100000
            t, r, p = (o >> 3) & 0xffff, (o >> 1) & 3, o >> 19
            img[0x080000 + (t << 4 | r << 2 | p)] = ((d & 0xff) << 8) | (d >> 8)
        elif a < 0x680000:
            img[0x180000 + ((a - 0x280000) >> 1)] = d
        elif a < 0x780000:
            img[0x380000 + ((a - 0x680000) >> 1)] = d
    return img


def cmd_images(game, romdir):
    out = os.path.join(ROOT, "local", game, "sim")
    os.makedirs(out, exist_ok=True)
    stream = stream_from_mra(mra_path(game), romdir)
    open(os.path.join(out, "stream.bin"), "wb").write(stream)
    img = sdram_image(stream)
    with open(os.path.join(out, "sdram.hex"), "w") as f:
        f.write("".join("%04x\n" % img.get(a, 0) for a in range(0x400000)))
    with open(os.path.join(out, "audiocpu.hex"), "w") as f:
        z = stream[0x780000:0x790000] if len(stream) > 0x780000 else bytes(0x10000)
        f.write("".join("%02x\n" % b for b in z))
    print(f"images written to {out}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd")
    ap.add_argument("--game", default="all")
    ap.add_argument("--romdir", default=ROMDIR)
    a = ap.parse_args()
    games = list(GAMES) if a.game == "all" else [a.game]
    if a.cmd == "mra":
        for g in games:
            p = mra_path(g)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w", newline="\n").write(mra_text(g, a.romdir))
            print("wrote", os.path.relpath(p, ROOT))
    elif a.cmd == "mracheck":
        bad = 0
        for g in games:
            s = stream_from_mra(mra_path(g), a.romdir)
            exp = expected_stream(g)
            ok = s == exp
            if not ok and len(s) == len(exp):
                i = next(k for k in range(len(s)) if s[k] != exp[k])
                print(f"  first difference at stream byte {i:#x}")
            print(("PASS" if ok else "FAIL") + f" mracheck {g}: {len(s):#x} bytes (expected {len(exp):#x})")
            bad += not ok
        sys.exit(bad)
    elif a.cmd == "images":
        for g in games:
            cmd_images(g, a.romdir)


if __name__ == "__main__":
    main()
