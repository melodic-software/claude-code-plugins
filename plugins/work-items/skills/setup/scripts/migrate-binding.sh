#!/usr/bin/env bash
# Move a legacy tracker binding into the convention home (ADR 0075 fix 11): the
# root .work-item-tracker.json becomes the `tracker` mapping of
# <home>/work-items.yaml, and the root .work-item-tracker.local.json becomes the
# `tracker` mapping of <home>/work-items.local.yaml. Each JSON file is removed only
# after its YAML copy reads back as the same binding.
#
# Usage: migrate-binding.sh [--root <repo-root>]
#   --root defaults to the seam's own anchor: CLAUDE_PROJECT_DIR, else the git
#   toplevel.
#
# Stdout, one line per action:
#   none                     no legacy file to migrate
#   migrated <json> <yaml>   the file's keys now sit under tracker: in <yaml>
#   removed <json>           the legacy file is gone (commit the deletion)
#   refused: <why>           nothing was written or removed
#   kept <json>: <why>       migrated, but this JSON file could not be removed
#
# Exit: 0 migrated or nothing to do; 1 refused (a target already holds a
# tracker key or does not parse, a legacy file is not a JSON object or holds a
# shape YAML cannot carry, or a read-back differs); 2 usage; 3 no convention home
# applies (the repository declined one, the pointer region is broken, or the
# root is $HOME or outside a git work tree), so the legacy file stays the binding;
# 4 migrated but a JSON file is still there.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../tools/work-item-tracker/lib/binding.sh
source "$SCRIPT_DIR/../../../tools/work-item-tracker/lib/binding.sh"

LEGACY_OVERLAY=".work-item-tracker.local.json"

usage() {
  printf 'usage: migrate-binding.sh [--root <repo-root>]\n' >&2
  exit 2
}

ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -ge 2 && -n "$2" ]] || usage
    ROOT="$2"
    shift 2
    ;;
  *) usage ;;
  esac
done

refuse() {
  printf 'refused: %s\n' "$1"
  exit 1
}

if [[ -z "$ROOT" ]]; then
  ROOT="$(wit_project_root)" || ROOT=""
  [[ -n "$ROOT" ]] || refuse "no repository root (set --root, or run inside a git work tree)"
fi
ROOT="$(cd "$ROOT" && pwd)" || refuse "root $ROOT is not a directory"

# JSON to the YAML subset the seam reads: strings double-quoted (JSON escapes are
# the parser's own), numbers and booleans plain, an empty list as [], a list of
# scalars as a block sequence. A null or an empty mapping writes the bare key,
# which reads as absent. A list holding a list or a mapping has no binding key
# that uses it, so it fails rather than guess a layout.
# shellcheck disable=SC2016 # jq program, not shell
JQ_TO_YAML='
  def key: if test("^[A-Za-z0-9_-]+$") then . else tojson end;
  def scalar: if type == "string" then tojson else tostring end;
  def lines($i):
    to_entries | map(
      (.key | key) as $k | .value as $v
      | if ($v | type) == "object" and ($v | length) > 0 then
          ["\($i)\($k):"] + ($v | lines($i + "  "))
        elif ($v | type) == "array" and ($v | length) > 0 then
          ["\($i)\($k):"] + ($v | map(
            if type == "object" or type == "array" then error("\($k) holds a nested list or mapping")
            else "\($i)  - \(scalar)" end))
        elif ($v | type) == "array" then ["\($i)\($k): []"]
        elif $v == null or ($v | type) == "object" then ["\($i)\($k):"]
        else ["\($i)\($k): \($v | scalar)"] end)
    | add // [];
  ["tracker:"] + lines("  ") | .[]'

# What the YAML read-back must equal: every scalar as text, and no null or empty
# mapping (each reads as absent).
# shellcheck disable=SC2016 # jq program, not shell
JQ_EXPECTED='
  walk(if type == "number" or type == "boolean" then tostring
       elif type == "object" then with_entries(select(.value != null and .value != {}))
       else . end)'

TEAM_SRC="$ROOT/$WIT_LEGACY_BINDING"
OVERLAY_SRC="$ROOT/$LEGACY_OVERLAY"
if [[ ! -f "$TEAM_SRC" && ! -f "$OVERLAY_SRC" ]]; then
  printf 'none\n'
  exit 0
fi

if ! HOME_DIR="$(wit_convention_home "$ROOT")"; then
  printf 'no-home: no convention home applies to %s; %s stays the binding\n' "$ROOT" "$WIT_LEGACY_BINDING"
  exit 3
