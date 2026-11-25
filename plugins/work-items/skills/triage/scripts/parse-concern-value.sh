#!/usr/bin/env bash
# GENERATED from lib/parse-concern-value.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
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
    cat <<'EOF'
Resolve one value from a YAML concern file, or the fallback when the key is absent or empty.
Usage: parse-concern-value.sh [--strict] [--list] [--ref <ref>] <file|-> <key> [fallback]
  <file|->     the concern file; - reads the document from stdin
  <key>        dotted key, e.g. merge.rung or lanes.pr-merge.slots.0.activity
  [fallback]   the value printed when the key is absent or empty
  --list       print the scalar items of the sequence at <key>, one per line
  --ref <ref>  read <file> as committed at <ref>: a 40-hex commit id or origin/<name>
  --strict     exit 3 on a parse error instead of taking the fallback
Exit codes:
  0  a well-formed invocation, including a missing or rejected file
  2  usage error, an invalid key or ref, or a ref that does not resolve
  3  --strict and the document does not parse
EOF
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
  if ! records="$(LC_ALL=C awk -v STRICT="$strict" -f "$PARSER" <<<"$text")"; then
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
