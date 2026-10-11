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
# only the aggregate verdict added with the extraction is namespaced. The `_to`
# suffix each helper now carries is the one deliberate departure — see PROCESS
# BUDGET below for why the stdout form had to go.
#
# PROCESS BUDGET (#3509) — every helper here writes into a caller-named variable
# instead of onto stdout. GNU Bash forks a subshell for `$(f)` even when `f` is
# pure builtins, and forks a second for `< <(printf …)`. Measured with
# `strace -f -e trace=clone,clone3,fork,vfork,execve`, the stdout form of these
# four helpers cost `linkage::problems` 12 forks per judged body and zero extra
# `execve` — pure process-creation latency, which is the whole cost on the host
# that filed #3509 (0.3-0.9 s per spawn there, against ~3-5 ms here). `printf -v`
# and an in-shell line split cost neither a fork nor an exec. The
# `local __plv_dest="$1"` shape follows hook-utils.sh's own out-variable
# convention and stays Bash 3.2-safe (no namerefs).
#
# TRAILING-NEWLINE CONTRACT — `$(f)` strips EVERY trailing newline from what `f`
# printed, so a `_to` helper must strip them itself to stay verdict-identical to
# the stdout form it replaced. `linkage::chomp_to` is that strip, spelled once;
# `section_content_to` needs none, because trimming already removes trailing
# whitespace.
#
# DEST-NAME CONTRACT — `printf -v "$dest"` writes the helper's OWN local when
# <dest> happens to name one (bash resolves the name in the callee's scope), so
# the caller silently gets nothing back. Every caller here is `linkage::problems`
# in this same file, and its four destinations carry a `_plv_` prefix that no
# helper local uses; the differential test asserts that no `_to` helper declares
# a local matching a destination name, so a future rename cannot reintroduce the
# shadow quietly.

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

# Trailing newlines removed, exactly as command substitution removed them.
linkage::chomp_to() {
  local __plv_dest="$1" __plv_s="$2"
  while [[ "$__plv_s" == *$'\n' ]]; do __plv_s="${__plv_s%$'\n'}"; done
  printf -v "$__plv_dest" '%s' "$__plv_s"
}

# `readarray` splits in C without a fork; `${rest#*$'\n'}` copies every
# surviving byte each line, so 16k two-character lines exceeded the 15s
# hooks.json timeout, and a per-char offset walk is linear in copies but still
# too many bash iterations.
#
# A here-string feeds `readarray` with no fork and no file this process must
# remove, but a here-string of >=64KiB deadlocks on bash builds that write it
# to a pipe in-process (see hardcoded-path-patterns.sh). Text shorter than
# _PR_LINKAGE_HERESTRING_MAX characters stays under 64000 bytes even at four
# bytes a character, so it takes the here-string. Longer text goes through a
# scratch file removed right after the read: one `rm` per call, and only for
# bodies far larger than any compliant PR body.
# umask 077 at load so the scratch body is never world-readable in TMPDIR;
# capturing umask to restore it would be a command substitution, which is a fork.
umask 077
_PR_LINKAGE_HERESTRING_MAX=16000

