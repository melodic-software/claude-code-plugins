# shellcheck shell=bash
# Shared pr-issue-linkage BODY VALIDATOR. Sourced (not executed) — the single
# in-repo transcription of the melodic-software/ci-workflows pr-issue-linkage
# validator's semantics, consumed by every hook that judges a PR body against
# that check:
#   - pr-body-linkage-gate.sh   (Bash surface: `gh pr create` / `gh pr edit`)
#   - pr-linkage-mcp-gate.sh    (MCP surface: GitHub MCP create/update PR)
#   - the marketplace repo's checked-in .claude/hooks/pr-linkage-mcp-gate.sh,
#     which sources this file from its own checkout
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

# The four contract sections the pinned ci-workflows reusable requires
# (melodic-software/ci-workflows pr-issue-linkage.yml @ v0.14.2). Stated once
# here so both hook surfaces, the blocked-message remedy, and the tests cannot
# drift from each other the way "Related only" drifted from the other three.
REQUIRED_SECTIONS=(Summary Fix Verification Related)

# Content of the first `## <heading>` section on stdout; returns 1 when there
# is no such heading, which is a different verdict from an empty one. Only a
# heading at the SAME level or higher (fewer or equal `#`) closes the section,
# so a nested `### …` subsection is content — a naive "next line starting with
# #" reading would call such a section empty.
#
# Trimming is spelled inline at both per-line sites rather than through `trim`:
# a command substitution forks, and one fork per body line put a 1000-line body
# past this hook's own declared timeout.
section_content() {
  local body="$1" heading_lc="${2,,}" line t start=0 lvl i=0 out=""
  local -a lines=()
  # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done < <(printf '%s\n' "$body")
  for ((i = 0; i < ${#lines[@]}; i++)); do
    t="${lines[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ "${t,,}" =~ ^##[[:space:]]+${heading_lc}$ ]] && {
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

# Mask fenced blocks, indented code, and inline spans the way the pinned
# ci-workflows reusable does before it searches for headings or keywords:
# a `## Fix` that exists only inside a fenced template, a four-space sample,
# or an inline span is not a real section. Fence close follows CommonMark
# (same delimiter character, at least as long, info string empty on close;
# a backtick fence's opener rejects an info string that itself contains a
# backtick). Masked lines become empty so line structure — and therefore
# heading-level section bounds — stays intact.
mask_markdown_code() {
  local body="$1" line rest rendered fence_char="" fence_len=0 in_fence=0
  local marker_run marker_rest i ticks len k o sidx nspans a b key last_end out=""
  local -a runs_pos runs_len spans_start spans_end order kept_start kept_end
  local -A pending
  while IFS= read -r line || [[ -n "$line" ]]; do
    rest="${line%$'\r'}"
    if ((in_fence)); then
      if [[ "$rest" =~ ^\ {0,3}(\`{3,}|~{3,})(.*)$ ]]; then
        marker_run="${BASH_REMATCH[1]}"
        marker_rest="${BASH_REMATCH[2]}"
        if [[ "${marker_run:0:1}" == "$fence_char" && ${#marker_run} -ge $fence_len && "$marker_rest" =~ ^[[:space:]]*$ ]]; then
          in_fence=0
          fence_char=""
          fence_len=0
        fi
      fi
      out+=$'\n'
      continue
    fi
    if [[ "$rest" =~ ^\ {0,3}(\`{3,}|~{3,})(.*)$ ]]; then
      marker_run="${BASH_REMATCH[1]}"
      marker_rest="${BASH_REMATCH[2]}"
      if [[ "${marker_run:0:1}" != '`' || "$marker_rest" != *'`'* ]]; then
        in_fence=1
        fence_char="${marker_run:0:1}"
        fence_len=${#marker_run}
        out+=$'\n'
        continue
      fi
    fi
    if [[ "$rest" =~ ^(\ {4}|\t) ]]; then
      out+=$'\n'
      continue
    fi
    # Collect backtick runs in one left-to-right pass, then pair each opener
    # with the next unused same-length run. A per-opener rescan of the
    # remainder is O(L^1.5) on a line of distinct run lengths and can exceed
    # the 15s PreToolUse timeout, which fails this gate open.
    runs_pos=()
    runs_len=()
    i=0
    len=${#rest}
    while ((i < len)); do
      if [[ "${rest:i:1}" == '`' ]]; then
        ticks=1
        while ((i + ticks < len)) && [[ "${rest:i+ticks:1}" == '`' ]]; do ((ticks++)); done
        runs_pos+=("$i")
        runs_len+=("$ticks")
        i=$((i + ticks))
      else
        ((i++))
      fi
    done
    pending=()
    spans_start=()
    spans_end=()
    for ((k = 0; k < ${#runs_pos[@]}; k++)); do
      ticks=${runs_len[k]}
      if [[ -n "${pending[$ticks]+x}" ]]; then
        o=${pending[$ticks]}
        unset 'pending[$ticks]'
        spans_start+=("${runs_pos[o]}")
        spans_end+=($((runs_pos[k] + runs_len[k])))
      else
        pending[$ticks]=$k
      fi
    done
    # Pairing completes in closer-first order. Nested differing-length
    # runs (`` `x` ``) therefore land the inner span first; a monotonic
    # render walk then orphans the outer span and leaks its gap text
    # (including a decoy "closes #N") into has_linkage(). Sort by start
    # and keep outermost only so the walk matches CommonMark: the first
    # opener consumes through its closer, and inner runs stay content.
    nspans=${#spans_start[@]}
    if ((nspans > 1)); then
      order=()
      for ((k = 0; k < nspans; k++)); do order+=("$k"); done
      for ((a = 1; a < nspans; a++)); do
        key=${order[a]}
        b=$((a - 1))
        while ((b >= 0 && spans_start[order[b]] > spans_start[key])); do
          order[b + 1]=${order[b]}
          ((b--))
        done
        order[b + 1]=$key
      done
      kept_start=()
      kept_end=()
      last_end=-1
      for k in "${order[@]}"; do
        if ((spans_start[k] >= last_end)); then
          kept_start+=("${spans_start[k]}")
          kept_end+=("${spans_end[k]}")
          last_end=${spans_end[k]}
        fi
      done
      spans_start=("${kept_start[@]}")
      spans_end=("${kept_end[@]}")
    fi
    rendered=""
    i=0
    sidx=0
    nspans=${#spans_start[@]}
    while ((i < len)); do
      if ((sidx < nspans && i == spans_start[sidx])); then
        i=${spans_end[sidx]}
        ((sidx++))
        continue
      fi
      rendered+="${rest:i:1}"
      ((i++))
    done
    out+="$rendered"$'\n'
  done < <(printf '%s\n' "$body")
  printf '%s' "$out"
}

# Aggregate verdict: strip comments, mask Markdown code (CI does both before
# any heading or keyword scan), then the closing-keyword half plus every
# required section. Fills the global LINKAGE_PROBLEMS array with one line per
# problem so the author sees the full set in one pass; returns 0 when the body
# passes (array empty), 1 otherwise. The consuming hook owns what a failure
# DOES — block message, telemetry, exit code.
LINKAGE_PROBLEMS=()
linkage::problems() {
  local body heading content
  body=$(strip_html_comments "$1")
  body=$(mask_markdown_code "$body")
  LINKAGE_PROBLEMS=()
  for heading in "${REQUIRED_SECTIONS[@]}"; do
    # shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
    if content=$(section_content "$body" "$heading"); then
      [[ -n "$content" ]] || LINKAGE_PROBLEMS+=("The \"## ${heading}\" section is empty.")
    else
      LINKAGE_PROBLEMS+=("Missing a \"## ${heading}\" section.")
    fi
  done
  has_linkage "$body" ||
    LINKAGE_PROBLEMS+=('Missing a native closing keyword (Closes/Fixes/Resolves #N) and no "No linked issue" marker.')
  ((${#LINKAGE_PROBLEMS[@]} == 0))
}
