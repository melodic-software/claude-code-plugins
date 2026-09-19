#!/usr/bin/env bash
# PreToolUse hook: nudge, never block, when a pull request is flipped to
# ready-for-review without evidence that the mandatory pre-PR skills ran on the
# commit under review.
#
# WHY IT EXISTS. This repository's mandatory reviews run on the operator's own
# seat, inside `/source-control:pull-request`, and the proof they ran is a
# head-stamped row in the skill-usage ledger. A session that flips a draft with
# a bare `gh pr ready` skips the skill's ready step, so nothing runs the missing
# skills and nothing re-renders the evidence block in the body. This hook is the
# nudge at that moment: it reads the ledger through
# `scripts/skill-evidence.sh check` and, when a mandatory skill has no fresh row
# at HEAD, names the skills that are owed and points at
# `/source-control:pull-request ready`, which runs them on the committed head
# and re-renders the block before flipping.
#
# ADVISORY, ALWAYS. The verdict travels on `additionalContext` and the exit
# status is 0 on every path, a broken environment included. It is a nudge, not a
# gate: the `ci-status` validator reports the same gap on every flip however the
# flip was made, so a miss here costs a nudge and never a blocked call. The hook
# also records nothing of its own. The validator's comment marker is the count
# of record for the promotion window, and a second writer would double-count it.
#
# WHAT IT MATCHES, per parsed argv rather than token co-occurrence
# (hook-precision rules 2 and 5), on each segment of the command line, one
# matcher per route a session can flip a pull request through:
#   * `gh pr ready [...]`, the CLI flip;
#   * `gh api graphql` whose `-f`/`-F`/`--field`/`--raw-field` `query=` operand
#     names `markPullRequestReadyForReview`, the flip's GraphQL mutation;
#   * `gh api` whose path operand is the cloud proxy's route,
#     `repos/<owner>/<repo>/pulls/<n>/ccr/ready_for_review`, with POST or with
#     no method flag. A session that cannot reach GraphQL is told to use that
#     route by name, so it is a flip surface of its own and not a REST
#     lookalike. Its sibling `ccr/convert_to_draft` is the undo, which owes no
#     evidence and is not matched.
#
# The GitHub MCP tool is a fourth surface, covered by the sibling
# pr-ready-evidence-mcp-gate.sh.
#
# OUT OF SCOPE, silent and allowed: `gh pr ready --undo`, which converts a pull
# request back to a draft and owes no evidence; `--help` on either form, which
# prints and exits without flipping anything; a `cd`/`pushd`/`popd` earlier on
# the command line, after which the directory the repository resolves from is
# not knowable here; `--repo`/`-R`, which points the call at a repository whose
# evidence map this checkout does not hold; and any command line with no
# matching segment.
#
# DECLARED BYPASS COVERAGE (documented misses, each one a lost nudge and never a
# false one): a flip wrapped in `env` or `sudo`; a GraphQL query supplied from a
# file (`-f query=@mutation.graphql`) or through an expansion the tokenizer
# cannot resolve; and the PowerShell tool, whose Bash-faithful command
# classifier is guardrails-owned and not vendored here. The GitHub MCP surface
# is covered by the sibling pr-ready-evidence-mcp-gate.sh.
#
# Kill switch: pr_ready_evidence_gate_enabled userConfig option.

set -uo pipefail

# Pinned for the whole process so the character classes below do not depend on
# the ambient locale, as in the sibling PR-body gates. Set before anything reads
# a class, the shared library included.
export LC_ALL=C

