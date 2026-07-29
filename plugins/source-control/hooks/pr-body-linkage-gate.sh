#!/usr/bin/env bash
# PreToolUse hook: block a bare `gh pr create` / `gh pr edit` whose PR BODY
# would fail the consuming repository's own `pr-issue-linkage` CI gate.
#
# WHY IT EXISTS — the gate is a REQUIRED check, so a body missing either half
# blocks the merge; but nothing enforced the contract at authoring time, so the
# failure was only ever discovered post-hoc, one CI round trip after the PR was
# already open. `/source-control:pull-request create` runs the equivalent
# pre-create gate (skills/pull-request/reference/create.md §2.4.2); this hook
# covers the calls that never go through the skill.
#
# WHAT IT ENFORCES — the two halves the reusable
# melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml validator
# requires, mirrored: after stripping HTML comments (terminated ones, then an
# unterminated `<!--` swallowing the rest — both, in that order, exactly as the
# validator does), the body must carry
#   (a) a native closing keyword (`Closes/Fixes/Resolves #N`, including
#       `owner/repo#N`) OR the literal `No linked issue` / `No related issue:`;
#   (b) a `## Related` section that is present AND non-empty, where a DEEPER
#       heading (`### …`) is that section's content, not its terminator.
#
# SCOPE GUARD — enforcement is keyed to the repository's OWN policy: the gate
# runs only when the repo root carries `.github/workflows/pr-issue-linkage.yml`
# (or `.yaml`). A repo that does not run the check is never gated, so the hook
# cannot drift away from what its consumer actually enforces. This is
# deliberately NOT the `pr_body_required_sections` seam
# (docs/conventions/pr-body-convention/): that key is the repo's configurable
# section scaffold, whose portable default excludes `Related` on purpose. The
# authority for THIS gate is the workflow file that defines it.
#
# WHICH DIRECTORY — the gate file and any relative `--body-file` resolve against
# the payload's `cwd`. A `cd`/`pushd`/`popd` earlier in the same command line
# moves the directory `gh` actually runs in, and the segment tokenizer discards
# that segment, so neither resolution would be knowable: the call goes OUT OF
# SCOPE from that point on, exactly as a `--repo`-targeted one does.
#
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE BAD BODY. The body is
# only judged when it can be read statically: a `--body`/`-b` literal, a
# `--body-file`/`-F <path>` that exists, or the sole heredoc when the command
# feeds stdin (`--body-file -`) or wraps one in a command substitution
# (`--body "$(cat <<'EOF' … EOF)"`). A value carrying an unexpanded `$` or
# backtick with no heredoc to resolve it, a body flag with no following word (a
# command `gh` itself rejects), an absent body flag (`--fill`, `--template`,
# `--editor`, `--web`, the interactive prompt), or an unreadable body file all
# ALLOW: guessing at a body this hook cannot see would block compliant calls.
# A stalled or unreadable hook payload allows too — unlike the sibling SECURITY
# guards, refusing an arbitrary Bash command because this POLICY gate could not
# read its own stdin is a worse failure than missing one body check.
#
# LOCALE — `[[:space:]]` stands in for JavaScript's `\s`, but its membership is
# locale-defined while `\s` is a fixed set, so the same body could be judged
# differently depending on ambient environment. Both halves are pinned instead:
# every non-ASCII character in the `\s` set is rewritten to a plain space by
# byte sequence (locale-independent), and matching then runs under `LC_ALL=C`,
# where `[[:space:]]` is exactly the six ASCII whitespace characters. The two
# together reproduce `\s` on any host.
#
# DECLARED BYPASS COVERAGE (out of scope, documented): the PowerShell tool —
# the Bash-faithful PowerShell command classifier is guardrails-owned and not
# vendored here; `gh api …/pulls` direct API calls; `gh pr edit` invocations
# that change no body (`--title`, `--add-label` alone) — the CI gate re-runs on
# `edited`, but such an edit leaves the body it already validated untouched; any
# invocation carrying `--repo`/`-R` or following a directory change; and one
# comment-stripping residual — the validator strips a comment span spanning a
# line break and JOINS what surrounds it, so `## Rel<!--\n-->ated` is a heading
# to CI and two lines here. Reproducing it needs whole-body (not per-line)
# stripping; the shape does not occur in a real body and is left as a residual.
#
# Kill switch: pr_body_linkage_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming the missing half(s) plus the line to add.

