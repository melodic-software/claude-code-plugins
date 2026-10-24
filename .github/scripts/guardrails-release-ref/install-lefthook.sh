#!/usr/bin/env bash
# Install the pinned lefthook on a Linux x86_64 runner, checksum-verified, into ~/.local/bin and
# onto $GITHUB_PATH: the lefthook the guardrails remote's end-to-end test
# (plugins/guardrails/git-hooks/lefthook-remote.test.sh) runs, in pr-require-checks.yml's
# test-bash lane and in release-move-guardrails-ref.yml before it moves guardrails-release.
# The version is the one the fleet runs; the hash is the release's published SHA-256 for
# lefthook_<version>_Linux_x86_64. A cached download under ~/.cache/ci-tools is reused and
# checked the same way.
set -euo pipefail

LEFTHOOK_VERSION=2.2.2
LEFTHOOK_SHA256=4fbf89eb7748c6aed84d833ee1a29edac48fae614468ca9a82896ec32f2800b6

asset="lefthook_${LEFTHOOK_VERSION}_Linux_x86_64"
mkdir -p "$HOME/.local/bin" "$HOME/.cache/ci-tools"
cached="$HOME/.cache/ci-tools/$asset"
[[ -f "$cached" ]] || curl -fSL --no-progress-meter --retry 3 --retry-all-errors -o "$cached" \
  "https://github.com/evilmartians/lefthook/releases/download/v$LEFTHOOK_VERSION/$asset"
cp "$cached" "$HOME/.local/bin/lefthook"
echo "$LEFTHOOK_SHA256  $HOME/.local/bin/lefthook" | sha256sum -c -
chmod +x "$HOME/.local/bin/lefthook"
[[ -z "${GITHUB_PATH:-}" ]] || echo "$HOME/.local/bin" >>"$GITHUB_PATH"
test "$("$HOME/.local/bin/lefthook" version)" = "$LEFTHOOK_VERSION"
