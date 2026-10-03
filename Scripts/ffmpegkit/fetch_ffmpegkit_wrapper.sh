#!/usr/bin/env bash
# Fetch the FFmpegKitNext wrapper sources needed to understand/extend the
# uYou download pipeline, into Sources/MediaKit/FFmpegKitWrapper/.
#
# These are REFERENCE copies — they are NOT compiled into the tweak (the
# Makefile wildcard only picks Sources/MediaKit/*.m at the top level).
# Compiling them standalone requires FFmpeg's C libraries; use the embedded
# ffmpegkit.framework binary instead.
#
# Usage: bash Scripts/fetch_ffmpegkit_wrapper.sh [ref]

set -euo pipefail

REF="${1:-main}"
REPO="aricloverEXTRA/ffmpeg-kit-next"
BASE="https://raw.githubusercontent.com/${REPO}/${REF}/apple/src"
DEST="$(dirname "$0")/../../Sources/MediaKit/FFmpegKitWrapper"

mkdir -p "$DEST"

FILES=(
  FFmpegKit.h
  FFmpegKit.m
  FFmpegSession.h
  FFmpegSession.m
  FFprobeKit.h
  FFprobeKit.m
  FFmpegKitConfig.h
  FFmpegKitConfig.m
  ReturnCode.h
  ReturnCode.m
  AbstractSession.h
  AbstractSession.m
  Session.h
  SessionState.h
  Log.h
  Log.m
  Level.h
  Statistics.h
  Statistics.m
)

echo "Fetching ${#FILES[@]} wrapper files (${REF}) into Sources/MediaKit/FFmpegKitWrapper/"
for f in "${FILES[@]}"; do
  curl -sfL "${BASE}/${f}" -o "${DEST}/${f}" || echo "  !! skipped ${f} (not found)"
done

echo "Done. Reference-only: these files are excluded from compilation."
