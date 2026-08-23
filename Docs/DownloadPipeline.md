# Download Pipeline Rewrite — Design (21.14.4+, iOS 16–26)

## Why uYou 3.0.4 downloads fail on modern YouTube

uYou 3.0.4 extracts stream URLs from YouTube's player internals as they existed
in the 19.x era. On 21.x the player response shape/stream gating changed, so
`getLinksLocallyPlayerItem:...` never yields usable URLs → the item is created
with nil metadata → UI shows `(null) | 0%` and "Downloading..." forever.
(Our old background-session swap made it worse; that's been removed.)

## Architecture

New standalone pipeline (`Sources/DownloadPipeline.xm`) — no dependency on
uYou's broken extraction:

1. **Innertube fetch**: POST `https://www.youtube.com/youtubei/v1/player`
   with an **iOS client context** (`clientName: IOS`, real clientVersion,
   `deviceModel`, etc.). The iOS client historically returns direct,
   non-ciphered URLs in `streamingData`.
2. **Parse**: `streamingData.formats` (muxed mp4) + `adaptiveFormats`
   (separate video/audio). Rank by bitrate/itag; keep `url` when present;
   handle `signatureCipher` fallback only if needed.
3. **Deliver**: hand chosen URLs + metadata (title, author, duration, filesize)
   to the consumer:
   - Phase 1: our own downloader (NSURLSession downloadTask, progress via
     NSNotification `uYouDownloadProgressChanged`) writing into uYou's
     existing storage layout so files appear in uYou's library UI.
   - Phase 2 (optional): feed URLs back into uYou's merge/metadata path
     (`mergeAudioWithMP4VideoForDownloadItem:`, `addMetadataToAudioForDownloadItem:`
     — both already hardened in uYouPatches.xm).
4. **Compatibility**: iOS 16+ APIs only (NSURLSession, NSJSONSerialization);
   no private framework use; all callbacks on main queue for UI.

## Status / TODO

- [x] Design (this file)
- [ ] `Sources/DownloadPipeline.xm`: innertube fetch + format selection
- [ ] Wire into download button flow (replace/bypass `getLinksLocallyPlayerItem`)
- [ ] Progress notifications wired to uYou's DownloadingCell UI
- [ ] Audio-only downloads (reuse existing webm→m4a converter)
- [ ] Test matrix: YT 21.14.4 / iOS 16, 18, 26 · video+audio · audio-only · Shorts

## Notes

- uYou storage root: `Documents/uYouDownloads/` (see NSFileManager fallback
  hooks in uYouPatches.xm).
- Never swap AFHTTPSessionManager's session (see uYouPatches.xm warning).
- Reference implementations: YouMod's download feature (daisuke1227),
  yt-dlp's iOS-client innertube requests.
