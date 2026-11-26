#!/usr/bin/env bash
set -euo pipefail

LEFTHOOK_VERSION=2.2.2
LEFTHOOK_SHA256=4fbf89eb7748c6aed84d833ee1a29edac48fae614468ca9a82896ec32f2800b6

asset="lefthook_${LEFTHOOK_VERSION}_Linux_x86_64"
bin="$HOME/.local/bin"
mkdir -p "$bin" "$HOME/.cache/ci-tools"
cached="$HOME/.cache/ci-tools/$asset"
[[ -f "$cached" ]] || curl -fSL --no-progress-meter --retry 7 --retry-all-errors -o "$cached" \
  "https://github.com/evilmartians/lefthook/releases/download/v$LEFTHOOK_VERSION/$asset"
cp "$cached" "$bin/lefthook"
echo "$LEFTHOOK_SHA256  $bin/lefthook" | sha256sum -c -
chmod +x "$bin/lefthook"
[[ -z "${GITHUB_PATH:-}" ]] || echo "$bin" >>"$GITHUB_PATH"
test "$("$bin/lefthook" version)" = "$LEFTHOOK_VERSION"
