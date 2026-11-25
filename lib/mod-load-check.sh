# shellcheck shell=bash

mod_load_check() {
  local root="$1" session="$2" floor version failed=0
  shift 2
  if [[ $# -gt 0 ]]; then
    echo "check-mod-load: takes no arguments" >&2
    exit 2
  fi
  _mod_load_row() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    [[ "$2" == FAIL ]] && failed=1
  }
  floor="$(sed -n '/"id": "claude"/,/"min"/s/.*"min": *"\([0-9.]*\)".*/\1/p' "$root/prerequisites.json")"
  version="$(claude --version 2>/dev/null)"
  version="${version%% *}"
  if [[ -z "$floor" ]]; then
    _mod_load_row mods-floor FAIL "prerequisites.json declares no mods floor on its claude entry"
  elif [[ -z "$version" ]]; then
    _mod_load_row mods-floor FAIL "claude did not report a version, so the mods floor $floor could not be checked"
  elif awk -v v="$version" -v f="$floor" 'BEGIN {
    nv = split(v, a, "."); nf = split(f, b, ".")
    for (i = 1; i <= (nv > nf ? nv : nf); i++) {
      if (a[i] + 0 != b[i] + 0) exit (a[i] + 0 < b[i] + 0)
    }
  }'; then
    _mod_load_row mods-floor PASS "claude $version meets the mods floor $floor"
  else
    _mod_load_row mods-floor FAIL "mods off: claude $version is older than the mods floor $floor, unsupported"
  fi
  _mod_load_row session INFO "$session"
  exit "$failed"
}
