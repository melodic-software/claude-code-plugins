#!/usr/bin/env bash
# Datamuse API helper for /pat-pattison.
# Free, no auth, no key. https://www.datamuse.com/api/
#
# Why this exists: AI rhyme/syllable/semantic recall is unreliable. Pat's
# identity-vs-rhyme check (pre-vowel consonants MUST differ) is hard to apply
# without word-by-word data. This helper compensates.
#
# Usage:
#   datamuse.sh rhyme    <word>          # rel_rhy perfect rhymes
#   datamuse.sh near     <word>          # rel_nry near rhymes
#   datamuse.sh cons     <word>          # rel_cns consonance
#   datamuse.sh syn      <word>          # rel_syn synonyms
#   datamuse.sh ant      <word>          # rel_ant antonyms
#   datamuse.sh trg      <word>          # rel_trg semantic-field triggers
#   datamuse.sh jja      <noun>          # adjectives describing the noun
#   datamuse.sh jjb      <adj>           # nouns described by the adj
#   datamuse.sh means    <phrase>        # ml reverse-dictionary
#   datamuse.sh sounds   <word>          # sl sounds-like
#   datamuse.sh pattern  <pattern>       # sp letter pattern, e.g. t???t
#   datamuse.sh syllables <word>         # syllable count via numSyllables
#   datamuse.sh family   <word>          # near + cons combined for family rhyme
#
# All modes return TSV (word\tscore\tnumSyllables\ttags) sorted by score desc.
# Default limit: 25 results. Override with LIMIT=<n>.
#
# Examples:
#   datamuse.sh rhyme lonely
#   datamuse.sh family stranger
#   datamuse.sh trg winter | head -30
#   datamuse.sh jja moon | head -20
#   datamuse.sh syllables disappointment
#   LIMIT=50 datamuse.sh near grief

set -euo pipefail

LIMIT="${LIMIT:-25}"
MODE="${1:-}"
shift || true
ARG="${*:-}"

usage() { sed -n '2,28p' "$0" >&2; }

# jq: emit each result as TSV (word, score, numSyllables, tags).
emit_tsv() { jq -r '.[] | [.word, (.score // 0), (.numSyllables // 0), ((.tags // []) | join(","))] | @tsv'; }

if [[ -z "$MODE" || -z "$ARG" ]]; then
  usage
  exit 1
fi

api="https://api.datamuse.com/words"
word=$(printf %s "$ARG" | sed 's/ /+/g')
max="$LIMIT"

case "$MODE" in
  rhyme) query="rel_rhy=$word" ;;
  near) query="rel_nry=$word" ;;
  cons) query="rel_cns=$word" ;;
  syn) query="rel_syn=$word" ;;
  ant) query="rel_ant=$word" ;;
  trg) query="rel_trg=$word" ;;
  jja) query="rel_jja=$word" ;;
  jjb) query="rel_jjb=$word" ;;
  means) query="ml=$word" ;;
  sounds) query="sl=$word" ;;
  pattern) query="sp=$word" ;;
  syllables)
    query="sp=$word"
    max=5
    ;;
  family)
    # near rhymes + consonance, combined; useful for Pat's family-rhyme search
    near=$(curl -sS "$api?rel_nry=$word&md=s&max=$LIMIT")
    cons=$(curl -sS "$api?rel_cns=$word&md=s&max=$LIMIT")
    echo "$near $cons" \
      | jq -s 'add | unique_by(.word) | sort_by(-(.score // 0))' \
      | emit_tsv
    exit 0
    ;;
  *)
    echo "unknown mode: $MODE" >&2
    usage
    exit 1
    ;;
esac

curl -sS "$api?$query&md=s&max=$max" | emit_tsv
