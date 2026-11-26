# shellcheck shell=bash

if [[ -n "${SKILL_FRONTMATTER_LIB_LOADED:-}" ]]; then
  # shellcheck disable=SC2317  # reachable via source (return) or direct exec (exit); standalone lint can't see the sourced context
  return 0 2>/dev/null || exit 0
fi
SKILL_FRONTMATTER_LIB_LOADED=1

skill_frontmatter::extract() {
  awk '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    /^---[[:space:]]*$/ { if (++fence == 1) next; exit }
    fence == 1 { print }
  '
}

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

skill_frontmatter::metadata_field() {
  local key="$1" strip=1
  [[ "${2:-}" == "--raw" ]] && strip=0
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

skill_frontmatter::has_metadata_field() {
  local key="$1"
  awk -v k="$key" '
    /^metadata:[[:space:]]*$/ { inmeta = 1; next }
    /^[^[:space:]]/ { inmeta = 0 }
    inmeta && $0 ~ "^[[:space:]]+" k ":([[:space:]]|$)" { found = 1; exit }
    END { exit(found ? 0 : 1) }
  '
}

skill_frontmatter::codepoint_len() {
  local bytes
  if command -v iconv >/dev/null 2>&1; then
    bytes=$(printf '%s' "$1" | iconv -f UTF-8 -t UTF-32BE | wc -c)
    printf '%s' "$((bytes / 4))"
  else
    (
      LC_ALL=C.UTF-8
      printf '%s' "${#1}"
    )
  fi
}

skill_frontmatter::summary_error() {
  local s="$1" cap=100 len lead
  local unsafe_lead='[]{}>|*&!%@`"'"'"'#-,?'

  if [[ -z "$s" ]]; then
    printf 'empty summary'
    return 1
  fi

  len="$(skill_frontmatter::codepoint_len "$s")"
  if ((len > cap)); then
    printf 'summary is %d codepoints (cap %d)' "$len" "$cap"
    return 1
  fi

  if LC_ALL=C grep -qE $'[\x01-\x1f\x7f]' <<<"$s"; then
    printf 'summary contains a tab or control character'
    return 1
  fi
  if LC_ALL=C grep -qE $'\xc2[\x80-\x9f]|\xe2\x80[\xa8\xa9]' <<<"$s"; then
    printf 'summary contains a C1 control or Unicode line separator'
    return 1
  fi

  lead="${s:0:1}"
  if [[ "$unsafe_lead" == *"$lead"* ]]; then
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

skill_frontmatter::extract_triggers() {
  sed "s/\\([[:alpha:]]\\)'\\([[:alpha:]]\\)/\\1\\2/g" 2>/dev/null | grep -oE "'[^']+'" 2>/dev/null | sort -u
}
