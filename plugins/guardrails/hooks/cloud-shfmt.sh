#!/usr/bin/env bash
set -uo pipefail

[[ "${BASH_SOURCE[0]}" != "$0" || "${CLAUDE_CODE_REMOTE:-}" == true ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary cloud-shfmt SessionStart open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

CLOUD_SHFMT_PIN="v3.14.1"
CLOUD_SHFMT_SHA="76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf"
CLOUD_SHFMT_URL="https://github.com/mvdan/sh/releases/download/${CLOUD_SHFMT_PIN}/shfmt_${CLOUD_SHFMT_PIN}_linux_amd64"
CLOUD_SHFMT_NOTE="$HOME/.local/state/claude-guardrails/shfmt-install-failed"

cloud_shfmt::install() {
  local url=$1 sha=$2 dest=$3 tmp rc got
  tmp=$(mktemp) || {
    echo "mktemp failed"
    return 1
  }
  curl -fsSL --max-time 60 -o "$tmp" "$url" 2>/dev/null
  rc=$?
  if ((rc != 0)); then
    rm -f "$tmp"
    echo "download failed: curl exit $rc ($url)"
    return 1
  fi
  got=$(sha256sum "$tmp" 2>/dev/null) || got=""
  got=${got%% *}
  if [[ "$got" != "$sha" ]]; then
    rm -f "$tmp"
    echo "checksum mismatch for $url (got ${got:-none}), not installed"
    return 1
  fi
  mkdir -p "${dest%/*}" && install -m 0755 "$tmp" "$dest"
  rc=$?
  rm -f "$tmp"
  ((rc == 0)) || {
    echo "could not write $dest"
    return 1
  }
}

cloud_shfmt::main() {
  [[ "${CLAUDE_CODE_REMOTE:-}" == true ]] || return 0
  if command -v shfmt >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/shfmt" ]]; then
    rm -f "$CLOUD_SHFMT_NOTE"
    return 0
  fi
  local why platform
  platform="$(uname -s 2>/dev/null)-$(uname -m 2>/dev/null)"
  if [[ "$platform" != Linux-x86_64 ]]; then
    why="no pinned shfmt build for $platform"
  elif why=$(cloud_shfmt::install "$CLOUD_SHFMT_URL" "$CLOUD_SHFMT_SHA" "$HOME/.local/bin/shfmt"); then
    rm -f "$CLOUD_SHFMT_NOTE"
    return 0
  fi
  mkdir -p "${CLOUD_SHFMT_NOTE%/*}" && printf '%s\n' "$why" >"$CLOUD_SHFMT_NOTE"
  echo "guardrails: shfmt install failed ($why); Bash calls will be refused until shfmt is on PATH" >&2
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cloud_shfmt::main
  exit 0
fi
