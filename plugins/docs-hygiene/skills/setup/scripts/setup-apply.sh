#!/usr/bin/env bash
# setup-apply.sh — write the docs-hygiene team configuration layer.
#
# WRITES EXACTLY ONE FILE: `<root>/.claude/docs-hygiene.json`. Not the personal
# layers, which are the operator's own files; not `.gitignore`, which is the
# consumer's; not anything else. The setup contract scopes `apply` to the
# artifact the plugin owns, and this script has no code path to any other.
#
# IDEMPOTENT. Values are merged per key and compared as parsed JSON, so a re-run
# that changes nothing prints `already configured` and leaves the file's bytes
# alone. Hand-written `_comment` text survives every merge.
#
# Every single-quoted `${...}` below is a jq program argument, substituted by jq
# from --arg/--argjson, never by the shell.
# shellcheck disable=SC2016
#
# Usage:
#   setup-apply.sh --defaults [--root <dir>]
#   setup-apply.sh <key>=<value> [<key>=<value> ...] [--root <dir>]
#   setup-apply.sh --help
#
#   --defaults    write the bundled document when no team layer exists, and
#                 report the existing one untouched when it does
#   <key>=<value> merge one key of `file_names` (the `file_names.` prefix is
#                 optional). The value is parsed as JSON when it parses, and
#                 taken as a string when it does not, so
#                 `roots=["docs","guide"]` sets a list and `rule=lower-kebab`
#                 sets a scalar.
#
# Exit: 0 written or already configured, 2 usage error or an unwritable target.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../templates/docs-hygiene.json"
TARGET_REL=".claude/docs-hygiene.json"

die() {
  printf 'setup-apply: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

jqr() {
  jq "$@" | tr -d '\r'
}

ROOT=""
WANT_DEFAULTS=0
PAIRS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --defaults)
    WANT_DEFAULTS=1
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    die "unknown flag '$1'"
    ;;
  *=*)
    PAIRS="$PAIRS
$1"
    ;;
  *)
    die "expected --defaults or <key>=<value>, got '$1'"
    ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
[[ -f "$TEMPLATE" ]] || die "bundled defaults missing at $TEMPLATE"
[[ "$WANT_DEFAULTS" -eq 1 || -n "$PAIRS" ]] || die "nothing to do: pass --defaults or at least one <key>=<value>"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

TARGET="$ROOT/$TARGET_REL"

if [[ -f "$TARGET" ]]; then
  current="$(jqr -e . "$TARGET" 2>/dev/null)" || die "the existing team layer is not valid JSON: $TARGET"
else
  current="$(jqr -e . "$TEMPLATE" 2>/dev/null)" || die "bundled defaults are not valid JSON: $TEMPLATE"
  [[ "$WANT_DEFAULTS" -eq 1 || -n "$PAIRS" ]] || exit 0
fi

before="$current"

while IFS= read -r pair; do
  [[ -n "$pair" ]] || continue
  key="${pair%%=*}"
  value="${pair#*=}"
  key="${key#file_names.}"
  [[ -n "$key" ]] || die "empty key in '$pair'"
  if printf '%s' "$value" | jq -e . >/dev/null 2>&1; then
    current="$(jqr -c --arg k "$key" --argjson v "$value" '.file_names[$k] = $v' <<<"$current")" ||
      die "cannot set '$key'"
  else
    current="$(jqr -c --arg k "$key" --arg v "$value" '.file_names[$k] = $v' <<<"$current")" ||
      die "cannot set '$key'"
  fi
done <<EOF
$PAIRS
EOF

current="$(jqr -c '.schema = 1' <<<"$current")" || die "cannot stamp the schema"

# Compare as parsed JSON so formatting alone never rewrites the file.
if [[ -f "$TARGET" ]] && jqr -e -n --argjson a "$before" --argjson b "$current" '$a == $b' >/dev/null 2>&1; then
  printf 'already configured: %s\n' "$TARGET_REL"
  exit 0
fi

mkdir -p "$(dirname "$TARGET")" || die "cannot create $(dirname "$TARGET")"
tmp="$TARGET.tmp.$$"
if ! jqr --indent 2 . <<<"$current" >"$tmp"; then
  rm -f "$tmp"
  die "cannot render the merged document"
fi
if ! cat "$tmp" >"$TARGET"; then
  rm -f "$tmp"
  die "cannot write $TARGET"
fi
rm -f "$tmp"

printf 'wrote: %s\n' "$TARGET_REL"
printf 'commit it: an uncommitted team layer has reached no other checkout yet.\n'
exit 0