set -uo pipefail

# Pinned for the whole process: see LOCALE above. Set before anything reads a
# character class, including the shared lib.
export LC_ALL=C

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "PR_BODY_LINKAGE_GATE"

start=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PreToolUse" "source-control-pr-body-linkage-gate" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
# Applicability pre-filter before any repo I/O or parsing. `gh` must appear as
# its own word (or a path's last segment) so `npm run lighthouse-prod` does not
# pay for the parse. `.` stays OUT of the trailing class so `gh.exe` still
# matches, and out of the leading one so `./gh` does; a quote on either side is
# a boundary too, since the command text is pre-tokenizer.
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Hh][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *"pr"* ]] || exit 0

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
REPO_ROOT=$(hook::repo_root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}")

# The consuming repo's own gate definition is the authority; no gate, no
# enforcement.
GATE_FILE=""
for candidate in "$REPO_ROOT/.github/workflows/pr-issue-linkage.yml" \
  "$REPO_ROOT/.github/workflows/pr-issue-linkage.yaml"; do
  [[ -f "$candidate" ]] && {
    GATE_FILE="$candidate"
    break
  }
done
[[ -n "$GATE_FILE" ]] || exit 0

# How the judged body was obtained, for the telemetry envelope.
FORM=""
# Set once a segment changes the working directory; every later segment is then
# resolving against a directory this hook cannot see.
DIR_CHANGED=0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg outcome "$1" --arg form "$FORM" \
    '{outcome:$outcome,form:$form}' 2>/dev/null) || data='{"outcome":"","form":""}'
  hook::emit_telemetry "pr-body-linkage-gate" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- Body validation (mirrors the ci-workflows validator) --------------------

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
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
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
  done <<<"$body"
  printf '%s' "$out"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
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

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
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
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
related_section() {
  local body="$1" line t start=0 lvl i=0 out=""
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done <<<"$body"
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

# --- Command extraction ------------------------------------------------------

# Body of the SOLE heredoc in the given text. Covers both stdin forms the
# authoring corpus uses: `--body-file -` fed by a heredoc, and a `--body
# "$(cat <<'EOF' … EOF)"` command substitution, whose quoted value the segment
# tokenizer hands back verbatim (it strips heredoc bodies only outside quotes).
# Returns 1 with no heredoc, an unterminated one, or SEVERAL — with more than
# one, which of them reaches `gh` is not statically knowable, and judging the
# wrong text would block a compliant call.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sole_heredoc_body() {
  local text="$1" line delim="" in_hd=0 t out="" count=0
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      t="${line%$'\r'}"
      t="${t#"${t%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "$t" == "$delim" ]] && {
        in_hd=0
        continue
      }
      out+="${line%$'\r'}"$'\n'
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      ((count++))
      ((count > 1)) && return 1
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done <<<"$text"
  # Still inside the body at end of text: the delimiter never appeared.
  ((count == 1 && in_hd == 0)) || return 1
  printf '%s' "$out"
}

