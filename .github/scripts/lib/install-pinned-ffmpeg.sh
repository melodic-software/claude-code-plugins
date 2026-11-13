#!/usr/bin/env bash
# Installs ffmpeg and ffprobe from BtbN's static GPL build (the Linux static
# build ffmpeg.org links; GPL for libx264), a month-end tag BtbN keeps, checked
# against its SHA-256, into <bin-dir> and onto PATH.
# Usage: install-pinned-ffmpeg.sh <bin-dir> [cache-dir]
# With a cache dir the archive is kept there and downloaded only when missing;
# without one it goes to RUNNER_TEMP and is removed after extracting.
# shellcheck disable=SC2154 # the runner sets RUNNER_TEMP and GITHUB_PATH
set -e
FFMPEG_RELEASE=autobuild-2026-09-30-13-08
FFMPEG_BUILD=n8.1.3-9-g29e619e767
FFMPEG_SHA256=97ce978979194b5cf7e06a5e68020dbdaa7a4f3294c5452b6a1bc347100dbb79
bin=${1:?usage: install-pinned-ffmpeg.sh <bin-dir> [cache-dir]}
cache=$2
asset="ffmpeg-$FFMPEG_BUILD-linux64-gpl-8.1.tar.xz"
url="https://github.com/BtbN/FFmpeg-Builds/releases/download/$FFMPEG_RELEASE/$asset"
mkdir -p "$bin"
if [[ -n "$cache" ]]; then
  mkdir -p "$cache"
  archive="$cache/$asset"
  [[ -f "$archive" ]] || curl -fSL --no-progress-meter --retry 7 --retry-all-errors -o "$archive" "$url"
else
  archive="$RUNNER_TEMP/$asset"
  curl -fSL --no-progress-meter --retry 7 --retry-all-errors -o "$archive" "$url"
fi
echo "$FFMPEG_SHA256  $archive" | sha256sum -c - ||
  {
    echo "::error::$asset does not match FFMPEG_SHA256"
    exit 1
  }
tar -xJf "$archive" -C "$bin" --strip-components=2 --wildcards '*/bin/ffmpeg' '*/bin/ffprobe'
[[ -n "$cache" ]] || rm -f "$archive"
echo "$bin" >>"$GITHUB_PATH"
for tool in ffmpeg ffprobe; do
  [[ -x "$bin/$tool" ]] || {
    echo "::error::$asset holds no bin/$tool"
    exit 1
  }
  line=$("$bin/$tool" -version | sed -n 1p)
  echo "$line"
  [[ "$line" == *"$FFMPEG_BUILD"* ]] || {
    echo "::error::$tool reports '$line', not $FFMPEG_BUILD"
    exit 1
  }
done
