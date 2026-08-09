# shellcheck shell=bash
# Shared SKILL.md frontmatter helpers for skill gates.
# Source from check-skill.sh, skill-contract-check.sh, and future skill validators.

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

# Extract the value of an indented `metadata:` sub-key (quotes stripped) from
# stdin frontmatter text, e.g. the `upstream-version` in:
#   metadata:
#     upstream-version: 0.1.17
# `skill_frontmatter::field` anchors at column 0 and cannot see this — it's
# for top-level keys only. Prints nothing if the key is absent.
#
# `key` is spliced into an awk regex uninterpreted — safe only for plain
# identifier-shaped keys (letters/digits/hyphen, e.g. `upstream-version`).
# A key containing awk regex metacharacters (`.`, `[`, `*`, ...) would silently
# mismatch, not error. All current call sites pass literal identifier keys.
skill_frontmatter::metadata_field() {
  local key="$1"
  awk -v k="$key" '
    $0 ~ "^[[:space:]]+" k ":[[:space:]]*" {
      val = $0
      sub("^[[:space:]]+" k ":[[:space:]]*", "", val)
      sub("[[:space:]]+#.*$", "", val)
      print val
      exit
    }
  '
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
