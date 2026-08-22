# The Scripts

Crash-analysis tooling for uYouEnhanced. All pure Python 3 stdlib (plus
[capstone](https://pypi.org/project/capstone/) for the disassembler) — runs on
Windows, macOS, or Linux. Without needing Mac/Xcode.

## CI workflow

`.github/workflows/crash-analysis.yml` downloads a built IPA artifact, extracts
the app binary + injected dylibs, and produces an `analysis_report.txt` with a
selector audit (`crash_analyzer.py audit`) plus reference dumps in `refdata/`.

## Local tools

| Script | Purpose |
|---|---|
| `crash_analyzer.py` | Mach-O parser: `info`, `selectors`, `syms`, `funcstarts`, `symbolicate <dylib> <offsets>`, `audit <ytbin> <dylib>` |
| `parse_ips.py` | Parse an Apple `.ips` crash report: real exception reason, image table, full backtrace with per-frame function-boundary mapping |
| `local_hook_audit.py` | Diff every tweak dylib's defined selectors against YouTube's implemented set (uses `refdata/`) |
| `local_symbolicate.py` | Map `.ips` imageOffset values to function starts using `refdata/` |
| `disasm_find_sel.py` | Disassemble a function (capstone) and resolve `__objc_selrefs` references |
| `resolve_selref.py` | Decode chained-fixup selector slots into selector strings |

## Typical debugging flow

1. Crash happens → pull the `.ips` from the device
   (Settings → Privacy & Security → Analytics → Analytics Data)
2. `python Scripts/parse_ips.py YouTube-<date>.ips`
   → shows the true backtrace; note any frame inside `uYouEnhanced.dylib`
3. Download that build's IPA, extract the named `.dylib` into the repo root
4. `python Scripts/disasm_find_sel.py uYouEnhanced.dylib 0x<start> 0x<end>`
   around the crashing offset, then
   `python Scripts/resolve_selref.py uYouEnhanced.dylib 0x<selref...>`
   → prints the exact missing selector
5. Guard or gate the matching hook in `Sources/`

`refdata/` is produced by the CI workflow; refresh it after each new build so
offsets stay accurate.

I apologize if this sounds complicated, I had to write scripts to get the flow going when it came to fixing the crashes with the uYouEnhanced tweak.