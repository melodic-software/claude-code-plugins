#!/usr/bin/env bash
# SessionStart probe for the binaries this plugin's prerequisites.json declares.
# Every name, local_bin, check, and install string comes from that manifest.
# Reports a missing binary once per session; never installs.
set -uo pipefail

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"
MANIFEST="$ROOT/prerequisites.json"
[[ -f "$MANIFEST" ]] || exit 0

field() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\""
  [[ "$2" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}

have() {
  command -v "$1" >/dev/null 2>&1 && return 0
  [[ -n "$2" ]] || return 1
  local dir="$PWD" i
  for ((i = 0; i < 8; i++)); do
    [[ -x "$dir/$2" ]] && return 0
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

plugin="$(field name "$(cat "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)")"
plugin="${plugin:-${ROOT##*/}}"
tools="$(tr -d '\r\n' <"$MANIFEST")"
tools="${tools#*\"tools\"}"

INPUT=""
loaded=0
while [[ "$tools" == *"{"* ]]; do
  tools="${tools#*\{}"
  entry="${tools%%\}*}"
  tools="${tools#*\}}"
  name="$(field name "$entry")"
  [[ -n "$name" ]] || continue
  local_bin="$(field local_bin "$entry")"
  have "$name" "$local_bin" && continue
  if [[ "$loaded" -eq 0 ]]; then
    # shellcheck source=hook-utils.sh
    source "$SCRIPT_DIR/hook-utils.sh"
    INPUT="$(cat || true)"
    loaded=1
  fi
  where="on PATH"
  [[ -n "$local_bin" ]] && where="on PATH or as $local_bin"
  if hook::notice_once "$plugin-$name" "$INPUT" prerequisite; then
    msg="$plugin: $name was not found $where. Hooks that need it will skip until it is installed. Run $(field check "$entry"). It does not install. Install: $(field install "$entry")"
    notice="${notice:+$notice$'\n'}$msg"
  fi
done
[[ -n "${notice:-}" ]] && hook::emit_skip_notice SessionStart "$notice"
exit 0
