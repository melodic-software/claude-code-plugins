#!/usr/bin/env bash
# SessionStart, cloud sessions only (CLAUDE_CODE_REMOTE=true): install the pinned
# shfmt the guards read every Bash command through (hook-utils.sh,
# hook::bash_parse_segments) into ~/.local/bin when no shfmt resolves, so a fresh
# cloud VM does not refuse every Bash call. The reader looks in ~/.local/bin when
# PATH lacks shfmt. A local machine is never touched.
#
# Never blocks the session: every path exits 0. When the install fails it writes
# the reason to ~/.local/state/claude-guardrails/shfmt-install-failed, and the
# reader's refusal message quotes it (hook::_bps_install_note); a later success
# removes it.
#
# The pin and hash match .claude/cloud-bootstrap.sh and the CI workflows in this
# repository (cloud-shfmt.test.sh checks they agree). v3.14.1 publishes no
# checksums file; the hash is sha256sum of the linux_amd64 asset.
set -uo pipefail

# A local session has nothing to install, so the hook leaves before any library
# loads. Sourced (cloud-shfmt.test.sh calls the installer directly), it goes on.
[[ "${BASH_SOURCE[0]}" != "$0" || "${CLAUDE_CODE_REMOTE:-}" == true ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: an install step never blocks a session, so any abort
# is reported and the session goes on (open); 0 is the only chosen status.
guard::abort_boundary cloud-shfmt SessionStart open 0
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

CLOUD_SHFMT_PIN="v3.14.1"
CLOUD_SHFMT_SHA="76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf"
CLOUD_SHFMT_URL="https://github.com/mvdan/sh/releases/download/${CLOUD_SHFMT_PIN}/shfmt_${CLOUD_SHFMT_PIN}_linux_amd64"
CLOUD_SHFMT_NOTE="$HOME/.local/state/claude-guardrails/shfmt-install-failed"

# cloud_shfmt::install <url> <sha256> <dest>: download, check, install. Prints
# the reason and returns 1 on any failure; <dest> is written only after the
# hash matches.
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