# A value the tokenizer could not fully resolve — an unexpanded expansion or a
# command substitution — is not this hook's to judge on its face.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block() {
  local p
  echo "BLOCKED: PR body fails this repo's required pr-issue-linkage check." >&2
  for p in "$@"; do echo "  - $p" >&2; done
  echo "Gate: ${GATE_FILE#"$REPO_ROOT/"} (required check 'pr-issue-linkage / pr-issue-linkage')." >&2
  echo "Add to the body:" >&2
  echo "  Closes #<issue>      (or the literal line: No linked issue)" >&2
  echo "  ## Related" >&2
  echo "  - <related PR / ADR / decision this PR does not close, or N/A>" >&2
  echo "Or create the PR through /source-control:pull-request create, which gates the body first." >&2
  emit_tel "blocked"
  exit 2
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
validate_body() {
  local body="$1" related
  local -a problems=()
  body=$(strip_html_comments "$body")
  # shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
  if related=$(related_section "$body"); then
    [[ -n "$related" ]] || problems+=('The "## Related" section is empty.')
  else
    problems+=('Missing a "## Related" section.')
  fi
  has_linkage "$body" ||
    problems+=('Missing a native closing keyword (Closes/Fixes/Resolves #N) and no "No linked issue" marker.')
  ((${#problems[@]})) || return 0
  block "${problems[@]}"
}

# gh long flags that consume the following argv word. Enumerated so a
# body-shaped string sitting in ANOTHER flag's value (`-l --body`) is never read
# as the body.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
takes_value() {
  case "$1" in
  --assignee | --base | --body | --body-file | --head | --label | --milestone | \
    --project | --reviewer | --template | --title | --repo | --recover | \
    --add-assignee | --add-label | --add-project | --add-reviewer | \
    --remove-assignee | --remove-label | --remove-project | --remove-reviewer)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# pflag groups shorthands: `-db BODY`, `-dbBODY`, `-dF file`, `-dFfile` are all
# valid and all carry a body, which a plain `-b`/`-F` match misses entirely.
# Walks the cluster; the first value-taking shorthand ends it, taking the rest
# of the word as its value or, when that is empty, the next word.
# Sets SHORT_KIND (body|file|repo|other|unknown), SHORT_VAL, SHORT_ATE_NEXT.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
parse_short_cluster() {
  local word="$1" next="$2" have_next="$3"
  local rest="${word#-}" c
  SHORT_KIND="other"
  SHORT_VAL=""
  SHORT_ATE_NEXT=0
  while [[ -n "$rest" ]]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$c" in
    # Value-taking shorthands. gh's own set; `b`/`F` carry the body, `R`
    # retargets the repository, the rest merely consume their value.
    b | F | R | a | B | H | l | m | p | r | T | t)
      if [[ -n "$rest" ]]; then
        SHORT_VAL="$rest"
      elif ((have_next)); then
        SHORT_VAL="$next"
        SHORT_ATE_NEXT=1
      else
        # Nothing left to take: gh rejects this as flag-needs-argument.
        SHORT_KIND="unknown"
        return 0
      fi
      case "$c" in
      b) SHORT_KIND="body" ;;
      F) SHORT_KIND="file" ;;
      R) SHORT_KIND="repo" ;;
      *) SHORT_KIND="other" ;;
      esac
      return 0
      ;;
    # Boolean shorthands: the cluster continues past them.
    d | e | f | w) ;;
    # Not a shorthand this hook knows. Stop reading the word rather than guess
    # which of its letters would have eaten the next one.
    *)
      SHORT_KIND="unknown"
      return 0
      ;;
    esac
  done
  return 0
}

