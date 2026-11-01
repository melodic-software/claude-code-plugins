#!/usr/bin/env bash
# Copy the legacy JSON tracker binding (.work-item-tracker.json) and its personal
# overlay (.work-item-tracker.local.json) into the `tracker` mapping of
# <home>/work-items.yaml and <home>/work-items.local.yaml, for /work-items:setup
# apply (SKILL.md "Provider binding"). The JSON files are left in place: readers
# outside the seam still read only them.
#
# Each layer is copied only when its YAML file has no `tracker` key. Both layers are
# checked before either is written: once the YAML binding exists the seam reads only
# the YAML overlay, so a binding copied without its overlay would drop the overlay
# silently. The YAML text is appended to the file (created when absent), parsed back
# with the seam's own reader and compared with the JSON before it is written, so a
# copy that would read differently is never written. The overlay is copied only to
# a path a repository .gitignore rule covers and the index does not hold.
#
# Usage: migrate-binding.sh [--root <repo-root>]
#
# Stdout, one line per layer: `binding: <outcome> <detail>` then
# `overlay: <outcome> <detail>`. Outcomes: copied, already-yaml, no-json, empty
# (the JSON file is `{}`), not-ignored and tracked (overlay only, nothing written).
#
# Exit: 0 done; 1 a file does not parse, holds a value the YAML subset cannot carry
#       or the seam reads differently, or the copy did not read back the same;
#       2 usage; 3 the overlay's YAML path is not gitignored or is tracked;
#       4 no convention home applies (declined, $HOME, not a git work tree, or a
#       broken pointer, which the resolver names on stderr). Exits 1, 3 and 4 write
#       nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../tools/work-item-tracker/lib/binding.sh
source "$SCRIPT_DIR/../../../tools/work-item-tracker/lib/binding.sh"

LEGACY_OVERLAY=".work-item-tracker.local.json"

ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -ge 2 ]] || { echo "migrate-binding: --root needs a path" >&2; exit 2; }
    ROOT="$2"
    shift 2
    ;;
  *)
    echo "migrate-binding: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done
if [[ -z "$ROOT" ]]; then
  ROOT="$(wit_project_root)" || { echo "migrate-binding: not in a git repository; pass --root" >&2; exit 2; }
fi
[[ -d "$ROOT" ]] || { echo "migrate-binding: --root is not a directory: $ROOT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "migrate-binding: jq is required" >&2; exit 1; }

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT

# What the seam reads back from the YAML: every scalar as a string.
readonly NORMALIZE='(.. | select(type == "number" or type == "boolean")) |= tostring'

# The YAML lines for a JSON object, under `tracker:`. Strings are double-quoted
# with the subset's escapes; numbers and booleans are written bare.
# shellcheck disable=SC2016 # a jq program: its $ind is jq's, not the shell's
readonly EMIT='
  def str: "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\t"; "\\t")) + "\"";
  def scalar: if type == "string" then str else tostring end;
  def key: if test("^[A-Za-z0-9_-]+$") then . else str end;
  def lines($ind):
    to_entries[] | (.key | key) as $k | .value as $v
    | if ($v | type) == "object" then ($ind + $k + ":"), ($v | lines($ind + "  "))
      elif ($v | type) == "array" then
        if ($v | length) == 0 then $ind + $k + ": []"
        else ($ind + $k + ":"), ($v[] | $ind + "  - " + scalar) end
      else $ind + $k + ": " + ($v | scalar) end;
  "tracker:", lines("  ")'

# unsupported <json-file>: name each value the YAML subset cannot carry, or the seam
# would read differently, if any. An empty object reads back as absent, which turns
# a present-but-empty key (a config error for some adapters) into its default.
unsupported() {
  jq -r '
    def at($p): $p | map(tostring) | join(".");
    [paths(. == null) | "null at " + at(.)]
    + [paths(. == {}) | "an empty object at " + at(.)]
    + [paths(type == "array") as $p | getpath($p) | select(any(.[]; type == "object" or type == "array"))
       | "a list of lists or mappings at " + at($p)]
    + [paths(type == "string") as $p | getpath($p) | select(explode | any(. < 32 and . != 9))
       | "a control character at " + at($p)]
    + [paths | select(.[-1] | type == "string" and (. == "" or test("[.\t]") or test("^[0-9]+$")))
       | "a key that is empty, all digits, or holds . or a tab at " + at(.)]
    | .[]' "$1"
}

# STATE and DETAIL: what plan found for a layer.
STATE=""
DETAIL=""

