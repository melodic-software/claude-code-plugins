#!/usr/bin/env bash
# setup-check.sh — verify the docs-hygiene consumer configuration surface.
#
# Read-only. Prints one row per check and changes nothing, so it is safe to run
# against a repository nobody has reviewed.
#
# WHAT IT IS FOR. Every value the file-name skills act on comes from
# `.claude/docs-hygiene.json` and its two personal layers: which tree is scoped,
# which names are legal, which references may be rewritten in which form, and
# which shell command runs after a generated file moves. A malformed layer, a
# regex that no grep accepts, or a regenerator whose command is not installed all
# fail LATE otherwise: the audit reports nothing, or the realign stops with a
# tree half migrated. This turns each of those into a row before any of it runs.
#
# Every single-quoted `${...}` below is a jq program argument, substituted by jq
# from --arg/--argjson, never by the shell.
# shellcheck disable=SC2016
#
# Usage:
#   setup-check.sh [--root <dir>] [--home <dir>]
#   setup-check.sh --help
#
# Exit: 0 every check passed (WARN and INFO rows do not fail the run),
#       1 at least one FAIL row, 2 usage or a missing prerequisite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
KNOWN_RULES=" lower-kebab "
KNOWN_FORMS=" all links-and-paths none "
GITIGNORE_LINE='.claude/**/*.local.*'

FAILS=0

die() {
  printf 'setup-check: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

row() {
  printf '%-4s  %-26s  %s\n' "$1" "$2" "$3"
  [[ "$1" == FAIL ]] && FAILS=$((FAILS + 1))
  return 0
}

ROOT=""
HOME_DIR="${HOME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --home)
    shift
    [[ $# -gt 0 ]] || die "--home needs a directory"
    HOME_DIR="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument '$1'"
    ;;
  esac
  shift
done

[[ -f "$RESOLVER" ]] || die "resolver missing at $RESOLVER"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

resolver() {
  bash "$RESOLVER" "$@" --root "$ROOT" --home "$HOME_DIR"
}

# --- prerequisites -----------------------------------------------------------

if command -v jq >/dev/null 2>&1; then
  row PASS "jq" "$(jq --version 2>/dev/null || echo present)"
else
  row FAIL "jq" "not on PATH; every skill in this plugin reads the concern file with jq"
  printf '\nsetup-check: 1 FAIL\n'
  exit 1
fi

if command -v git >/dev/null 2>&1; then
  row PASS "git" "$(git --version 2>/dev/null)"
  HAVE_GIT=1
else
  row WARN "git" "not on PATH; the tracked and ignored rows below are skipped"
  HAVE_GIT=0
fi

# --- layers ------------------------------------------------------------------

layer_paths="$(resolver paths)" || die "cannot resolve the layer paths"
while IFS="$(printf '\t')" read -r name path state; do
  [[ -n "$name" ]] || continue
  case "$state" in
  present) row PASS "layer $name" "$path" ;;
  absent) row INFO "layer $name" "absent; the layer below it supplies these keys" ;;
  *) row INFO "layer $name" "$state" ;;
  esac
done <<EOF
$layer_paths
EOF

if ! CONFIG="$(resolver resolve 2>&1)"; then
  row FAIL "resolve" "$CONFIG"
  printf '\nsetup-check: %d FAIL\n' "$FAILS"
  exit 1
fi
row PASS "resolve" "every present layer parses and declares this contract's schema"

get() {
  printf '%s' "$CONFIG" | jq -r "$1" 2>/dev/null
}

# --- key shapes --------------------------------------------------------------

shape_errors="$(printf '%s' "$CONFIG" | jq -r '
  .file_names as $f
  | [
      (if ($f.roots | type) != "array" or ($f.roots | length) == 0
         then "roots must be a non-empty array" else empty end),
      (if ($f.roots | map(select(type != "string")) | length) > 0
         then "roots must hold strings" else empty end),
      (if ($f.rule | type) != "string" then "rule must be a string" else empty end),
      (if ($f.regex | type) != "string" then "regex must be a string" else empty end),
      (["exempt_basenames","exempt_paths","exempt_extensions","sweep_exclude","sweep_exclude_sites"][]
        | . as $k
        | if ($f[$k] | type) != "array" then "\($k) must be an array" else empty end),
      (if ($f.tiers | type) != "array" then "tiers must be an array" else empty end),
      (if ($f.generated | type) != "array" then "generated must be an array" else empty end),
      (if ($f.redirect_map != null and ($f.redirect_map | type) != "string")
         then "redirect_map must be null or a string" else empty end)
    ]
  | .[]
')"
if [[ -n "$shape_errors" ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && row FAIL "key shape" "$line"
  done <<EOF
$shape_errors
EOF
else
  row PASS "key shape" "every key carries the type this contract declares"
fi

rule="$(get '.file_names.rule')"
case "$KNOWN_RULES" in
*" $rule "*) row PASS "rule" "$rule" ;;
*) row FAIL "rule" "'$rule' is not a rule this version implements (known:${KNOWN_RULES%?})" ;;
esac

# --- the casing regex --------------------------------------------------------