# Whether a wrapper's flag consumes the FOLLOWING word. Without this, the
# separated form of an option value (`sudo -u root gh …`, `env -u VAR gh …`)
# leaves the value sitting where the command name is expected, and the wrapped
# `gh` is never found. An attached value (`-uroot`, `--user=root`) is part of
# the flag word and consumes nothing.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
wrapper_flag_takes_value() {
  local wrapper="$1" flag="$2"
  case "$flag" in
  *=*) return 1 ;;
  *) ;;
  esac
  case "$wrapper" in
  sudo)
    case "$flag" in
    -u | -g | -h | -p | -C | -D | -R | -T | -U | \
      --user | --group | --host | --prompt | --close-from | --chdir | --chroot | \
      --command-timeout | --other-user)
      return 0
      ;;
    *) return 1 ;;
    esac
    ;;
  env)
    case "$flag" in
    -u | --unset | -C | --chdir | -S | --split-string) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 word next have_next bin wrapper
  local body_flag="" body_val="" body=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # `gh` is commonly wrapped in command-scoped environment settings
  # (`GH_TOKEN=… gh …`, `env … gh …`, `sudo gh …`); step past them before
  # deciding this is not a gh call.
  while ((i < n)); do
    word="${w[i]}"
    if [[ "$word" == *=* && "$word" != -* ]]; then
      ((i++))
      continue
    fi
    case "${word##*/}" in
    env | command | sudo)
      wrapper="${word##*/}"
      ((i++))
      while ((i < n)); do
        case "${w[i]}" in
        --)
          ((i++))
          break
          ;;
        -*)
          # shellcheck disable=SC2310  # pure classifier; a false return is the "no value" case
          if wrapper_flag_takes_value "$wrapper" "${w[i]}"; then ((i++)); fi
          ((i++))
          ;;
        *=*) ((i++)) ;;
        *) break ;;
        esac
      done
      continue
      ;;
    *) break ;;
    esac
  done

  # A directory change puts every later segment somewhere this hook cannot
  # resolve; see WHICH DIRECTORY in the header.
  case "${w[i]:-}" in
  cd | pushd | popd)
    DIR_CHANGED=1
    return 0
    ;;
  *) ;;
  esac
  ((DIR_CHANGED)) && return 0

  # Match `gh` by its basename, so `gh.exe`, `/usr/bin/gh`, and `./gh` are the
  # same call — the wrapper loop above already reads basenames.
  bin="${w[i]:-}"
  bin="${bin//\\//}"
  bin="${bin##*/}"
  bin="${bin,,}"
  bin="${bin%.exe}"
  [[ "$bin" == "gh" && "${w[i + 1]:-}" == "pr" ]] || return 0
  case "${w[i + 2]:-}" in
  create | new | edit) ;;
  *) return 0 ;;
  esac

  for ((i = i + 3; i < n; i++)); do
    word="${w[i]}"
    next=""
    have_next=0
    ((i + 1 < n)) && {
      next="${w[i + 1]}"
      have_next=1
    }
    case "$word" in
    --) break ;;
    # The target repository may not be the one whose gate file was read.
    --repo | --repo=*) return 0 ;;
    # A body flag with no following word is a malformed command gh rejects on
    # its own; there is no body to judge. An explicitly EMPTY value is a
    # different case — the word is present, and gh would open a PR with a blank
    # body the gate rejects — so it stays judged.
    --body)
      ((have_next)) || return 0
      body_flag="body"
      body_val="$next"
      ((i++))
      ;;
    --body=*)
      body_flag="body"
      body_val="${word#--body=}"
      ;;
    --body-file)
      ((have_next)) || return 0
      body_flag="file"
      body_val="$next"
      ((i++))
      ;;
    --body-file=*)
      body_flag="file"
      body_val="${word#--body-file=}"
      ;;
    --*)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "$word"; then ((i++)); fi
      ;;
    -?*)
      parse_short_cluster "$word" "$next" "$have_next"
      case "$SHORT_KIND" in
      repo) return 0 ;;
      body)
        body_flag="body"
        body_val="$SHORT_VAL"
        ;;
      file)
        body_flag="file"
        body_val="$SHORT_VAL"
        ;;
      *) ;;
      esac
      ((SHORT_ATE_NEXT)) && ((i++))
      ;;
    *) ;;
    esac
  done

  # No body flag: `--fill`, `--template`, `--editor`, `--web`, the interactive
  # prompt, or a `gh pr edit` that changes something other than the body. The
  # body is not this call's to determine.
  [[ -n "$body_flag" ]] || return 0

  if [[ "$body_flag" == "file" ]]; then
    if [[ "$body_val" == "-" ]]; then
      # The heredoc feeding stdin lives outside the value, in the raw command.
      body=$(sole_heredoc_body "$COMMAND") || return 0
      FORM="stdin-heredoc"
    else
      local path="$body_val"
      [[ "$path" == /* || "$path" =~ ^[A-Za-z]:[\\/] ]] || path="${HOOK_CWD:-$REPO_ROOT}/$path"
      [[ -r "$path" && -f "$path" ]] || return 0
      body=$(cat -- "$path") || return 0
      FORM="body-file"
    fi
  else
    # shellcheck disable=SC2310  # is_dynamic is a pure predicate; both branches are handled
    if is_dynamic "$body_val"; then
      # The `$(cat <<'EOF' … EOF)` substitution is inside the value itself, so
      # judge only that — a heredoc elsewhere in the command is not this body.
      body=$(sole_heredoc_body "$body_val") || return 0
      FORM="body-substitution"
    else
      body="$body_val"
      FORM="body-literal"
    fi
  fi

  validate_body "$body"
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok"
exit 0
