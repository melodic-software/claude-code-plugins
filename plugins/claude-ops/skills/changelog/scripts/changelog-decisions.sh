#!/usr/bin/env bash
# Render component decisions for one changelog read.
#
# Input is TSV, one decision per line, no header:
#   lens, title, items, owner, sentence, store, docs_lag
# lens is correct, replace, adopt, note, or skip.
# skip leaves no row. correct, adopt, and note require a sentence.
# replace prints the store cell as "nominated" while the store row is still
# pending a human verdict, and never prints "replaced".
# A non-empty docs_lag cell is listed under Docs lag, not as a decision row
# of its own.
#
# Exit 0 on a rendered ledger. Exit 2 when a kept row is missing its sentence
# or the lens is unknown.
set -euo pipefail

in="${1:-}"
if [[ -z "$in" || ! -f "$in" ]]; then
  echo "usage: changelog-decisions.sh <decisions.tsv>" >&2
  exit 2
fi

corrected=""
replaced=""
adopted=""
noted=""
lag=""

while IFS=$'\t' read -r lens title items owner sentence store docs_lag || [[ -n "${lens:-}" ]]; do
  [[ -z "${lens:-}" || "$lens" == \#* ]] && continue
  case "$lens" in
  skip) continue ;;
  correct | adopt | note)
    if [[ -z "$sentence" ]]; then
      echo "changelog-decisions: $lens row '$title' has no sentence" >&2
      exit 2
    fi
    ;;
  replace)
    if [[ -z "$sentence" ]]; then
      echo "changelog-decisions: replace row '$title' has no sentence" >&2
      exit 2
    fi
    store_cell="nominated"
    case "$store" in
    *pending* | "") store_cell="nominated" ;;
    *)
      # A human verdict already recorded in the store is quoted, never upgraded
      # to "replaced" by this renderer.
      store_cell="$store"
      ;;
    esac
    if [[ "$store_cell" == replaced ]]; then
      echo "changelog-decisions: a replace row is nominated until a human verdict, never replaced" >&2
      exit 2
    fi
    ;;
  *)
    echo "changelog-decisions: unknown lens '$lens'" >&2
    exit 2
    ;;
  esac
  row="| $title | $items | $owner | $sentence |"
  case "$lens" in
  correct) corrected+="$row"$'\n' ;;
  adopt) adopted+="$row"$'\n' ;;
  note) noted+="$row"$'\n' ;;
  replace) replaced+="| $title | $items | $owner | $sentence | $store_cell |"$'\n' ;;
  *)
    echo "changelog-decisions: unknown lens '$lens'" >&2
    exit 2
    ;;
  esac
  if [[ -n "$docs_lag" ]]; then
    lag+="- $title: $docs_lag"$'\n'
  fi
done <"$in"

echo "# Changelog decisions"
echo
if [[ -n "$corrected" ]]; then
  echo "## Corrected"
  echo
  echo "| Decision | Items | Owner surface | Was stated / is true |"
  echo "|---|---|---|---|"
  printf '%s' "$corrected"
  echo
fi
if [[ -n "$replaced" ]]; then
  echo "## Replaced with native"
  echo
  echo "| Candidate | Items | Component | Problem solved | Store row |"
  echo "|---|---|---|---|---|"
  printf '%s' "$replaced"
  echo
fi
if [[ -n "$adopted" ]]; then
  echo "## Adopted"
  echo
  echo "| Decision | Items | Component | Problem solved |"
  echo "|---|---|---|---|"
  printf '%s' "$adopted"
  echo
fi
if [[ -n "$noted" ]]; then
  echo "## Noted"
  echo
  echo "| Decision | Items | Owner surface | Note |"
  echo "|---|---|---|---|"
  printf '%s' "$noted"
  echo
fi
if [[ -n "$lag" ]]; then
  echo "## Docs lag"
  echo
  printf '%s' "$lag"
  echo
fi
exit 0
