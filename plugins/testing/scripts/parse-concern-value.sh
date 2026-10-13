#!/usr/bin/env bash
# GENERATED from lib/parse-concern-value.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Resolve one value from a YAML concern file the way every consuming plugin
# must: quote-aware, comment-safe, whitespace-trimmed, trailing-slash-normalized,
# with a caller-supplied fallback for the case the key is absent.
#
# Parsing is yaml-subset.awk's, which sits beside this script in every copy:
# one YAML parser for the repository. A `#` inside a quoted value is part of the
# value, never a comment.
#
# SINGLE SOURCE OF TRUTH: lib/parse-concern-value.sh and lib/yaml-subset.awk at
# the marketplace repo root. The copies materialized into consuming plugins
# exist because installed plugins are cache-isolated and must be
# self-contained; never edit a copy. Edit the source and run
# scripts/sync-shared-copies.sh; CI rejects drifted copies.
#
# Usage:
#   parse-concern-value.sh [--strict] [--list] [--ref <ref>] <file|-> <key> [fallback]
#
#   <file>        path to the concern file; `-` reads the document from stdin
#                 (a remote reader passes text it fetched itself)
#   <key>         dotted key: `memory_dir`, `merge.rung`,
#                 `lanes.pr-merge.slots.0.activity` (sequence items by index)
#   [fallback]    value to emit when the key is absent or empty: the caller's
#                 already-resolved location or the schema default. This script
#                 never reads prose or schemas; the caller passes it in.
#   --list        print the scalar items of the sequence at <key>, one per line
#   --ref <ref>   read <file> as committed at <ref>: a 40-hex commit id or
#                 `origin/<name>`. Validated before any git call and passed to
#                 git after --end-of-options.
#   --strict      exit 3 on a parse error instead of taking the fallback
#
# Output: the resolved value, or empty when nothing resolves (the caller
# applies its documented default). Exit 0 for a well-formed invocation,
# including a missing file. A document the parser rejects is treated as absent
# with one stderr line, so a malformed file never stops a consumer; --strict
# makes it exit 3 for a caller that must tell an error from an absent key.
# Exit 2 for a usage error, an invalid key or ref, or a ref that does not
# resolve.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/yaml-subset.awk"

usage() {
  echo "parse-concern-value: usage: parse-concern-value.sh [--strict] [--list] [--ref <ref>] <file|-> <key> [fallback]" >&2
  exit 2
}

strict=0 list=0 has_ref=0 ref=""
pos=()
while (($#)); do
  case "$1" in
  -h | --help)
    awk 'NR > 1 && /^set -uo/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  --strict) strict=1 ;;
  --list) list=1 ;;
  --ref)
    (($# >= 2)) || usage
    has_ref=1 ref="$2"
    shift
    ;;
  --)
    shift
    pos+=("$@")
    break
    ;;
  *) pos+=("$1") ;;
  esac
  shift
done

concern_file="${pos[0]:-}"
key="${pos[1]:-}"
fallback="${pos[2]:-}"
[[ -n "$concern_file" && -n "$key" ]] || usage
if [[ ! "$key" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "parse-concern-value: invalid key; expected [A-Za-z0-9_.-]+" >&2
  exit 2
fi

text="" present=1
if ((has_ref)); then
  # Only a full commit id or origin/<name> passes; nothing that git could read
  # as an option, a revision range or a path.
  if [[ "$concern_file" == "-" ]] ||
    ! [[ "$ref" =~ ^[0-9a-f]{40}$ || ("$ref" =~ ^origin/[A-Za-z0-9._/-]+$ && "$ref" != *..* && "$ref" != origin/-*) ]]; then
    echo "parse-concern-value: invalid --ref; expected a 40-hex commit id or origin/<name>, and a file path" >&2
    exit 2
  fi
  if ! git rev-parse --verify --quiet --end-of-options "$ref^{commit}" >/dev/null; then
    echo "parse-concern-value: --ref does not resolve to a commit: $ref" >&2
    exit 2
  fi
  text="$(git show --end-of-options "$ref:$concern_file" 2>/dev/null)" || present=0
elif [[ "$concern_file" == "-" ]]; then
  text="$(cat)"
elif [[ -f "$concern_file" ]]; then
  text="$(<"$concern_file")"
else
  present=0
fi

records=""
if ((present)); then
  if ! records="$(LC_ALL=C awk -f "$PARSER" <<<"$text")"; then
    printf 'parse-concern-value: %s: line %s\n' "$concern_file" \
      "$(awk -F '\t' '$1 == "error" { print $2 ": " $3 }' <<<"$records" | tail -n 1)" >&2
    ((strict)) && exit 3
    records=""
  fi
fi

values=()
# shellcheck disable=SC2016 # awk programs, expanded by awk, not the shell.
if ((list)); then
  pattern='index($1, ENVIRON["PCV_KEY"] ".") == 1 && substr($1, length(ENVIRON["PCV_KEY"]) + 2) ~ /^[0-9]+$/'
else
  pattern='$1 == ENVIRON["PCV_KEY"] && !seen++'
fi
while IFS= read -r v; do
  v="${v%/}" # normalize a single trailing slash
  [[ -z "$v" ]] || values+=("$v")
done < <(PCV_KEY="$key" LC_ALL=C awk -F '\t' "$pattern"' { print substr($0, length($1) + 2) }' <<<"$records")

if ((${#values[@]} == 0)); then
  values=("$fallback")
fi
printf '%s\n' "${values[@]}"