# Kill switch FIRST, above every source: a disabled gate must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics.
[[ "${CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`: a command
# substitution forks a subshell even for a builtin body, and on Windows Git Bash
# that fork is a process.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

hook::buffer_stdin_to INPUT || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require_jq "PreToolUse" "source-control-pr-ready-evidence-gate" "$INPUT"

# Every payload field in ONE jq process, the shape the sibling gates use: a
# per-field read costs 3 to 4 forks and 1 to 2 execs EACH over the same buffered
# string. `|| exit 0` is the advisory allow a failed batch earns.
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.command' '.cwd' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
COMMAND="${HOOK_JQ_FIELDS[1]}"
HOOK_CWD="${HOOK_JQ_FIELDS[2]}"
# hook::jq_fields CR-strips but does not chomp trailing newlines, which the
# `$(jq ...)` form it replaced did. A tool name carrying one would miss the
# exact match below, and a cwd carrying one fails `git -C`.
while [[ "$TOOL" == *$'\n' ]]; do TOOL="${TOOL%$'\n'}"; done
while [[ "$HOOK_CWD" == *$'\n' ]]; do HOOK_CWD="${HOOK_CWD%$'\n'}"; done

[[ "$TOOL" == "Bash" ]] || exit 0
[[ -n "$COMMAND" ]] || exit 0

# Applicability pre-filter before any repository I/O or parsing. `gh` must
# appear as its own word, or as a path's last segment, so an unrelated command
# never pays for the tokenizer. `.` stays out of both classes so `gh.exe` and
# `./gh` still match; a quote on either side is a boundary, since this text is
# pre-tokenizer.
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Hh][^[:alnum:]_-] ]] || exit 0

# Set by the callback when a segment is a ready flip, and when a segment moved
# the working directory out from under the repository resolution below.
MATCHED=0
DIR_CHANGED=0

# gh flags that consume the following argv word, in both spellings gh accepts.
# Enumerated so a value sitting in another flag's operand is never read as an
# operand of its own: `gh api -H graphql ...` would otherwise read the header
# value as the `graphql` endpoint.
# shellcheck disable=SC2329  # reached through the hook::bash_parse_segments callback chain
takes_value() {
  case "$1" in
  --repo | --field | --raw-field | --header | --method | --jq | --template | \
    --cache | --hostname | --input | --preview | \
    -H | -X | -q | -t | -p)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# Does this `gh pr ...` segment flip a pull request to ready for review?
# <start> is the index of the word after `pr`; the remaining arguments are the
# whole segment's argv.
# shellcheck disable=SC2329  # reached through the hook::bash_parse_segments callback chain
is_pr_ready() {
  local start="$1"
  shift
  local -a w=("$@")
  local n=${#w[@]} i
  [[ "${w[start]:-}" == "ready" ]] || return 1
  for ((i = start + 1; i < n; i++)); do
    case "${w[i]}" in
    --) break ;;
    # `--undo` converts the pull request BACK to a draft, which owes no
    # evidence; `--help` prints and exits without flipping anything.
    --undo | --help | -h) return 1 ;;
    # The call names a repository whose evidence map this checkout does not
    # hold.
    --repo | --repo=* | -R | -R?*) return 1 ;;
    *) ;;
    esac
  done
  return 0
}

# Does this `gh api ...` segment run the ready-for-review GraphQL mutation?
# <start> is the index of the word after `api`.
# shellcheck disable=SC2329  # reached through the hook::bash_parse_segments callback chain
is_api_ready() {
  local start="$1"
  shift
  local -a w=("$@")
  local n=${#w[@]} i word val graphql=0 mutation=0
  for ((i = start; i < n; i++)); do
    word="${w[i]}"
    case "$word" in
    --) break ;;
    --help | -h) return 1 ;;
    --repo | --repo=* | -R | -R?*) return 1 ;;
    # A field operand, in every spelling gh accepts: `-f k=v`, `-fk=v`,
    # `--field k=v`, `--field=k=v`, and the raw-field twins.
    -f | -F | --field | --raw-field)
      val="${w[i + 1]:-}"
      ((i++))
      ;;
    -f?* | -F?*) val="${word:2}" ;;
    --field=* | --raw-field=*) val="${word#*=}" ;;
    -*)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "${word%%=*}" && [[ "$word" != *=* ]]; then ((i++)); fi
      continue
      ;;
    *)
      [[ "$word" == "graphql" ]] && graphql=1
      continue
      ;;
    esac
    # A `query=` operand naming the mutation is the GraphQL flip. A query read
    # from a file (`query=@mutation.graphql`) is a documented miss: its text is
    # not on the command line.
    if [[ "$val" == query=*markPullRequestReadyForReview* ]]; then
      mutation=1
    fi
  done
  ((graphql && mutation))
}

