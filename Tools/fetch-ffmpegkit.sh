#!/usr/bin/env bash
# FFmpegKitNext iOS frameworks builder for uYouEnhanced.
#
# Optional: the repo already ships prebuilt frameworks in Vendor/, and
# tools/stage-ffmpeg.sh will use those as-is. Run this only if you want to
# rebuild ffmpeg from source (takes 30-90 minutes on an Apple silicon Mac).
#
# Ported from YouMod's tools/fetch-ffmpegkit.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MODULES_DIR="$ROOT/modules/ffmpeg"
CACHE_DIR="$ROOT/.cache/ffmpegkit"
SRC_DIR="$CACHE_DIR/ffmpeg-kit-next"
MARKER="$MODULES_DIR/.uYouEnhanced-source-build"

REPO_URL="https://github.com/arthenica/ffmpeg-kit-next.git"
REPO_TAG="${UYOU_FFMPEG_TAG:-v9.0.0}"

HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$PATH"

FRAMEWORKS=(ffmpegkit libavcodec libavdevice libavfilter libavformat libavutil libswresample libswscale)

BUILD_ARGS=(
  --arch=arm64
  --xcframework
  --target=14.0
  --enable-lib-ios-zlib
  --enable-lib-ios-libiconv
)

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

resolve_gnu_sed() {
  [[ -n "${SED:-}" ]] && return 0
  local candidate
  for candidate in gsed "$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin/sed"; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" --version 2>/dev/null | grep -q 'GNU sed'; then
      export SED="$(command -v "$candidate")"
      return 0
    fi
  done
  die "GNU sed not found - install it with: brew install gnu-sed"
}

have_complete_install() {
  local current
  [[ -f "$MARKER" ]] || return 1
  for f in "${FRAMEWORKS[@]}"; do
    [[ -f "$MODULES_DIR/$f.framework/$f" ]] || return 1
  done
  current="$(sed -n 's/^build_args=//p' "$MARKER" 2>/dev/null || true)"
  [[ "$current" == "${BUILD_ARGS[*]}" ]] || return 1
  [[ "$(sed -n 's/^tag=//p' "$MARKER" 2>/dev/null || true)" == "$REPO_TAG" ]] || return 1
}

fetch_source() {
  if [[ -d "$SRC_DIR/.git" ]]; then
    info "source already at $SRC_DIR"
    return
  fi
  mkdir -p "$CACHE_DIR"
  info "cloning ffmpeg-kit-next $REPO_TAG"
  git clone --quiet --depth=1 --branch "$REPO_TAG" "$REPO_URL" "$SRC_DIR"
}

xcframework_dir() {
  find "$SRC_DIR/prebuilt" -maxdepth 1 -type d -name 'bundle-apple-xcframework-ios*' 2>/dev/null | sort | head -n 1
}

install_frameworks() {
  local out
  out="$(xcframework_dir)"
  [[ -n "$out" && -d "$out" ]] || die "build produced no xcframeworks under $SRC_DIR/prebuilt (see $SRC_DIR/build.log)"

  mkdir -p "$MODULES_DIR"
  rm -rf "$MODULES_DIR"/*.framework

  local xcfw name slice
  for xcfw in "$out"/*.xcframework; do
    [[ -d "$xcfw" ]] || continue
    name="$(basename "$xcfw" .xcframework)"
    slice="$(find "$xcfw" -maxdepth 1 -type d \( -name 'ios-arm64' -o -name 'ios-arm64_*' \) | sort | head -n 1)"
    [[ -n "$slice" && -d "$slice/$name.framework" ]] || die "no ios-arm64 slice for $name"
    cp -R "$slice/$name.framework" "$MODULES_DIR/"
  done

  for f in "${FRAMEWORKS[@]}"; do
    local bin="$MODULES_DIR/$f.framework/$f"
    [[ -f "$bin" ]] || continue
    install_name_tool -add_rpath "@loader_path/.." "$bin" 2>/dev/null || true
  done

  cat > "$MARKER" <<EOF
tag=$REPO_TAG
build_args=${BUILD_ARGS[*]}
built=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

force=0
case "${1:-}" in
  --force) force=1 ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  "") ;;
  *) die "unknown option: $1" ;;
esac

if [[ $force -eq 0 ]] && have_complete_install; then
  info "FFmpegKit frameworks already built - pass --force to rebuild."
  exit 0
fi

command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"
resolve_gnu_sed
info "using GNU sed at $SED"

fetch_source

if [[ $force -eq 1 ]]; then
  info "forcing a clean rebuild"
  rm -rf "$SRC_DIR/prebuilt"
fi

if [[ -z "$(xcframework_dir)" ]]; then
  info "building FFmpeg for ios-arm64 - this takes 30-90 minutes"
  ( cd "$SRC_DIR" && ./ios.sh "${BUILD_ARGS[@]}" ) || { tail -n 80 "$SRC_DIR/build.log" >&2; die "ios.sh failed"; }
fi

install_frameworks
info "installed into $MODULES_DIR:"
du -sh "$MODULES_DIR"/*.framework 2>/dev/null | sed 's/^/    /'
