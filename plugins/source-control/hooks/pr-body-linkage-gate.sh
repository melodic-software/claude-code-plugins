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
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE BAD BODY. The body is
# only judged when it can be read statically: a `--body`/`-b` literal, a
# `--body-file`/`-F <path>` that exists, or the first heredoc body when the
# command feeds stdin (`--body-file -`) or wraps one in a command substitution
# (`--body "$(cat <<'EOF' … EOF)"`). A value carrying an unexpanded `$` or
# backtick with no heredoc to resolve it, an absent body flag (`--fill`,
# `--template`, `--editor`, `--web`, the interactive prompt), or an unreadable
# body file all ALLOW: guessing at a body this hook cannot see would block
# compliant calls.
#
# DECLARED BYPASS COVERAGE (out of scope, documented): the PowerShell tool —
# the Bash-faithful PowerShell command classifier is guardrails-owned and not
# vendored here; `gh api …/pulls` direct API calls; `gh pr edit` invocations
# that change no body (`--title`, `--add-label` alone) — the CI gate re-runs on
# `edited`, but such an edit leaves the body it already validated untouched; and
# any invocation carrying `--repo`/`-R`, whose target repository may not be the
# local one whose workflow file the scope guard read.
#
# Kill switch: pr_body_linkage_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming the missing half(s) plus the line to add.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "PR_BODY_LINKAGE_GATE"

start=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq "PreToolUse" "source-control-pr-body-linkage-gate" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
# Cheap applicability pre-filter before any repo I/O or parsing.
[[ "$COMMAND" == *"gh"* && "$COMMAND" == *"pr"* ]] || exit 0

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

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg outcome "$1" --arg form "$FORM" \
    '{outcome:$outcome,form:$form}' 2>/dev/null) || data='{"outcome":"","form":""}'
  hook::emit_telemetry "pr-body-linkage-gate" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- Body validation (mirrors the ci-workflows validator) --------------------

# Remove HTML comments the way the validator does — every terminated `<!-- … -->`
# span, then an unterminated `<!--` taking everything after it. Both strips are
# one left-to-right pass with a carried in-comment state, which produces exactly
# that result: once a `<!--` has no `-->`, the state never clears again.
# GitHub's own closing-keyword parser and its Markdown renderer both ignore
# commented-out text, so an unedited PR template — whose instructional prose
# names the very markers this gate looks for — must not pass vacuously.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
strip_html_comments() {
  local body="$1" line rest kept out="" in_comment=0
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

# Content of the first `## Related` section, or the sentinel when there is no
# such heading. Only a heading at the SAME level or higher (fewer or equal `#`)
# closes the section, so a nested `### …` subsection is content — a naive
# "next line starting with #" reading would call such a section empty.
RELATED_ABSENT=$'\001absent'
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
related_section() {
  local body="$1" line t start=0 lvl i=0 out=""
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done <<<"$body"
  for ((i = 0; i < ${#lines[@]}; i++)); do
    t=$(trim "${lines[i]}")
    [[ "${t,,}" =~ ^##[[:space:]]+related$ ]] && {
      start=$((i + 1))
      break
    }
  done
  ((start)) || {
    printf '%s' "$RELATED_ABSENT"
    return 0
  }
  for ((i = start; i < ${#lines[@]}; i++)); do
    t=$(trim "${lines[i]}")
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
  local text="$1" line delim="" in_hd=0 trimmed out="" count=0
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      trimmed=$(trim "${line%$'\r'}")
      [[ "$trimmed" == "$delim" ]] && {
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
  related=$(related_section "$body")
  if [[ "$related" == "$RELATED_ABSENT" ]]; then
    problems+=('Missing a "## Related" section.')
  elif [[ -z "$related" ]]; then
    problems+=('The "## Related" section is empty.')
  fi
  has_linkage "$body" ||
    problems+=('Missing a native closing keyword (Closes/Fixes/Resolves #N) and no "No linked issue" marker.')
  ((${#problems[@]})) || return 0
  block "${problems[@]}"
}

# gh flags that consume the following argv word. Enumerated so a body-shaped
# string sitting in ANOTHER flag's value (`-l --body`) is never read as the body.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
takes_value() {
  case "$1" in
  -a | --assignee | -B | --base | -b | --body | -F | --body-file | -H | --head | \
    -l | --label | -m | --milestone | -p | --project | -r | --reviewer | \
    -T | --template | -t | --title | -R | --repo | --recover | \
    --add-assignee | --add-label | --add-project | --add-reviewer | \
    --remove-assignee | --remove-label | --remove-project | --remove-reviewer)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 word next
  local body_flag="" body_val="" body=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # `gh` is commonly wrapped in command-scoped environment settings
  # (`GH_TOKEN=… gh …`, `env … gh …`); step past them before deciding this is
  # not a gh call.
  while ((i < n)); do
    word="${w[i]}"
    if [[ "$word" == *=* && "$word" != -* ]]; then
      ((i++))
      continue
    fi
    case "${word##*/}" in
    env | command)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* || ("${w[i]}" == *=* && "${w[i]}" != -*) ]]; do ((i++)); done
      continue
      ;;
    *) break ;;
    esac
  done

  [[ "${w[i]:-}" == "gh" && "${w[i + 1]:-}" == "pr" ]] || return 0
  case "${w[i + 2]:-}" in
  create | new | edit) ;;
  *) return 0 ;;
  esac

  for ((i = i + 3; i < n; i++)); do
    word="${w[i]}"
    next=""
    ((i + 1 < n)) && next="${w[i + 1]}"
    case "$word" in
    --) break ;;
    # The target repository may not be the one whose gate file was read.
    -R | --repo | -R?* | --repo=*) return 0 ;;
    # A body flag with no following word is a malformed command gh rejects on
    # its own; there is no body to judge. An explicitly EMPTY value is a
    # different case — the word is present, and gh would open a PR with a blank
    # body the gate rejects — so it stays judged.
    --body | -b)
      ((i + 1 < n)) || return 0
      body_flag="body"
      body_val="$next"
      ((i++))
      ;;
    --body=*)
      body_flag="body"
      body_val="${word#--body=}"
      ;;
    -b?*)
      body_flag="body"
      body_val="${word#-b}"
      ;;
    --body-file | -F)
      ((i + 1 < n)) || return 0
      body_flag="file"
      body_val="$next"
      ((i++))
      ;;
    --body-file=*)
      body_flag="file"
      body_val="${word#--body-file=}"
      ;;
    -F?*)
      body_flag="file"
      body_val="${word#-F}"
      ;;
    *)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "$word"; then ((i++)); fi
      ;;
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
      [[ -r "$path" ]] || return 0
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

emit_tel "ok" ""
exit 0