# Does this `gh api ...` segment call the cloud proxy's ready-for-review route?
# <start> is the index of the word after `api`. The route carries the owner,
# the repository and the number in one path operand, so it is read whole rather
# than from any token on its own.
# shellcheck disable=SC2329  # reached through the hook::bash_parse_segments callback chain
is_ccr_ready() {
  local start="$1"
  shift
  local -a w=("$@")
  local n=${#w[@]} i word method="" path=""
  for ((i = start; i < n; i++)); do
    word="${w[i]}"
    case "$word" in
    --) break ;;
    --help | -h) return 1 ;;
    --method | -X)
      method="${w[i + 1]:-}"
      ((i++))
      ;;
    --method=*) method="${word#*=}" ;;
    -X?*) method="${word:2}" ;;
    -*)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "${word%%=*}" && [[ "$word" != *=* ]]; then ((i++)); fi
      ;;
    *)
      # The first non-flag word is the endpoint; a later one is an operand of
      # something else.
      [[ -n "$path" ]] || path="$word"
      ;;
    esac
  done
  # No method flag is the shape the proxy's own message prints; any method
  # other than POST is a different call on the same path.
  [[ -z "$method" || "${method,,}" == "post" ]] || return 1
  # A query string is stripped so the suffix is read against the path alone,
  # and a full `https://api.github.com/...` form is read the same way a bare
  # path is.
  path="${path%%\?*}"
  [[ "$path" =~ (^|/)repos/[^/]+/[^/]+/pulls/[0-9]+/ccr/ready_for_review$ ]]
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 d bin

  # `bash -c '...'` carries a whole command line in one operand; re-parse that
  # operand rather than read it as an argv word.
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # Leading `VAR=val` assignments are not the command word.
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done

  # Only the CURRENT shell can relocate later segments. `command`, `builtin` and
  # `eval` dispatch a builtin inside this shell, so `command cd /x` really does
  # move it; `sudo cd /x` and `env cd /x` are separate processes that fail on a
  # builtin and move nothing, which is why neither appears here.
  d=$i
  while ((d < n)); do
    case "${w[d]}" in
    command | builtin | eval | -p) ((d++)) ;;
    *) break ;;
    esac
  done
  case "${w[d]:-}" in
  cd | pushd | popd)
    DIR_CHANGED=1
    return 0
    ;;
  *) ;;
  esac
  ((DIR_CHANGED)) && return 0

  # Match `gh` by basename, so `gh.exe`, `/usr/bin/gh` and `./gh` are one call.
  bin="${w[i]:-}"
  bin="${bin//\\//}"
  bin="${bin##*/}"
  bin="${bin,,}"
  bin="${bin%.exe}"
  [[ "$bin" == "gh" ]] || return 0

  case "${w[i + 1]:-}" in
  pr)
    # shellcheck disable=SC2310  # the return status IS the verdict
    is_pr_ready "$((i + 2))" "${w[@]}" && MATCHED=1
    ;;
  api)
    # shellcheck disable=SC2310  # the return status IS the verdict
    is_api_ready "$((i + 2))" "${w[@]}" && MATCHED=1
    # shellcheck disable=SC2310  # the return status IS the verdict
    is_ccr_ready "$((i + 2))" "${w[@]}" && MATCHED=1
    ;;
  *) ;;
  esac
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment
((MATCHED)) || exit 0

# --- In scope from here: the call flips a pull request to ready ---------------
# Everything below spawns processes, which is why nothing above it does.

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || exit 0

# notice <key> <message>: one visible skip notice per (session, agent) for an
# environment this gate cannot read, then silence. Every caller exits 0 after.
notice() {
  hook::notice_once "$1" "$INPUT" && hook::emit_skip_notice "PreToolUse" "$2"
  return 0
}

# The redirect sits on the enclosing GROUP, not inside the substitution: bash
# elides the substitution's own extra fork only when the command carries no
# redirection of its own.
{ HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD) || HEAD_SHA=""; } 2>/dev/null
if [[ -z "$HEAD_SHA" ]]; then
  notice "source-control-pr-ready-evidence-head" \
    "source-control pr-ready-evidence-gate: $REPO_ROOT has no HEAD commit, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed."
  exit 0
fi

# The base branch the diff is classified against. `refs/remotes/origin/HEAD` is
# the recorded default branch; `origin/main` is the fallback for a checkout that
# never had one set.
{ BASE_REF=$(git -C "$REPO_ROOT" symbolic-ref -q refs/remotes/origin/HEAD) || BASE_REF=""; } 2>/dev/null
if [[ -z "$BASE_REF" ]]; then
  if git -C "$REPO_ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    BASE_REF="origin/main"
  fi