fi
TEAM_DST="$ROOT/$HOME_DIR/work-items.yaml"
OVERLAY_DST="$ROOT/$HOME_DIR/work-items.local.yaml"

# Check every pair before writing either, so a refusal leaves both untouched.
PAIRS=()
for pair in "$TEAM_SRC|$TEAM_DST" "$OVERLAY_SRC|$OVERLAY_DST"; do
  src="${pair%%|*}"
  dst="${pair#*|}"
  [[ -f "$src" ]] || continue
  jq -e 'type == "object"' "$src" >/dev/null 2>&1 || refuse "$src is not a JSON object"
  if [[ "$src" == "$TEAM_SRC" ]] && ! jq -e 'length > 0' "$src" >/dev/null; then
    refuse "$src is empty; bind with /work-items:setup apply instead"
  fi
  if [[ -f "$dst" ]] && wit_yaml_has_binding "$dst"; then
    refuse "$dst already sets tracker: or does not parse; reconcile it with $src by hand"
  fi
  jq -r "$JQ_TO_YAML" "$src" >/dev/null 2>&1 || refuse "$src holds a nested list or mapping no binding key uses"
  PAIRS+=("$pair")
done
# A YAML overlay the legacy binding never read would start applying once the
# binding moves beside it.
if [[ -f "$TEAM_SRC" && ! -f "$OVERLAY_SRC" && -f "$OVERLAY_DST" ]] && wit_yaml_has_binding "$OVERLAY_DST"; then
  refuse "$OVERLAY_DST already sets tracker: and would start applying to the moved binding; reconcile it by hand"
fi

SCRATCH="$(mktemp -d)" || refuse "cannot create a temporary directory"
trap 'rm -rf "$SCRATCH"' EXIT
NEW_HOME=""
[[ -d "$ROOT/$HOME_DIR" ]] || NEW_HOME="$ROOT/$HOME_DIR"
mkdir -p "$ROOT/$HOME_DIR" || refuse "cannot create $ROOT/$HOME_DIR"

WRITTEN=()
rollback() {
  local n=0 dst
  for dst in "${WRITTEN[@]}"; do
    if [[ -f "$SCRATCH/orig.$n" ]]; then
      cp "$SCRATCH/orig.$n" "$dst" || refuse "$1; restoring $dst from $SCRATCH/orig.$n also failed"
    else
      rm -f "$dst"
    fi
    n=$((n + 1))
  done
  [[ -n "$NEW_HOME" ]] && rmdir -p "$NEW_HOME" 2>/dev/null
  refuse "$1"
}

for pair in "${PAIRS[@]}"; do
  src="${pair%%|*}"
  dst="${pair#*|}"
  n="${#WRITTEN[@]}"
  if [[ -f "$dst" ]]; then
    cp "$dst" "$SCRATCH/orig.$n" || rollback "cannot back up $dst"
  fi
  WRITTEN+=("$dst")
  # Keep what the file already holds (other work-items settings); a final line
  # with no newline gets one before the tracker block.
  sep=""
  if [[ -s "$dst" && -n "$(tail -c 1 "$dst")" ]]; then sep=$'\n'; fi
  {
    printf '%s' "$sep"
    jq -r "$JQ_TO_YAML" "$src"
  } >>"$dst" || rollback "cannot write $dst"
  expected="$(jq -c -S "$JQ_EXPECTED" "$src")"
  actual="$(wit_yaml_binding_json "$dst" 2>"$SCRATCH/read.err" | jq -c -S . 2>/dev/null)"
  if [[ "$actual" != "$expected" ]]; then
    rollback "$dst does not read back as $src (expected $expected, read ${actual:-nothing}$(sed 's/^/; /' "$SCRATCH/read.err" | tr -d '\n')); nothing was removed"
  fi
done

for pair in "${PAIRS[@]}"; do
  printf 'migrated %s %s\n' "${pair%%|*}" "${pair#*|}"
done
# Past this point the YAML copies stand, so a failed removal is its own outcome,
# never a refusal.
for pair in "${PAIRS[@]}"; do
  if ! rm -f "${pair%%|*}"; then
    printf 'kept %s: the YAML copy is the binding now; remove the JSON file by hand\n' "${pair%%|*}"
    exit 4
  fi
  printf 'removed %s\n' "${pair%%|*}"
done