# plan <label> <json> <yaml>: decide one layer without writing. STATE is no-json,
# already-yaml, empty or copy; for copy, DETAIL is the checked temp file holding the
# new YAML. Fails, naming the problem, when the layer cannot be copied.
plan() {
  local json="$2" yaml="$3" expected actual bad tmp="$WORK/$1.yaml"
  STATE=""
  DETAIL="$json"
  if [[ ! -f "$json" ]]; then
    STATE="no-json"
    return 0
  fi
  if ! jq -e 'type == "object"' "$json" >/dev/null 2>&1; then
    echo "migrate-binding: $json does not parse as a JSON object" >&2
    return 1
  fi
  if [[ -f "$yaml" ]]; then
    wit_yaml_records "$yaml" >/dev/null || return 1
    if wit_yaml_has_binding "$yaml"; then
      STATE="already-yaml"
      DETAIL="$yaml"
      return 0
    fi
  fi
  bad="$(unsupported "$json")" || return 1
  if [[ -n "$bad" ]]; then
    printf 'migrate-binding: %s holds %s; the YAML binding cannot carry it, so fix it in the JSON file first\n' \
      "$json" "${bad//$'\n'/, }" >&2
    return 1
  fi
  if [[ "$(jq -c . "$json")" == "{}" ]]; then
    STATE="empty"
    return 0
  fi
  expected="$(jq -c "$NORMALIZE" "$json")" || return 1
  : >"$tmp" || return 1
  DETAIL="$tmp"
  if [[ -s "$yaml" ]]; then
    cat "$yaml" >"$tmp"
    [[ -z "$(tail -c 1 "$yaml")" ]] || printf '\n' >>"$tmp"
  fi
  jq -r "$EMIT" "$json" >>"$tmp" || return 1
  actual="$(wit_yaml_binding_json "$tmp")" || return 1
  if [[ "$(jq -n --argjson a "$expected" --argjson b "$actual" '$a == $b')" != "true" ]]; then
    printf 'migrate-binding: the YAML copy of %s reads back as %s, not %s; nothing written\n' \
      "$json" "$actual" "$expected" >&2
    return 1
  fi
  STATE="copy"
}

# write <label> <state> <detail> <json> <yaml>: carry out what plan decided.
write() {
  local label="$1" state="$2" detail="$3" json="$4" yaml="$5"
  if [[ "$state" != "copy" ]]; then
    printf '%s: %s %s\n' "$label" "$state" "$detail"
    return 0
  fi
  mkdir -p "$(dirname "$yaml")" || return 1
  # cat, not mv: an existing file keeps its mode, a new one takes the umask.
  cat "$detail" >"$yaml" || return 1
  printf '%s: copied %s -> %s\n' "$label" "$json" "$yaml"
}

# gitignored <path>: a repository .gitignore rule ignores the path, as
# reference/overlay-ignore-probes.md decides it (info/exclude and core.excludesFile
# protect no teammate). git prints a repository .gitignore source relative to the
# work tree and an excludes file as an absolute path, so a global excludes file
# named ~/.gitignore is refused before the .gitignore name test.
gitignored() {
  local match
  git -C "$ROOT" check-ignore --no-index -q -- "$1" || return 1
  match="$(git -C "$ROOT" check-ignore --no-index -v -- "$1")"
  case "${match%%:*}" in
  /*) return 1 ;;
  .gitignore | */.gitignore) return 0 ;;
  *) return 1 ;;
  esac
}

if ! HOME_DIR="$(wit_convention_home "$ROOT")"; then
  echo "migrate-binding: no convention home applies under $ROOT; $WIT_LEGACY_BINDING stays the binding" >&2
  exit 4
fi
JSON="$ROOT/$WIT_LEGACY_BINDING"
YAML="$ROOT/$HOME_DIR/work-items.yaml"
OVERLAY_JSON="$ROOT/$LEGACY_OVERLAY"
OVERLAY_REL="$HOME_DIR/work-items.local.yaml"
OVERLAY_YAML="$ROOT/$OVERLAY_REL"

plan binding "$JSON" "$YAML" || exit 1
BINDING_STATE="$STATE"
BINDING_DETAIL="$DETAIL"
plan overlay "$OVERLAY_JSON" "$OVERLAY_YAML" || exit 1
OVERLAY_STATE="$STATE"
OVERLAY_DETAIL="$DETAIL"

if [[ "$OVERLAY_STATE" == "copy" ]]; then
  if ! gitignored "$OVERLAY_REL"; then
    printf 'overlay: not-ignored %s\n' "$OVERLAY_REL"
    echo "migrate-binding: add a .gitignore rule for $OVERLAY_REL, then run again" >&2
    exit 3
  fi
  if [[ -n "$(git -C "$ROOT" ls-files -- "$OVERLAY_REL")" ]]; then
    printf 'overlay: tracked %s\n' "$OVERLAY_REL"
    echo "migrate-binding: $OVERLAY_REL is in the index; untrack it (git rm --cached), then run again" >&2
    exit 3
  fi
fi

write binding "$BINDING_STATE" "$BINDING_DETAIL" "$JSON" "$YAML" || exit 1
write overlay "$OVERLAY_STATE" "$OVERLAY_DETAIL" "$OVERLAY_JSON" "$OVERLAY_YAML" || exit 1
