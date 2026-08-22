"""Find selectors DEFINED by each tweak dylib that YouTube 21.14.4 does NOT implement.

These are logos %hook registrations on nonexistent methods: the hook makes
respondsToSelector: return YES, YouTube calls it, %orig forwards -> unrecognized
selector / doesNotRecognizeSelector. Prime crash candidates.

Usage: python Scripts/local_hook_audit.py
"""
import os

REFDIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "crash-analysis-report", "refdata"))

DYLIB_NAMES = [
    "YouSpeed", "libcolorpicker", "YouPiP", "YouGroupSettings",
    "DontEatMyContent", "YouLoop", "uYou", "iSponsorBlock",
    "YTABConfig", "libFLEX", "YTVideoOverlay", "YouTimeStamp",
    "uYouEnhanced", "YTweaks", "YouSlider", "YTIcons",
    "YouTubeDislikesReturn", "YouQuality",
]

def load_set(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return {line.strip() for line in f if line.strip()}

def main():
    yt = load_set(os.path.join(REFDIR, "youtube_selectors.txt"))
    print(f"YouTube selectors: {len(yt)}\n")

    for i, name in enumerate(DYLIB_NAMES, start=1):
        p = os.path.join(REFDIR, f"dylib{i}_defined_selectors.txt")
        if not os.path.exists(p):
            continue
        defined = load_set(p)
        missing = sorted(s for s in defined if s not in yt)
        print(f"[{i:2d}] {name}: {len(missing)} defined-but-missing (of {len(defined)})")
        for s in missing[:40]:
            print(f"      {s}")
        if len(missing) > 40:
            print(f"      ... +{len(missing)-40} more")
        print()

if __name__ == "__main__":
    main()
