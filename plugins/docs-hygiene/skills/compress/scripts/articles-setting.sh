#!/usr/bin/env bash
# Exit: 0 after printing the setting line; 2 on a usage error.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/../../../lib/parse-concern-value.sh"
REL="docs/conventions/docs-hygiene.yaml"
KEY="compress_articles"

if (($# > 1)); then
  echo "articles-setting: usage: articles-setting.sh [<dir>]" >&2
  exit 2
fi
dir="${1:-.}"

if ! root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [[ -z "$root" ]]; then
  printf 'unset\tnot in a git working tree\n'
  exit 0
fi
home="$(cd "$HOME" 2>/dev/null && pwd -P)" || home="$HOME"
if [[ "$home" == "$root" || "$home" == "${root%/}/"* ]]; then
  printf 'unset\t%s\n' "repository root is \$HOME or an ancestor of it"
  exit 0
fi

file="$root/$REL"
if [[ ! -f "$file" ]]; then
  printf 'unset\tno %s\n' "$REL"
  exit 0
fi

key_re="^[\"']?${KEY}[\"']?[[:space:]]*:"
key_lines="$(grep -E "$key_re" "$file")"
count="$(grep -cE "$key_re" "$file")"

if ((count > 1)); then
  printf 'invalid\tset %s times\n' "$count"
  exit 0
fi

value="$(bash "$READER" --strict "$file" "$KEY" 2>/dev/null)"
if (($? == 3)); then
  printf 'invalid\tdoes not parse\n'
  exit 0
fi
if ((count == 0)) && [[ -z "$value" ]]; then
  printf 'unset\t%s not set in %s\n' "$KEY" "$REL"
  exit 0
fi
case "$value" in
keep | cut)
  printf '%s\n' "$value"
  exit 0
  ;;
*) ;;
esac

raw="${key_lines#*:}"
raw="$(printf '%s' "$raw" | sed -E 's/(^|[[:space:]])#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
printf 'invalid\t%s\n' "${raw:-(no value)}"
