#!/usr/bin/env bash
# Read compress_articles from the repository layer, docs/conventions/docs-hygiene.yaml.
#
# Usage: articles-setting.sh [<dir>]
#
#   <dir>  a directory inside the repository; default: the current directory.
#
# Prints one line, tab-separated, and exits 0:
#   keep | cut                 the file sets a valid value
#   unset<TAB><reason>         the layer does not apply: no git working tree, a root
#                              that is $HOME or an ancestor of it, no file, or no key
#   invalid<TAB><what>         the key is present but holds no valid value: the raw
#                              value, "(no value)", "set N times" or "does not parse"
# Exit 2 on a usage error. The caller resolves the other layers and the default
# (reference/config.md); this script reads only the repository file.
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

# Root-level lines naming the key, quoted or not, with any spacing before the colon.
key_re="^[\"']?${KEY}[\"']?[[:space:]]*:"
key_lines="$(grep -E "$key_re" "$file")"
count="$(grep -cE "$key_re" "$file")"

value="$(bash "$READER" --strict "$file" "$KEY" 2>/dev/null)"
status=$?
if ((status == 3)); then
  printf 'invalid\tdoes not parse\n'
  exit 0
fi
if [[ ! "$count" =~ ^[0-9]+$ ]] || ((count == 0)); then
  if [[ -z "$value" ]]; then
    printf 'unset\t%s not set in %s\n' "$KEY" "$REL"
    exit 0
  fi
  count=1
fi
if ((count > 1)); then
  printf 'invalid\tset %s times\n' "$count"
  exit 0
fi
case "$value" in
keep | cut)
  printf '%s\n' "$value"
  exit 0
  ;;
*) ;;
esac

# Present without a valid value: report what the line holds after the colon.
raw="${key_lines#*:}"
raw="$(printf '%s' "$raw" | sed -E 's/(^|[[:space:]])#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
printf 'invalid\t%s\n' "${raw:-(no value)}"