# Split <text> into the LINKAGE_LINES array, element-for-element as
# `while IFS= read -r line || [[ -n "$line" ]]; … done < <(printf '%s\n' "$text")`
# did: `printf '%s\n'` terminates the last line, so the element count is always
# one more than the number of newlines in <text>, and an empty <text> yields one
# empty element. No process substitution, so no fork.
linkage::split_lines() {
  if ((${#1} < _PR_LINKAGE_HERESTRING_MAX)); then
    readarray -t LINKAGE_LINES <<<"$1"
    return 0
  fi
  local __plv_file="${TMPDIR:-/tmp}/pr-linkage-lines.$$"
  printf '%s\n' "$1" >"$__plv_file"
  readarray -t LINKAGE_LINES <"$__plv_file"
  rm -f "$__plv_file"
}

# Remove HTML comments the way the validator does — every terminated `<!-- … -->`
# span, then an unterminated `<!--` taking everything after it. Both strips are
# one left-to-right pass with a carried in-comment state, which produces exactly
# that result: once a `<!--` has no `-->`, the state never clears again.
# GitHub's own closing-keyword parser and its Markdown renderer both ignore
# commented-out text, so an unedited PR template — whose instructional prose
# names the very markers this gate looks for — must not pass vacuously.
# Unicode-space normalization rides along on the same pass; the delimiters are
# ASCII, so neither step can disturb the other.
strip_html_comments_to() {
  local __plv_dest="$1" body="$2" line rest kept out="" in_comment=0 sp i=0
  for sp in "${UNICODE_SPACES[@]}"; do body="${body//"$sp"/ }"; done
  linkage::split_lines "$body"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    line="${LINKAGE_LINES[i]}"
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
  done
  linkage::chomp_to "$__plv_dest" "$out"
}

trim_to() {
  local __plv_dest="$1" s="$2"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf -v "$__plv_dest" '%s' "$s"
}

# The pr-contract analyzer's linkage patterns (`scan_line` and the `no-issue`
# test in ci-workflows .github/actions/pr-contract/run.sh), transcribed to POSIX
# ERE and matched against lower-cased text in place of `tolower`. The closing
# keyword and the non-closing marker are matched one line at a time, as CI
# does; the no-issue phrase is matched over the whole body, wrapped in newlines
# so the explicit non-word boundary also holds at either end.
CLOSING_ERE='(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:blank:]]*:?[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+'
NON_CLOSING_ERE='^ {0,3}(refs|relates[[:blank:]]+to):[[:blank:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[[:blank:]]*$'
NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'
# A tracker's link line, which `/work-items:track link` prints from the bound
# adapter (work-items CONTRACT.md "Change links"): a linking keyword, then an
# issue key (`Closes ENG-123`, `Refs SW2-12`) or a qualified item id
# (`Refs: local-markdown:local/markdown#7`), alone on its line. Matched against
# the original-case line, so a key stays upper-case and `fixes utf-8` is not
# one; the keyword is checked lower-cased against TRACKER_KEYWORD_ERE. The
# second keyword word is spelled `to` rather than any word: POSIX
# leftmost-longest submatching would otherwise read `Closes ENG-123` as the
# keyword `Closes EN` and the key `G-123`. This
# goes beyond the CI analyzer, which knows only GitHub's `#N`; there the body
# contract is advisory, and blocking an adapter's own link would leave a
# non-GitHub tracker no way to open a pull request through this gate.
TRACKER_LINK_ERE='^ {0,3}([A-Za-z]+([[:blank:]]+[Tt][Oo])?)([[:blank:]]*:[[:blank:]]*|[[:blank:]]+)([A-Z][A-Z0-9_]*-[0-9]+|[a-z][a-z0-9-]*:[^[:space:]#]+#[0-9]+)[[:blank:]]*$'
TRACKER_KEYWORD_ERE='^(close[sd]?|fix(es|ed)?|resolve[sd]?|refs|relates[[:blank:]]+to)$'
_PLV_WORD_ERE="[A-Za-z][A-Za-z']*"

# CI's `negation_trigger`: the first disclaimer word among the last five words
# between the previous `.!?;,` and the keyword, into <dest>; empty when there is
# none. A typographic apostrophe (U+2019) counts as a straight one, and "not
# only" is affirmative.
negation_trigger_to() {
  local __plv_dest="$1" tail="${2##*[.!?;,]}" lower n first i
  local -a words=()
  printf -v "$__plv_dest" '%s' ""
  tail="${tail//$'\xe2\x80\x99'/\'}"
  while [[ "$tail" =~ $_PLV_WORD_ERE ]]; do
    words+=("${BASH_REMATCH[0]}")
    tail="${tail#*"${BASH_REMATCH[0]}"}"
  done
  n=${#words[@]}
  first=0
  ((n > 5)) && first=$((n - 5))
  for ((i = first; i < n; i++)); do
    lower="${words[i],,}"
    [[ "$lower" == not ]] && ((i + 1 < n)) && [[ "${words[i + 1],,}" == only ]] && continue
    case "$lower" in
    not | never | no | without | deliberately | intentionally | *"n't")
      printf -v "$__plv_dest" '%s' "${words[i]}"
      return 0
      ;;
    *) ;;
    esac
  done
}

# Scan the masked body for linkage. Returns 0 when it carries an un-negated
# closing keyword, a non-closing `Refs:` / `Relates to:` marker on its own line,
# a tracker link line, or a no-issue opt-out. Fills LINKAGE_NEGATED with one `"<text>" (trigger
# "<word>")` entry per distinct negated closing reference, in first-seen order.
# A negated closer never counts as linkage, and CI fails it even when valid
# linkage exists elsewhere, because GitHub's parser still closes the issue.
LINKAGE_NEGATED=()
scan_linkage() {
  local line lower chunk m pre start len off before after text _plv_trigger i found=1
  local -A negated_seen=()
  LINKAGE_NEGATED=()
  linkage::split_lines "$1"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    line="${LINKAGE_LINES[i]}"
    lower="${line,,}"
    [[ "$lower" =~ $NON_CLOSING_ERE ]] && found=0
    [[ "$line" =~ $TRACKER_LINK_ERE && "${BASH_REMATCH[1],,}" =~ $TRACKER_KEYWORD_ERE ]] && found=0
    off=0
    while chunk="${lower:off}" && [[ "$chunk" =~ $CLOSING_ERE ]]; do
      m="${BASH_REMATCH[0]}"
      # The leftmost match is also the first occurrence of its own text.
      pre="${chunk%%"$m"*}"
      start=$((off + ${#pre}))
      len=${#m}
      off=$((start + len))
      before=""
      ((start > 0)) && before="${lower:start-1:1}"
      after="${lower:off:1}"
      [[ "$before" == [a-z0-9_] || "$after" == [a-z0-9_] ]] && continue
      text="${line:start:len}"
      negation_trigger_to _plv_trigger "${line:0:start}"
      if [[ -z "$_plv_trigger" ]]; then
        found=0
        continue
      fi
      [[ -n "${negated_seen[$text]:-}" ]] && continue
      negated_seen[$text]=1
      LINKAGE_NEGATED+=("\"${text}\" (trigger \"${_plv_trigger}\")")
    done
  done
  ((found == 0)) && return 0
  lower=$'\n'"${1,,}"$'\n'
  [[ "$lower" =~ $NO_ISSUE_ERE ]]
}

# The four contract sections the pinned ci-workflows reusable requires
# (melodic-software/ci-workflows pr-issue-linkage.yml @ v0.14.2). Stated once
# here so both hook surfaces, the blocked-message remedy, and the tests cannot
# drift from each other the way "Related only" drifted from the other three.
REQUIRED_SECTIONS=(Summary Fix Verification Related)

# Content of the first `## <heading>` section into <dest>; returns 1 when there
# is no such heading, which is a different verdict from an empty one. Only a
# heading at the SAME level or higher (fewer or equal `#`) closes the section,
# so a nested `### …` subsection is content — a naive "next line starting with
# #" reading would call such a section empty.
#
# Trimming is spelled inline at both per-line sites rather than through
# `trim_to`: even a function CALL was cheap, but the stdout `trim` it replaced
# forked, and one fork per body line put a 1000-line body past this hook's own
# declared timeout. The inline form is kept so that cannot regress.
#
# <dest> is cleared before the heading search, so the not-found return leaves it
# empty rather than holding whatever the caller had there.
section_content_to() {
  local __plv_dest="$1" body="$2" heading_lc="${3,,}" t start=0 lvl i=0 out=""
  printf -v "$__plv_dest" '%s' ""
  linkage::split_lines "$body"
  for ((i = 0; i < ${#LINKAGE_LINES[@]}; i++)); do
    t="${LINKAGE_LINES[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    # Quoted: a configured heading such as `What changed?` matches as text.
    [[ "${t,,}" =~ ^##[[:space:]]+"${heading_lc}"$ ]] && {
      start=$((i + 1))
      break
    }
  done
  ((start)) || return 1
  for ((i = start; i < ${#LINKAGE_LINES[@]}; i++)); do
    t="${LINKAGE_LINES[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    if [[ "$t" =~ ^#+[[:space:]]+[^[:space:]] ]]; then
      lvl=0
      while [[ "${t:lvl:1}" == "#" ]]; do ((lvl++)); done
      ((lvl <= 2)) && break
    fi
    out+="${LINKAGE_LINES[i]}"$'\n'
  done
  trim_to "$__plv_dest" "$out"
}

# Mask fenced blocks, indented code, and inline spans the way the pinned
# ci-workflows reusable does before it searches for headings or keywords:
# a `## Fix` that exists only inside a fenced template, a four-space sample,
# or an inline span is not a real section. Fence close follows CommonMark
# (same delimiter character, at least as long, info string empty on close;
# a backtick fence's opener rejects an info string that itself contains a
# backtick). Masked lines become empty so line structure — and therefore
# heading-level section bounds — stays intact.
mask_markdown_code_to() {
  local __plv_dest="$1" body="$2" line rest rendered fence_char="" fence_len=0 in_fence=0
  local marker_run marker_rest i ticks len k m j sidx nspans nruns cs ce out="" li=0
  local -a runs_pos runs_len spans_start spans_end used
  # Up to three leading spaces, then the fence run, then the info string.
  local fence_re='^ {0,3}(`{3,}|~{3,})(.*)$'
  linkage::split_lines "$body"
  for ((li = 0; li < ${#LINKAGE_LINES[@]}; li++)); do
    line="${LINKAGE_LINES[li]}"
    rest="${line%$'\r'}"
    if ((in_fence)); then
      if [[ "$rest" =~ $fence_re ]]; then
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
    if [[ "$rest" =~ $fence_re ]]; then
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
    # A glob, not `=~ ^(\ {4}|\t)`: in a bash regex `\t` is a literal `t`.
    if [[ "$rest" == "    "* || "$rest" == $'\t'* ]]; then
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
    # CommonMark: leftmost opener consumes through the next same-length
    # run; everything between is content (nested pairs, the escaped-tick
    # idiom, leftover pending of another length). Walk openers in order
    # and mark absorbed runs used so they cannot steal a later pair.
    nruns=${#runs_pos[@]}
    used=()
    for ((k = 0; k < nruns; k++)); do used[k]=0; done
    spans_start=()
    spans_end=()
    for ((k = 0; k < nruns; k++)); do
      ((used[k])) && continue
      ticks=${runs_len[k]}
      j=-1
      for ((m = k + 1; m < nruns; m++)); do
        if ((used[m] == 0 && runs_len[m] == ticks)); then
          j=$m
          break
        fi
      done
      ((j < 0)) && continue
      used[k]=1
      used[j]=1
      for ((m = k + 1; m < j; m++)); do
        used[m]=1
      done
      cs=${runs_pos[k]}
      ce=$((runs_pos[j] + runs_len[j]))
      spans_start+=("$cs")
      spans_end+=("$ce")
    done
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
  done
  linkage::chomp_to "$__plv_dest" "$out"
}

# Section half of the verdict: append one LINKAGE_PROBLEMS line per <heading>
# that is missing or empty in <body>, which must already be comment-stripped
# and code-masked. Shared by linkage::problems and the pull-request skill's
# pre-create check, which passes its own configured headings.
linkage::section_problems() {
  local _plv_content="" _plv_masked="$1" heading
  shift
  for heading in "$@"; do
    # shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
    if section_content_to _plv_content "$_plv_masked" "$heading"; then
      [[ -n "$_plv_content" ]] || LINKAGE_PROBLEMS+=("The \"## ${heading}\" section is empty.")
    else
      LINKAGE_PROBLEMS+=("Missing a \"## ${heading}\" section.")
    fi
  done
}

# Aggregate verdict: strip comments, mask Markdown code (CI does both before
# any heading or keyword scan), then every required section plus the linkage
# half: a negated closing reference, and missing linkage. Fills the global LINKAGE_PROBLEMS array with one line per
# problem so the author sees the full set in one pass; returns 0 when the body
# passes (array empty), 1 otherwise. The consuming hook owns what a failure
# DOES — block message, telemetry, exit code.
LINKAGE_PROBLEMS=()
linkage::problems() {
  # `_plv_`-prefixed per the DEST-NAME CONTRACT above: an out-variable named
  # `body`, `out`, or `line` would be captured by the callee's own local.
  local _plv_stripped="" _plv_body=""
  local _plv_linked=0 _plv_negated=""
  strip_html_comments_to _plv_stripped "$1"
  mask_markdown_code_to _plv_body "$_plv_stripped"
  LINKAGE_PROBLEMS=()
  linkage::section_problems "$_plv_body" "${REQUIRED_SECTIONS[@]}"
  # shellcheck disable=SC2310  # the exit IS the verdict: linkage present or not
  scan_linkage "$_plv_body" || _plv_linked=1
  ((${#LINKAGE_NEGATED[@]} == 0)) || {
    printf -v _plv_negated '%s, ' "${LINKAGE_NEGATED[@]}"
    LINKAGE_PROBLEMS+=("Negated closing reference (${_plv_negated%, }): GitHub still auto-closes the issue on merge. Use \"Refs: #N\" on its own line instead.")
  }
  ((_plv_linked == 0)) ||
    LINKAGE_PROBLEMS+=('No closing line: add Closes #N, Refs: #N (link without closing), or No linked issue.')
  ((${#LINKAGE_PROBLEMS[@]} == 0))
}

# linkage::block_message <gate-path>: the PreToolUse block text for the current
# LINKAGE_PROBLEMS, to stderr. One printer for both gates so the text cannot
# drift between the Bash and MCP surfaces. The closing sentence names the
# required shape for a repository with no PR-body rule of its own.
linkage::block_message() {
  local p
  echo "BLOCKED: PR body fails the pr-contract step in $1." >&2
  for p in "${LINKAGE_PROBLEMS[@]}"; do echo "  - $p" >&2; done
  echo "The body needs a closing line (Closes #N, Refs: #N, the bound tracker's link line from /work-items:track link, or No linked issue) and non-empty ## Summary, ## Fix, ## Verification and ## Related sections." >&2
}