regex="$(get '.file_names.regex')"
if printf 'probe.md' | grep -Eq "$regex" >/dev/null 2>&1; then
  row PASS "regex" "compiles under grep -E and accepts a lower-kebab probe"
elif [[ $? -eq 1 ]]; then
  row WARN "regex" "compiles, but rejects the probe 'probe.md'; confirm that is intended"
else
  row FAIL "regex" "grep -E cannot compile it: $regex"
fi

case "$regex" in
*"'"*) row FAIL "regex quoting" "holds a single quote; the emitted gate inlines this value" ;;
*) row PASS "regex quoting" "free of the single quote the gate emitter cannot inline" ;;
esac

# --- tiers -------------------------------------------------------------------

tier_names="$(get '.file_names.tiers[].name')"
dupes="$(printf '%s\n' "$tier_names" | sort | uniq -d | tr '\n' ' ')"
if [[ -n "${dupes// /}" ]]; then
  row FAIL "tier names" "duplicated: $dupes"
else
  row PASS "tier names" "unique: $(printf '%s' "$tier_names" | tr '\n' ' ')"
fi

bad_forms=""
while IFS= read -r form; do
  [[ -n "$form" ]] || continue
  case "$KNOWN_FORMS" in
  *" $form "*) ;;
  *) bad_forms="$bad_forms $form" ;;
  esac
done <<EOF
$(get '.file_names.tiers[].forms')
EOF
if [[ -n "$bad_forms" ]]; then
  row FAIL "tier forms" "unknown:$bad_forms (known:${KNOWN_FORMS%?})"
else
  row PASS "tier forms" "every tier names a form this version applies"
fi

# --- generated files and their regenerators ----------------------------------

gen_count="$(get '.file_names.generated | length')"
if [[ "$gen_count" == "0" ]]; then
  row INFO "generated" "no generated file declared; nothing is regenerated after a move"
else
  while IFS="$(printf '\t')" read -r gpath gcmd; do
    [[ -n "$gpath" ]] || continue
    if [[ -z "$gcmd" || "$gcmd" == "null" ]]; then
      row FAIL "generated $gpath" "no regenerate command; the realign would leave it stale"
      continue
    fi
    # An interpreter as the first word says nothing about whether the script it
    # runs exists, so step past it and resolve the argument that does.
    first="${gcmd%% *}"
    rest="${gcmd#* }"
    target="$first"
    case "$first" in
    bash | sh | zsh | python | python3 | node | ruby | perl | pwsh)
      [[ "$rest" != "$gcmd" ]] && target="${rest%% *}"
      ;;
    *) ;;
    esac
    if command -v "$target" >/dev/null 2>&1 || [[ -e "$ROOT/$target" ]]; then
      row PASS "generated $gpath" "regenerator resolves: $target"
    else
      row FAIL "generated $gpath" "regenerator '$target' resolves to nothing on PATH or under the root"
    fi
  done <<EOF
$(printf '%s' "$CONFIG" | jq -r '.file_names.generated[] | [.path, (.regenerate // "")] | @tsv')
EOF
fi

# --- tracked team layer, ignored overlay -------------------------------------

TEAM_LAYER=".claude/docs-hygiene.json"
OVERLAY_LAYER=".claude/docs-hygiene.local.json"

if [[ "$HAVE_GIT" -eq 1 && -f "$ROOT/$TEAM_LAYER" ]]; then
  if git -C "$ROOT" check-ignore -q "$TEAM_LAYER" 2>/dev/null; then
    row FAIL "team layer tracked" "$TEAM_LAYER is gitignored; an ignored team layer never reaches the team"
  elif git -C "$ROOT" ls-files --error-unmatch "$TEAM_LAYER" >/dev/null 2>&1; then
    row PASS "team layer tracked" "$TEAM_LAYER is committed"
  else
    row WARN "team layer tracked" "$TEAM_LAYER is written but untracked; commit it to share it"
  fi
elif [[ ! -f "$ROOT/$TEAM_LAYER" ]]; then
  row INFO "team layer tracked" "no team layer yet; run setup apply --defaults to write one"
fi

if [[ "$HAVE_GIT" -eq 1 && -f "$ROOT/$OVERLAY_LAYER" ]]; then
  if git -C "$ROOT" check-ignore -q "$OVERLAY_LAYER" 2>/dev/null; then
    row PASS "overlay ignored" "$OVERLAY_LAYER is gitignored"
  else
    row WARN "overlay ignored" "$OVERLAY_LAYER is not gitignored; the recommended line is $GITIGNORE_LINE"
  fi
fi

# --- policy-floor declarations a personal layer cannot supply ----------------

inert="$(resolver layers | grep '^!inert:' || true)"
if [[ -n "$inert" ]]; then
  while IFS="$(printf '\t')" read -r marker layer reason; do
    [[ -n "$marker" ]] || continue
    row WARN "${marker#!inert:} override" "declared by the $layer layer and ignored ($reason)"
  done <<EOF
$inert
EOF
else
  row PASS "policy floor" "no personal layer declares a key only the team layer supplies"
fi

if [[ "$FAILS" -eq 0 ]]; then
  printf '\nsetup-check: 0 FAIL\n'
  exit 0
fi
printf '\nsetup-check: %d FAIL\n' "$FAILS"
exit 1
