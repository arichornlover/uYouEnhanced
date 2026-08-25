# The Scripts

Tooling for uYouEnhanced. All pure Python 3 stdlib (plus
[capstone](https://pypi.org/project/capstone/) for the disassembler) — runs on
Windows, macOS, or Linux without needing Mac/Xcode. PowerShell scripts are for
Windows-side framework maintenance.

## Script index

### 📦 Build & Release — `Scripts/build/`

| Script | Purpose |
|---|---|
| `build_unofficial_deb.py` | Package an UNOFFICIAL uYou deb: takes the pristine `Tweaks/uYou/com.miro.uyou_3.0.4_iphoneos-arm.deb` + a compiled tweak dylib, rebrands 3.0.4 → 3.0.5 and injects it. **Not** used by IPA builds. |
| `rebrand_uyou.py` | Rebrand an extracted `uYou.dylib`: version strings 3.0.4 → 3.0.5 (ASCII) + credit line → UNOFFICIAL notice (UTF-16LE). Also called by the Makefile during IPA builds. |

```bash
python Scripts/build/build_unofficial_deb.py \
  Tweaks/uYou/com.miro.uyou_3.0.4_iphoneos-arm.deb theos/obj/uYouEnhanced.dylib
```

### 🎬 FFmpegKit / Vendor maintenance — `Scripts/ffmpegkit/`

The download pipeline's ffmpeg backend lives in `Sources/MediaKit/`. These
scripts maintain the frameworks behind it.

| Script | Purpose |
|---|---|
| `slim_vendor.ps1` | Strip `Vendor/*.framework` down to runtime essentials: removes nested duplicate frameworks, `Headers/`, `Modules/`, `PrivateHeaders/`, stray files. Keeps binary + Info.plist + LICENSE. |
| `generate_framework_plists.ps1` | Generate a minimal `Info.plist` for any framework missing one (signing tools expect it). |
| `analyze_vendor_deps.ps1` | Parse Mach-O load commands of every `Vendor/*.framework` and print each one's dylib dependencies. |
| `scan_rpath_refs.ps1` | Brute-force scan binaries for `@rpath/...` references — quick cross-check of inter-framework links. |
| `fetch_ffmpegkit_wrapper.sh` | Cherry-pick the FFmpegKitNext ObjC wrapper sources (`FFmpegKit`, `FFmpegSession`, …) into `Sources/MediaKit/FFmpegKitWrapper/` as reference-only copies (never compiled). |

```powershell
# After adding/replacing frameworks in Vendor\:
powershell -File Scripts\ffmpegkit\slim_vendor.ps1
powershell -File Scripts\ffmpegkit\generate_framework_plists.ps1
```

See `Docs/FFmpegKitNext.md` for the full backend story.

### 🔍 Crash analysis — `Scripts/crash-analysis/`

`.github/workflows/crash-analysis.yml` downloads a built IPA artifact, extracts
the app binary + injected dylibs, and produces `crash-analysis-report/analysis_report.txt`
with a selector audit plus reference dumps in `refdata/`.

| Script | Purpose |
|---|---|
| `parse_ips.py` | Parse an Apple `.ips` crash report: real exception reason, image table, backtrace with function-boundary mapping |
| `local_symbolicate.py` | Map `.ips` imageOffset values to function starts using `refdata/` |
| `local_hook_audit.py` | Diff every tweak dylib's defined selectors against YouTube's implemented set (uses `refdata/`) |
| `crash_analyzer.py` | Mach-O parser: `info`, `selectors`, `syms`, `funcstarts`, `symbolicate <dylib> <offsets>`, `audit <ytbin> <dylib>` |
| `disasm_find_sel.py` | Disassemble a function (capstone) and resolve `__objc_selrefs` references |
| `resolve_selref.py` | Decode chained-fixup selector slots into selector strings |
| `hunt_cstring.py` | Dump `__cstring` strings from a Mach-O matching a regex |

## Typical crash debugging flow

1. Crash happens → pull the `.ips` from the device
   (Settings → Privacy & Security → Analytics → Analytics Data)
2. `python Scripts/crash-analysis/parse_ips.py YouTube-<date>.ips`
   → shows the true backtrace; note any frame inside `uYouEnhanced.dylib`
3. Download that build's IPA, extract the named `.dylib` into the repo root
4. `python Scripts/crash-analysis/disasm_find_sel.py uYouEnhanced.dylib 0x<start> 0x<end>`
   around the crashing offset, then
   `python Scripts/crash-analysis/resolve_selref.py uYouEnhanced.dylib 0x<selref...>`
   → prints the exact missing selector
5. Guard or gate the matching hook in `Sources/`

`refdata/` is produced by the CI workflow; refresh it after each new build so
offsets stay accurate.

I apologize if this sounds complicated, I had to write scripts to get the flow going when it came to fixing the crashes with the uYouEnhanced tweak.

## Notes

- `__pycache__/` is local-only — don't commit it.
- The `.ps1` scripts target Windows PowerShell 5.1+; run them from the repo root.
- Keep LGPL license headers intact in any vendored wrapper sources.