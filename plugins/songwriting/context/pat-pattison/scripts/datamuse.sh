#!/usr/bin/env bash
# Datamuse API helper for /songwriting:rhyme (Pat Pattison method).
# Free, no auth, no key. https://www.datamuse.com/api/

set -euo pipefail

MODE="${1:-}"
shift || true
ARG="${*:-}"

usage() {
  cat >&2 <<'EOF'
Datamuse API helper for /songwriting:rhyme: word lists as TSV (word, score, syllables, tags) by score.
API: https://www.datamuse.com/api/ (free, no key).

Usage:
  datamuse.sh rhyme    <word>       perfect rhymes
  datamuse.sh near     <word>       near rhymes
  datamuse.sh cons     <word>       consonance
  datamuse.sh syn      <word>       synonyms
  datamuse.sh ant      <word>       antonyms
  datamuse.sh trg      <word>       semantic-field triggers
  datamuse.sh jja      <noun>       adjectives describing the noun
  datamuse.sh jjb      <adj>        nouns described by the adjective
  datamuse.sh means    <phrase>     reverse dictionary
  datamuse.sh sounds   <word>       sounds-like
  datamuse.sh pattern  <pattern>    letter pattern, e.g. t???t
  datamuse.sh syllables <word>      syllable count
  datamuse.sh family   <word>       near rhymes and consonance combined
  LIMIT=<n>                         results per request (default 25)

Examples:
  datamuse.sh rhyme lonely
  LIMIT=50 datamuse.sh near grief

Exit 0 on success; 1 on a usage error; nonzero on a failed request or unparsable reply.
EOF
}

emit_tsv() { jq -r '.[] | [.word, (.score // 0), (.numSyllables // 0), ((.tags // []) | join(","))] | @tsv'; }

fetch() { curl -sS "https://api.datamuse.com/words?$1&md=s&max=$max"; }

if [[ "$MODE" == "-h" || "$MODE" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$MODE" || -z "$ARG" ]]; then
  usage
  exit 1
fi

word="${ARG// /+}"
max="${LIMIT:-25}"

case "$MODE" in
rhyme) query="rel_rhy=$word" ;;
near) query="rel_nry=$word" ;;
cons) query="rel_cns=$word" ;;
syn | ant | trg | jja | jjb) query="rel_$MODE=$word" ;;
means) query="ml=$word" ;;
sounds) query="sl=$word" ;;
pattern) query="sp=$word" ;;
syllables)
  query="sp=$word"
  max=5
  ;;
family)
  near=$(fetch "rel_nry=$word")
  cons=$(fetch "rel_cns=$word")
  echo "$near $cons" | jq -s 'add | unique_by(.word) | sort_by(-(.score // 0))' | emit_tsv
  exit 0
  ;;
*)
  echo "unknown mode: $MODE" >&2
  usage
  exit 1
  ;;
esac

fetch "$query" | emit_tsv
