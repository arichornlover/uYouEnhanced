"""Parse an Apple .ips crash report and symbolicate tweak frames locally.
Usage: python Scripts/parse_ips.py path/to/crash.ips
"""
import json
import os
import sys

REFDIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "crash-analysis-report", "refdata"))

DYLIB_NAMES = [
    "YouSpeed", "libcolorpicker", "YouPiP", "YouGroupSettings",
    "DontEatMyContent", "YouLoop", "uYou", "iSponsorBlock",
    "YTABConfig", "libFLEX", "YTVideoOverlay", "YouTimeStamp",
    "uYouEnhanced", "YTweaks", "YouSlider", "YTIcons",
    "YouTubeDislikesReturn", "YouQuality",
]


def load_ips(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    start = text.find("\n{")
    if start == -1:
        start = text.find("{")
    else:
        start += 1
    return json.loads(text[start:])


def load_funcstarts(index):
    p = os.path.join(REFDIR, f"dylib{index}_funcstarts.txt")
    if not os.path.exists(p):
        return []
    with open(p, encoding="utf-8", errors="replace") as f:
        out = []
        for line in f:
            s = line.strip()
            if s:
                out.append(int(s, 16))
        return sorted(out)


def main():
    doc = load_ips(sys.argv[1])

    reason = doc.get("exceptionReason", {})
    print("== Exception ==")
    print("  composed:", reason.get("composed_message", "?"))

    images = doc.get("usedImages", [])
    print(f"\n== Images ({len(images)}) ==")
    for i, img in enumerate(images):
        print(f"  [{i}] {img.get('name','?')}  {img.get('path','?')}")

    # map our dylib names -> refdata index
    refmap = {}
    for i, name in enumerate(DYLIB_NAMES, start=1):
        refmap[name + ".dylib"] = i

    bt = doc.get("lastExceptionBacktrace", [])
    print(f"\n== Backtrace ({len(bt)} frames) ==")
    for fr in bt:
        idx = fr.get("imageIndex", -1)
        off = fr.get("imageOffset", 0)
        sym = fr.get("symbol", "")
        imgname = images[idx].get("name", "?") if 0 <= idx < len(images) else "?"
        loc = f"{imgname}+{off:#x}"
        if sym:
            loc += f" ({sym}+{fr.get('symbolLocation',0)})"
        extra = ""
        key = imgname.lower()
        for dylib, n in refmap.items():
            if dylib.lower().startswith(key) and len(key) > 3:
                starts = load_funcstarts(n)
                prev = None
                for s in starts:
                    if s <= off:
                        prev = s
                    else:
                        break
                if prev is not None:
                    extra = f"  -> {dylib} funcstart {prev:#x} (+{off-prev:#x})"
                break
        print(f"  #{bt.index(fr):<2} {loc}{extra}")


if __name__ == "__main__":
    main()
