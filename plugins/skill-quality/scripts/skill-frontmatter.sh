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
# scalar (`key: |` / `key: >`, with optional chomp/indent indicator) is unfolded
# to its text so downstream length / trigger / phrasing checks see the content
# rather than the `|` / `>` marker: literal (`|`) joins lines with newlines,
# folded (`>`) with spaces.
skill_frontmatter::field() {
  local key="$1"
  awk -v k="$key" '
    $0 ~ "^" k ":[[:space:]]*" {
      val = $0
      sub("^" k ":[[:space:]]*", "", val)
      if (val ~ /^[|>][0-9]*[+-]?[[:space:]]*$/) {
        fold = (val ~ /^>/)
        out = ""; started = 0; base = -1
        while ((getline line) > 0) {
          if (line ~ /^[[:space:]]*$/) { if (started) out = out (fold ? " " : "\n"); continue }
          match(line, /^[[:space:]]*/); ind = RLENGTH
          if (base < 0) base = ind
          if (ind < base) break
          if (started) out = out (fold ? " " : "\n")
          out = out substr(line, base + 1)
          started = 1
        }
        print out
        exit
      }
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
