#!/usr/bin/env bash
# Stages FFmpegKitNext frameworks into uYouMedia.bundle after Theos staging.
#
# Run automatically by the Makefile's after-stage:: hook. Frameworks are taken
# from modules/ffmpeg (built by tools/fetch-ffmpegkit.sh) when present, otherwise
# from the prebuilt Vendor/ directory that ships with the repo.
#
# Ported from YouMod's tools/stage-ffmpeg.sh.
set -euo pipefail

STAGING="${1:?usage: stage-ffmpeg.sh <THEOS_STAGING_DIR>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

BUNDLE_NAME="uYouMedia.bundle"
FRAMEWORKS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Pick a source directory that actually holds the frameworks.
resolve_modules() {
  local candidate
  for candidate in "$ROOT/modules/ffmpeg" "$ROOT/Vendor"; do
    [ -d "$candidate" ] || continue
    for f in "${FRAMEWORKS[@]}"; do
      [ -f "$candidate/$f.framework/$f" ] || continue 2
    done
    printf '%s' "$candidate"
    return 0
  done
  return 1
}

MODULES="$(resolve_modules || true)"

if [ -z "$MODULES" ]; then
  # Nothing to stage. The runtime loader falls back to YouTube's own vendored
  # frameworks, so this is a degraded build and not a hard failure - the tweak
  # still compiles and installs, it just cannot transcode on its own.
  warn "no FFmpegKit frameworks in $ROOT/modules/ffmpeg or $ROOT/Vendor - skipping ffmpeg staging"
  warn "the tweak will fall back to YouTube's vendored ffmpeg at runtime"
  exit 0
fi

BUNDLE="$(find "$STAGING" -type d -name "$BUNDLE_NAME" -print -quit 2>/dev/null || true)"

if [ -z "$BUNDLE" ]; then
  # Usually Bundles/uYouMedia.bundle is embedded by the tweak's install rule
  # before after-stage runs. If it is not there yet, create it where an embedded
  # bundle would land so the runtime resolver still finds it.
  for candidate in "$STAGING/var/jb/Library/Frameworks" "$STAGING/Library/Frameworks"; do
    if mkdir -p "$candidate/$BUNDLE_NAME" 2>/dev/null; then
      BUNDLE="$candidate/$BUNDLE_NAME"
      warn "$BUNDLE_NAME was not staged yet - created $candidate/$BUNDLE_NAME"
      break
    fi
  done
fi

[ -n "$BUNDLE" ] || die "could not locate or create $BUNDLE_NAME under $STAGING"

info "staging FFmpegKit into ${BUNDLE#"$STAGING"} (from ${MODULES#"$ROOT/"})"
for framework in "$MODULES"/*.framework; do
  [ -d "$framework" ] || continue
  name="$(basename "$framework")"
  rm -rf "${BUNDLE:?}/$name"
  cp -R "$framework" "$BUNDLE/$name"
  binary="$BUNDLE/$name/$name"
  if [ -f "$binary" ] && command -v ldid >/dev/null 2>&1; then
    ldid -S "$binary" 2>/dev/null || true
  fi
done

staged="$(find "$BUNDLE" -maxdepth 1 -type d -name '*.framework' | wc -l | tr -d ' ')"
info "staged $staged frameworks ($(du -sh "$MODULES" 2>/dev/null | cut -f1))"

missing=()
for f in "${FRAMEWORKS[@]}"; do
  [ -f "$BUNDLE/$f.framework/$f" ] || missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
  die "incomplete ffmpeg stage, missing: ${missing[*]}"
fi
