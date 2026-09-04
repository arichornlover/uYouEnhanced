# FFmpegKitNext Integration

The download pipeline's ffmpeg calls go through `Sources/UYTMediaKit`, which
picks the best available backend at runtime:

1. **FFmpegKitNext** (`ffmpegkit.framework` embedded in the app) — preferred
2. **MobileFFmpeg** (legacy copy inside uYou.dylib) — automatic fallback
3. **None** — callers degrade gracefully to uYou's stock behavior

No linking changes are needed; the framework is loaded with `dlopen` at runtime.

## Producing the framework

Two paths, pick one:

### Path A — automatic (recommended, zero builds)

CI does everything. The **"Fetch & Embed FFmpegKit Framework (auto)"** step
downloads the prebuilt `min` xcframework from `arthenica/ffmpeg-kit` v6.0
(FFmpeg core only — exactly what remux + AAC conversion needs), extracts just
the `ios-arm64` device slice, thins it to arm64, and embeds it into the IPA.
Simulator/x86_64/catalyst slices and every other variant are excluded.

No manual action required; if the download ever fails, the build continues
with MobileFFmpeg.

### Path B — FFmpegKitNext v9.0.0 from source

v9.0.0 is source-only (no prebuilt binaries). Build it once on a macOS
machine using the workflow in `aricloverEXTRA/ffmpeg-kit-next`
(`.github/workflows/build-ios.yml`), or locally:

```bash
git clone https://github.com/arichornloverEXTRA/ffmpeg-kit-next.git
cd ffmpeg-kit-next
./nix-ios.sh            # or the non-Nix ios.sh flow, see their wiki
```

Then drop the resulting arm64 `ffmpegkit.framework` into `Vendor/` — the CI
step prefers a manually provided framework over the auto-download.

## Wrapper sources (reference-only)

`Scripts/ffmpegkit/fetch_ffmpegkit_wrapper.sh` cherry-picks the command-execution core
(`FFmpegKit`, `FFmpegSession`, `ReturnCode`, `FFmpegKitConfig`, session/log
classes) into `Sources/MediaKit/FFmpegKitWrapper/` so the API lives next to
our pipeline code. These are reference copies: they are NOT compiled (the
Makefile wildcard ignores that subfolder) because the wrapper needs FFmpeg's
C libraries to link — the embedded framework binary already contains them.

## Verifying which backend ran

Console logs filtered by `[uYouPatches]` show the backend id on every
conversion/remux failure, and `UYTFFActiveBackend()` values are:
0 = none, 1 = FFmpegKitNext, 2 = MobileFFmpeg.
