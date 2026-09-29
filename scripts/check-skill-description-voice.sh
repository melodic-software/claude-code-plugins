#!/usr/bin/env bash
# Fail a skill description that addresses the reader: `you`, `your`, `yours`,
# `yourself` or `yourselves` outside a single-quoted trigger phrase. The
# description is injected into the system prompt, so Anthropic's skill-authoring
# best practices keep it in the third person (#4112):
# https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions
#
#   scripts/check-skill-description-voice.sh --all          every plugin skill
#   scripts/check-skill-description-voice.sh <base-ref>     skills changed since
#                                                           the merge base
#   scripts/check-skill-description-voice.sh --paths FILE...
#
# A quoted trigger phrase opens with `'` at the start or after whitespace, `:`,
# `,` or `(`, and closes at the first later `'` followed by `,`, `.`, `;`, `)`,
# whitespace or the end, so an apostrophe inside a phrase (`'don't stop'`)
# does not end it early; an escaped `\"` delimits a phrase the same way. The
# phrase is the user's words and is not judged. A hyphenated name such as
# `do-your-research` is one word, not a pronoun.
#
# Exit 0 clean, 1 findings (on stderr), 2 usage or environment.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# shellcheck source=lib/changed-files.sh
source scripts/lib/changed-files.sh || exit 2

usage() {
  echo "usage: check-skill-description-voice.sh --all | <base-ref> | --paths FILE..." >&2
  exit 2
}

files=()
case "${1:-}" in
--all)
  for f in plugins/*/skills/*/SKILL.md; do
    [[ -f "$f" ]] && files+=("$f")
  done
  ;;
--paths)
  shift
  (($# > 0)) || usage
  files=("$@")
  ;;
"" | -*) usage ;;
*)
  # shellcheck disable=SC2310  # verify_base is one git call; its non-zero return is the handled case
  changed_files::verify_base "$1" || {
    echo "check-skill-description-voice: base-ref '$1' is not a commit" >&2
    exit 2
  }
  changed=()
  changed_files::into changed "$1...HEAD" || exit 2
  for f in ${changed[@]+"${changed[@]}"}; do
    [[ "$f" == plugins/*/skills/*/SKILL.md && "$f" != plugins/*/skills/*/*/* && -f "$f" ]] && files+=("$f")
  done
  ;;
esac

((${#files[@]} > 0)) || {
  echo "check-skill-description-voice: no skills to check"
  exit 0
}

awk '
  FNR == 1 { fm = ($0 ~ /^---[[:space:]]*$/); blk = 0; next }
  # A block-scalar description (`>-`, `|`) is its indented continuation lines.
  fm && blk && /^([[:space:]]|$)/ { acc = acc " " $0; next }
  fm && blk { check(FILENAME, acc); blk = 0 }
  fm && /^---[[:space:]]*$/ { fm = 0; next }
  fm && /^description:[[:space:]]*[>|][-+0-9]*[[:space:]]*$/ { blk = 1; acc = ""; next }
  fm && /^description:/ { check(FILENAME, substr($0, 13)) }

  function strip(s,   out, i, j, n, c, prev) {
    out = ""; n = length(s); i = 1
    while (i <= n) {
      c = substr(s, i, 1)
      prev = (i == 1) ? " " : substr(s, i - 1, 1)
      if (c == "\047" && prev ~ /[[:space:]:,(]/) {
        for (j = i + 1; j <= n; j++)
          if (substr(s, j, 1) == "\047" && (j == n || substr(s, j + 1, 1) ~ /[,.;)[:space:]]/)) break
        if (j <= n) { out = out " "; i = j + 1; continue }
      }
      out = out c; i++
    }
    return out
  }

  function check(file, desc,   text, words, n, k, hits) {
    # An escaped double quote delimits a trigger phrase the same way.
    gsub(/\\"/, "\047", desc)
    text = tolower(strip(desc))
    # A hyphenated name (do-your-research, You-I-We) is one word, not a pronoun.
    gsub(/[^a-z-]+/, " ", text)
    n = split(text, words, " ")
    hits = ""
    for (k = 1; k <= n; k++)
      if (words[k] ~ /^(you|your|yours|yourself|yourselves)$/ && index(" " hits " ", " " words[k] " ") == 0)
        hits = hits (hits == "" ? "" : " ") words[k]
    if (hits != "") {
      printf "FAIL: %s: description addresses the reader (%s) outside a quoted trigger phrase\n", file, hits > "/dev/stderr"
      bad++
    }
  }

  END {
    if (bad > 0) {
      printf "check-skill-description-voice: %d of %d description(s) address the reader; write them in the third person\n", bad, ARGC - 1 > "/dev/stderr"
      exit 1
    }
    printf "check-skill-description-voice: PASS (%d skills)\n", ARGC - 1
  }
' "${files[@]}"