fi
if [[ -z "$BASE_REF" ]]; then
  notice "source-control-pr-ready-evidence-base" \
    "source-control pr-ready-evidence-gate: neither refs/remotes/origin/HEAD nor origin/main resolves in $REPO_ROOT, so the changed-file classes for this ready flip cannot be detected. The flip was allowed. Run \`git fetch origin\` and \`git remote set-head origin -a\` to give the gate a base."
  exit 0
fi

# The ledger location, from this plugin's own option. The scope words mirror
# claude-ops' skill_usage_scope, which is the option that WRITES the ledger;
# anything else is read as a path, with a leading `~/` expanded.
STORE="${CLAUDE_PLUGIN_OPTION_SKILL_EVIDENCE_STORE:-repo}"
case "$STORE" in
repo | "") LEDGER="$REPO_ROOT/.claude/observability/skill-usage.jsonl" ;;
user) LEDGER="${HOME:-}/.claude/observability/skill-usage.jsonl" ;;
*)
  # A path. The strip pattern escapes the tilde so nothing expands here; a
  # value that carried a leading `~/` is joined to $HOME instead.
  LEDGER="${STORE#\~/}"
  [[ "$LEDGER" != "$STORE" ]] && LEDGER="${HOME:-}/$LEDGER"
  ;;
esac

if [[ ! -f "$LEDGER" ]]; then
  notice "source-control-pr-ready-evidence-ledger" \
    "source-control pr-ready-evidence-gate: no skill-usage ledger at $LEDGER, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed. That ledger is written by the claude-ops plugin: enable it, and set its skill_usage_scope option and this plugin's skill_evidence_store option to the same scope word. Set pr_ready_evidence_gate_enabled to false to turn this gate off."
  exit 0
fi

# The one reader of the evidence rule, shared with the ready step, the ci-status
# validator and the babysit merge gate, so no reader drifts from another.
EVIDENCE_SH="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$EVIDENCE_SH" ]]; then
  EVIDENCE_SH="$EVIDENCE_SH/scripts/skill-evidence.sh"
else
  EVIDENCE_SH="$HOOK_DIR/../scripts/skill-evidence.sh"
fi

REPORT=""
RC=0
{ REPORT=$(CLAUDE_PROJECT_DIR="$REPO_ROOT" "$EVIDENCE_SH" check \
  --head "$HEAD_SHA" --ledger "$LEDGER" --base "$BASE_REF") || RC=$?; } 2>/dev/null
if ((RC != 0)); then
  notice "source-control-pr-ready-evidence-script" \
    "source-control pr-ready-evidence-gate: scripts/skill-evidence.sh exited $RC, so the pre-PR skill evidence for this ready flip could not be read. The flip was allowed."
  exit 0
fi

# `verdict=inert` (no map, so the mechanism is off in this repository) and
# `verdict=clean` (every mandatory skill has a fresh row) both say nothing.
case "$REPORT" in
*"verdict=gap"*) ;;
*) exit 0 ;;
esac

CTX="source-control pr-ready-evidence-gate: this call flips a pull request to ready for review, but the skill-usage ledger carries no fresh evidence at HEAD $HEAD_SHA that every mandatory pre-PR skill ran."
# Split in the shell rather than `while read < <(...)` or a here-string: both
# hand the text to a reader through a file descriptor bash has to set up, and
# this loop needs neither a fork nor a temporary file.
rest="$REPORT"
while [[ -n "$rest" ]]; do
  line="${rest%%$'\n'*}"
  if [[ "$line" == "$rest" ]]; then rest=""; else rest="${rest#*$'\n'}"; fi
  case "$line" in
  missing=*) CTX+=$'\n'"  missing: ${line#missing=}" ;;
  stale=*) CTX+=$'\n'"  stale: ${line#stale=}" ;;
  *) ;;
  esac
done
CTX+=$'\n'"Run \`/source-control:pull-request ready\` instead of flipping directly. It runs the missing skills against the committed head, commits anything they change, and re-renders the evidence block in the pull request body before the flip."
CTX+=$'\n'"This notice is advisory and the call was allowed."

hook::emit_channels "PreToolUse" "$CTX" ""
exit 0
