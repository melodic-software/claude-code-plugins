# shellcheck shell=bash
# Shared pr-issue-linkage BODY VALIDATOR. Sourced (not executed) — the single
# in-repo transcription of the melodic-software/ci-workflows pr-issue-linkage
# validator's semantics, consumed by every hook that judges a PR body against
# that check:
#   - pr-body-linkage-gate.sh   (Bash surface: `gh pr create` / `gh pr edit`)
#   - pr-linkage-mcp-gate.sh    (MCP surface: GitHub MCP create/update PR)
# A drift fix against the upstream validator lands here once and reaches every
# surface atomically; per-surface extraction, scope guards, and block messages
# stay in the consuming hooks.
#
# CONTRACT — callers pin `export LC_ALL=C` BEFORE sourcing: the character
# classes below are locale-dependent and the whole point of the
# UNICODE_SPACES normalization is a locale-independent verdict. See the LOCALE
# note in either consuming hook.
#
# Function names are kept exactly as they were when these lived inline in
# pr-body-linkage-gate.sh (unprefixed), so its annotated history still reads;
# only the aggregate verdict added with the extraction is namespaced.

# Guard against double-sourcing.
[[ -n "${_PR_LINKAGE_VALIDATOR_LOADED:-}" ]] && return 0
readonly _PR_LINKAGE_VALIDATOR_LOADED=1

# Every character JavaScript's `\s` matches beyond the six ASCII ones, as its
# literal UTF-8 bytes. Spelled as bytes rather than `\uXXXX` because bash
# renders `\u` through the ambient charmap, which is the very dependency the
# LOCALE note removes. NBSP in particular arrives routinely in text pasted from
# an issue title.
UNICODE_SPACES=(
  $'\xc2\xa0' $'\xe1\x9a\x80'
  $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83'
  $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87'
  $'\xe2\x80\x88' $'\xe2\x80\x89' $'\xe2\x80\x8a'
  $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\xe2\x80\xaf'
  $'\xe2\x81\x9f' $'\xe3\x80\x80' $'\xef\xbb\xbf'
)

# Remove HTML comments the way the validator does — every terminated `<!-- … -->`
# span, then an unterminated `<!--` taking everything after it. Both strips are
# one left-to-right pass with a carried in-comment state, which produces exactly
# that result: once a `<!--` has no `-->`, the state never clears again.
# GitHub's own closing-keyword parser and its Markdown renderer both ignore
# commented-out text, so an unedited PR template — whose instructional prose
# names the very markers this gate looks for — must not pass vacuously.
# Unicode-space normalization rides along on the same pass; the delimiters are
# ASCII, so neither step can disturb the other.
strip_html_comments() {
  local body="$1" line rest kept out="" in_comment=0 sp
  for sp in "${UNICODE_SPACES[@]}"; do body="${body//"$sp"/ }"; done
  while IFS= read -r line || [[ -n "$line" ]]; do
    rest="${line%$'\r'}"
    kept=""
    while [[ -n "$rest" ]]; do
      if ((in_comment)); then
        if [[ "$rest" == *"-->"* ]]; then
          rest="${rest#*-->}"
          in_comment=0
        else
          rest=""
        fi
      else
        if [[ "$rest" == *"<!--"* ]]; then
          kept+="${rest%%<!--*}"
          rest="${rest#*<!--}"
          in_comment=1
        else
          kept+="$rest"
          rest=""
        fi
      fi
    done
    out+="$kept"$'\n'
  done < <(printf '%s\n' "$body") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  printf '%s' "$out"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# The validator's regexes, transcribed to POSIX ERE. JavaScript's `\b` has no
# ERE equivalent, so the probe is wrapped in newlines and the boundary is spelled
# as an explicit non-word character on each side — `#12abc` and `unclosed #5`
# stay non-matches, exactly as `\b` makes them. Matched against a lower-cased
# probe in place of the `i` flag.
KEYWORD_ERE='[^a-z0-9_](close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]*:?[[:space:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[^a-z0-9_]'
NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'

has_linkage() {
  local probe
  probe=$'\n'"${1,,}"$'\n'
  [[ "$probe" =~ $KEYWORD_ERE || "$probe" =~ $NO_ISSUE_ERE ]]
}

# Content of the first `## Related` section on stdout; returns 1 when there is
# no such heading, which is a different verdict from an empty one. Only a
# heading at the SAME level or higher (fewer or equal `#`) closes the section,
# so a nested `### …` subsection is content — a naive "next line starting with
# #" reading would call such a section empty.
#
# Trimming is spelled inline at both per-line sites rather than through `trim`:
# a command substitution forks, and one fork per body line put a 1000-line body
# past this hook's own declared timeout.
related_section() {
  local body="$1" line t start=0 lvl i=0 out=""
  local -a lines=()
  # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done < <(printf '%s\n' "$body")
  for ((i = 0; i < ${#lines[@]}; i++)); do
    t="${lines[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ "${t,,}" =~ ^##[[:space:]]+related$ ]] && {
      start=$((i + 1))
      break
    }
  done
  ((start)) || return 1
  for ((i = start; i < ${#lines[@]}; i++)); do
    t="${lines[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    if [[ "$t" =~ ^#+[[:space:]]+[^[:space:]] ]]; then
      lvl=0
      while [[ "${t:lvl:1}" == "#" ]]; do ((lvl++)); done
      ((lvl <= 2)) && break
    fi
    out+="${lines[i]}"$'\n'
  done
  trim "$out"
}

# Aggregate verdict: strip comments, judge both halves. Fills the global
# LINKAGE_PROBLEMS array with one line per missing half; returns 0 when the
# body passes (array empty), 1 otherwise. The consuming hook owns what a
# failure DOES — block message, telemetry, exit code.
LINKAGE_PROBLEMS=()
linkage::problems() {
  local body related
  body=$(strip_html_comments "$1")
  LINKAGE_PROBLEMS=()
  # shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
  if related=$(related_section "$body"); then
    [[ -n "$related" ]] || LINKAGE_PROBLEMS+=('The "## Related" section is empty.')
  else
    LINKAGE_PROBLEMS+=('Missing a "## Related" section.')
  fi
  has_linkage "$body" ||
    LINKAGE_PROBLEMS+=('Missing a native closing keyword (Closes/Fixes/Resolves #N) and no "No linked issue" marker.')
  ((${#LINKAGE_PROBLEMS[@]} == 0))
}
