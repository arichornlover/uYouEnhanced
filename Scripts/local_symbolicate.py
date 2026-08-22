"""Local symbolication of .ips imageOffset values using crash-analysis-report refdata.

Usage: python Scripts/local_symbolicate.py 81012 [more offsets...]
"""
import glob
import os
import re
import sys

REFDIR = os.path.join(os.path.dirname(__file__), "..", "crash-analysis-report", "refdata")

DYLIB_NAMES = [
    "YouSpeed", "libcolorpicker", "YouPiP", "YouGroupSettings",
    "DontEatMyContent", "YouLoop", "iSponsorBlock", "YTABConfig",
    "libFLEX", "YTVideoOverlay", "YouTimeStamp", "uYouEnhanced",
    "YTweaks", "YouSlider", "YTIcons", "YouTubeDislikesReturn",
    "YouQuality",
]

def parse_int(tok):
    return int(tok, 16) if tok.lower().startswith("0x") else int(tok)

def load_funcstarts(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return sorted(parse_int(line.strip()) for line in f if line.strip())

def load_defined_symbols(path):
    """symbols.txt lines: '0xADDR 0xTYPE _name' -> {addr: name} for addr != 0."""
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 3:
                try:
                    addr = parse_int(parts[0])
                except ValueError:
                    continue
                if addr:
                    out[addr] = parts[2]
    return out

def main():
    offsets = [parse_int(a) for a in sys.argv[1:]]
    if not offsets:
        print("usage: local_symbolicate.py <offset> [...]")
        return

    for i, name in enumerate(DYLIB_NAMES, start=1):
        fs_path = os.path.join(REFDIR, f"dylib{i}_funcstarts.txt")
        syms_path = os.path.join(REFDIR, f"dylib{i}_symbols.txt")
        if not os.path.exists(fs_path):
            continue
        starts = load_funcstarts(fs_path)
        if not starts:
            continue
        lo, hi = starts[0], starts[-1]
        defined = load_defined_symbols(syms_path)

        for off in offsets:
            if off < lo or off > hi + 0x10000:
                status = "TOO SMALL / no coverage"
            else:
                status = "POSSIBLE OWNER"
            prev = None
            for s in starts:
                if s <= off:
                    prev = s
                else:
                    break
            sym = defined.get(prev, "?")
            delta = off - prev if prev is not None else 0
            prev_s = f"{prev:#x}" if prev is not None else "n/a"
            print(f"[{i:2d}] {name:22s} off={off:#x} "
                  f"text~[{lo:#x}-{hi:#x}] "
                  f"nearest_start={prev_s} "
                  f"(+{delta:#x}) sym={sym} -> {status}")

if __name__ == "__main__":
    main()
