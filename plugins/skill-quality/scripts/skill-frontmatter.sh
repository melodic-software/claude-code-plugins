# shellcheck shell=bash
# Shared SKILL.md frontmatter helpers for skill gates.
# Sourced by check-skill.sh (and the repo's summary-reader parity test); source
# it from future skill validators too.

if [[ -n "${SKILL_FRONTMATTER_LIB_LOADED:-}" ]]; then
  # shellcheck disable=SC2317  # reachable via source (return) or direct exec (exit); standalone lint can't see the sourced context
  return 0 2>/dev/null || exit 0
fi
SKILL_FRONTMATTER_LIB_LOADED=1

# Extract YAML frontmatter (between first two --- fences) from stdin.
# The opening fence MUST be line 1 — content before it is not frontmatter, so a
# stray `---` further down cannot be mistaken for the block's start.
skill_frontmatter::extract() {
  awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    /^---[[:space:]]*$/ { fence++; if (fence == 1) next; if (fence >= 2) exit }
    fence == 1 { print }
  '
}

# Extract a frontmatter scalar by key (quotes stripped) from stdin. A block
# scalar header (`key: |` / `key: >`, with an optional indent and/or chomp
# indicator in either order and an optional trailing `# comment`) is unfolded to
# its text so downstream length / trigger / phrasing checks see the content
# rather than the `|` / `>` marker: literal (`|`) joins lines with newlines,
# folded (`>`) with spaces.
#
# A trailing YAML comment on the key line is dropped, because a real YAML reader
# — which is what the harness loads frontmatter with — never delivers it as part
# of the value. Without this, `description: "12345" # note` measures the comment
# and the quotes `strip_quotes` can no longer see as outer, inflating every
# length / trigger check that reads the field. Stripping is quote-aware and is
# confined to this plain/flow branch: inside a block scalar a `#` is content
# (a markdown heading in a `description: |` body), never a comment.
skill_frontmatter::field() {
  local key="$1"
  awk -v k="$key" '
    # Cut a trailing YAML comment from a plain or flow scalar. A quoted scalar
    # ends at its closing quote and anything after it is comment; a plain scalar
    # ends at the first whitespace-preceded `#`. An unterminated quote is left
    # whole, because malformed YAML is not for this helper to guess at.
    # \047 is a single quote: the awk program is single-quoted by the shell, so
    # spelling the character out would end the program mid-expression.
    function fm_strip_comment(v,   n, q, i, ch) {
      n = length(v)
      if (n == 0) return v
      q = substr(v, 1, 1)
      if (q == "\"" || q == "\047") {
        i = 2
        while (i <= n) {
          ch = substr(v, i, 1)
          if (q == "\"" && ch == "\\") { i += 2; continue }
          if (ch == q) {
            # A single-quoted YAML scalar escapes one quote by doubling it.
            if (q == "\047" && substr(v, i + 1, 1) == "\047") { i += 2; continue }
            return substr(v, 1, i)
          }
          i++
        }
        return v
      }
      # A value that opens with `#` is all comment: the scalar is empty.
      if (q == "#") return ""
      if (match(v, /[[:space:]]+#/)) return substr(v, 1, RSTART - 1)
      return v
    }
    $0 ~ "^" k ":[[:space:]]*" {
      val = $0
      sub("^" k ":[[:space:]]*", "", val)
      if (val ~ /^[|>]([0-9][+-]?|[+-][0-9]?)?[[:space:]]*(#.*)?$/) {
        # Text capture for the checks (not a full YAML parser): a frontmatter
        # key sits at column 0, so every indented line is block content and the
        # first column-0 line is the next key. Collecting on that boundary
        # ignores the indent indicator entirely, so an explicit indent smaller
        # than the first content line cannot drop later lines. Leading indent is
        # stripped per line (irrelevant to length / trigger / phrasing checks).
        fold = (val ~ /^>/)
        out = ""; started = 0
        while ((getline line) > 0) {
          if (line ~ /^[[:space:]]*$/) { if (started) out = out (fold ? " " : "\n"); continue }
          if (line !~ /^[[:space:]]/) break
          sub(/^[[:space:]]+/, "", line)
          if (started) out = out (fold ? " " : "\n")
          out = out line
          started = 1
        }
        print out
        exit
      }
      print fm_strip_comment(val)
      exit
    }
  '
}

# Extract the value of an indented `metadata:` sub-key from stdin frontmatter
# text, e.g. the `upstream-version` in:
#   metadata:
#     upstream-version: 0.1.17
# `skill_frontmatter::field` anchors at column 0 and cannot see this — it's
# for top-level keys only. Prints nothing if the key is absent.
#
# The read is SCOPED to the `metadata:` block: collection starts at a column-0
# `metadata:` line and stops at the next column-0 key. Without that scope this
# matched the first indented `key:` line anywhere in the frontmatter, so an
# indented line inside a `description: |` block scalar was read as metadata
# while the cheat-sheet generator (which tracks the block) read the real value.
# Two readers disagreeing about WHICH value they are reading is a sharper
# failure than disagreeing about whether it is valid (#3189).
#
# Quotes are NOT stripped. The value is the literal text after the key, which is
# what the generator's reader takes and what the summary guard judges: a quoted
# scalar is a rejection there, not a value to unwrap. Stripping quotes here
# would hide exactly the malformed values this feeds.
#
# `key` is spliced into an awk regex uninterpreted — safe only for plain
# identifier-shaped keys (letters/digits/hyphen, e.g. `upstream-version`).
# A key containing awk regex metacharacters (`.`, `[`, `*`, ...) would silently
# mismatch, not error. All current call sites pass literal identifier keys.
#
# With `--raw` the trailing `#`-comment is LEFT IN PLACE. A guard that rejects
# " #" needs to see it: the generator treats a trailing comment on a swept key
# as an error rather than something to strip away, so a reader that strips it
# first can never reach the same verdict. Trailing whitespace is removed in both
# modes, matching the generator's trim.
skill_frontmatter::metadata_field() {
  local key="$1" mode="${2:-}" strip=1
  [[ "$mode" == "--raw" ]] && strip=0
  awk -v k="$key" -v strip="$strip" '
    /^metadata:[[:space:]]*$/ { inmeta = 1; next }
    /^[^[:space:]]/ { inmeta = 0 }
    inmeta && $0 ~ "^[[:space:]]+" k ":[[:space:]]*" {
      val = $0
      sub("^[[:space:]]+" k ":[[:space:]]*", "", val)
      if (strip) sub("[[:space:]]+#.*$", "", val)
      sub("[[:space:]]+$", "", val)
      print val
      exit
    }
  '
}

# Does the `metadata:` block carry `key` at all? Distinguishes an ABSENT key
# from one present with an empty value — `metadata_field` prints nothing for
# both, and the two have different verdicts (absent is fine, empty is not).
skill_frontmatter::has_metadata_field() {
  local key="$1"
  awk -v k="$key" '
    /^metadata:[[:space:]]*$/ { inmeta = 1; next }
    /^[^[:space:]]/ { inmeta = 0 }
    inmeta && $0 ~ "^[[:space:]]+" k ":([[:space:]]|$)" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  '
}

# Judge a `metadata.summary` value against the shared summary contract, printing
# one error message when it fails and nothing when it passes. Exit status
# mirrors that: 0 = valid, 1 = rejected.
#
# This restates the guard the cheat-sheet generator enforces
# (scripts/cheatsheet-config.mjs, summaryError). The two are separate statements
# of one contract by necessity, not by choice: that guard is repo-internal
# JavaScript and this library ships inside an installable plugin that runs with
# no Node and no repository scripts beside it. They are held together by a
# shared case table (summary-contract-cases.json) that both are run against, so
# a divergence between them fails a test instead of surfacing as a CI surprise
# two commits later.
#
# The contract is a FIXED POINT: the literal text after `summary:` must be what
# every reader recovers, whether it reads with a real YAML parser or a regex.
# Claude Code documents that malformed frontmatter loads a skill with EMPTY
# metadata, so a value a parser rejects costs the skill its whole frontmatter.
# Requiring a plain, unquoted, colon-free scalar is the largest subset a regex
# reader can recover exactly, which is why it is stricter than YAML alone needs.
#
# Deliberately NOT enumerated: values a YAML resolver reads as a non-string
# (`true`, `017`, `12:34`, `2026-08-23`). A denylist of resolver spellings only
# ever holds the ones someone was already burned by. The parity test's YAML
# oracle catches that whole class mechanically instead, along with the
# multi-line-scalar cases no single-line rule can reach.
skill_frontmatter::summary_error() {
  local s="$1" cap=100 len lead
  local unsafe_lead='[]{}>|*&!%@`"'"'"'#-,?'

  if [[ -z "$s" ]]; then
    printf 'empty summary'
    return 1
  fi

  # Unicode CODEPOINTS, not bytes, counted locale-independently: UTF-8 ->
  # UTF-32BE via iconv makes every codepoint exactly 4 bytes, so byte-count/4 is
  # the codepoint count on any host. A locale-pinned ${#var} silently degrades
  # to byte counting where the pinned locale does not exist, tightening the cap
  # for multi-byte summaries; hosts without iconv take that fallback knowingly.
  if command -v iconv >/dev/null 2>&1; then
    len=$(($(printf '%s' "$s" | iconv -f UTF-8 -t UTF-32BE | wc -c) / 4))
  else
    len="$(
      LC_ALL=C.UTF-8
      printf '%s' "${#s}"
    )"
  fi
  if ((len > cap)); then
    printf 'summary is %d codepoints (cap %d)' "$len" "$cap"
    return 1
  fi

  # Byte-literal patterns under LC_ALL=C: portable ERE, no GNU -P dependency.
  if LC_ALL=C grep -qE $'[\x01-\x1f\x7f]' <<<"$s"; then
    printf 'summary contains a tab or control character'
    return 1
  fi
  # C1 controls (U+0080-U+009F) and the Unicode line separators U+2028/U+2029.
  # A real YAML reader rejects the former outright and consumes the latter as
  # line breaks, and neither is visible in an editor or a diff.
  if LC_ALL=C grep -qE $'\xc2[\x80-\x9f]|\xe2\x80[\xa8\xa9]' <<<"$s"; then
    printf 'summary contains a C1 control or Unicode line separator'
    return 1
  fi

  lead="${s:0:1}"
  if [[ "$unsafe_lead" == *"$lead"* ]]; then
    # Naming the remedy matters here: quoting is what an author reaches for
    # first, and a leading quote is rejected by this very rule (#3189).
    printf "summary starts with the YAML-special character '%s' (reword to a plain unquoted scalar; quoting it is rejected too)" "$lead"
    return 1
  fi
  if [[ "$s" == "=" ]]; then
    # The backticks are literal in the diagnostic, not a command substitution.
    # shellcheck disable=SC2016
    printf 'summary is the YAML value-key special `=`'
    return 1
  fi
  if [[ "$s" == *": "* ]]; then
    printf 'summary contains ": " (YAML mapping indicator; reword to remove the colon, quoting it is rejected too)'
    return 1
  fi
  if [[ "$s" == *" #"* ]]; then
    printf 'summary contains " #" (YAML comment start)'
    return 1
  fi
  if [[ "$s" == *: || "$s" == *" " ]]; then
    printf 'summary ends with a colon or whitespace'
    return 1
  fi
  return 0
}

# Strip ONE outer quote layer — double OR single, not both.
skill_frontmatter::strip_quotes() {
  local s="$1"
  if [[ "$s" == '"'*'"' ]]; then
    s="${s#\"}"
    s="${s%\"}"
  elif [[ "$s" == "'"*"'" ]]; then
    s="${s#\'}"
    s="${s%\'}"
  fi
  printf '%s' "$s"
}

# Sorted-unique single-quoted trigger phrases in stdin text.
# Intra-word apostrophes (contractions like "can't") are stripped first —
# otherwise they read as quote delimiters and manufacture pseudo-phrases
# spanning unrelated prose, which the keyword-preservation gate can never
# reconcile across legitimate description edits.
skill_frontmatter::extract_triggers() {
  sed "s/\\([[:alpha:]]\\)'\\([[:alpha:]]\\)/\\1\\2/g" 2>/dev/null | grep -oE "'[^']+'" 2>/dev/null | sort -u
}
