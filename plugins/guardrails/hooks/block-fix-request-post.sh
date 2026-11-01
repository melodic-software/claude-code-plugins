#!/usr/bin/env bash
# PreToolUse hook: block an agent from posting the PR-fix lane's fix request.
#
# WHY. The address-feedback lane (.github/scripts/pr-unblock/address-feedback.mjs,
# FIX_REQUEST) treats a comment line that starts with
# `PR-fix lane: please fix this finding` (any case), written by a trusted person
# with write access, as direction for a lane that holds push credentials. A
# local session posts with the owner's GitHub token, so a prompt-injected agent
# could steer that lane. The owner decided that only they, typing in the GitHub
# UI, post the phrase (#8438). This guard holds that decision on the Bash and
# PowerShell tools and on the GitHub MCP server's comment, review, issue and
# pull-request write tools. The risk is our own actors, so a repository may
# lift it for sessions working in it: `fix_request_post` in
# docs/conventions/guardrails.yaml (schema schemas/guardrails.schema.json) is
# `block` (the default) or `allow`. It is read from the session's repository
# (the payload's cwd) at its local `origin/HEAD`, never the working tree or
# index, so an edit and `git add` do not lift it. Under `allow` a would-be
# block exits 0, whichever repository the post targets. No such ref or file, a
# missing key, a file that does not parse or any other value keeps `block`; the
# last two say so.
#
# WHAT BLOCKS. A command that posts or edits GitHub content, carrying the phrase
# where the lane would read it as a request:
#   gh          `gh pr|issue comment|review|create|edit` (`--body`, `--body-file`,
#               `-F`, `-` for stdin); `gh api` that writes (a field, `--input`,
#               or a method other than GET or HEAD), reading `-F k=@file`,
#               `--input file` and `@-`/`-` from stdin.
#   curl        to api.github.com or a GHES `/api/v3` or `/api/graphql` route,
#               with a data, form or upload flag and no `-G`; `@file` and `@-`
#               are read.
#   GraphQL     through either, only when the query text names a mutation.
#   MCP         the tool's `body`, and a review's `comments`.
# The body is read from the posting command's own words (a quoted
# `$(cat <<EOF ...)` stays in its word, and a quoted `$(cat file)` is read) and
# every file it names as a body. When a posting command reads stdin or expands
# a variable or substitution, when it posts a body file and the command writes
# a file or the body file does not exist yet, or on PowerShell, the whole
# command text (heredocs, pipes, assignments), here-strings and every file fed
# through `cat` or `<` are read too. Relative paths resolve against the
# payload's cwd. A `bash -c`/`sh -c` operand and an `eval` are read as commands
# too.
#
# HOW A BODY IS READ. Case-insensitively, as FIX_REQUEST is, and line by line:
# a line counts when the phrase starts it, or follows a quote or `=` that opens
# a value (`--body "PR-fix ...`, `"body":"PR-fix ...`, `body=PR-fix ...`), and
# is not followed by a letter, digit or `_`. JSON (`\n`, `\u000a`) and URL
# (`%0A`, `+`) escapes are decoded first. A line inside a fence does not count,
# with the lane's own fence rule (a line starting with up to three spaces and
# ``` or ~~~, either marker toggling it), so the guard never sees a fence the
# lane does not; nor does a
# line starting `>`, nor a mention later in a line. Doubt resolves to a block:
# the phrase inside an HTML comment counts, as it does for the lane, and so
# does a quoted mention mid-line (`see "PR-fix lane: please fix this finding"`).
# A false block costs a rephrase; a missed one steers a push-holding lane.
#
# STAYS QUIET on a command that reads, greps or shows the phrase (`grep`,
# `git show`, `gh search`, a `gh api` GET, a GraphQL query), on a command that
# posts nothing to GitHub, and on Write and Edit, which are not wired to it.
#
# KNOWN GAPS: a body assembled through a variable, `printf` with a computed
# argument or another expansion; a script (Python, Node) or cmdlet
# (`Invoke-RestMethod`) that posts; a wrapper this guard does not step over
# (`xargs`, `sudo` with an option other than -u/-g/-C/-D); a relative body
# file after a `cd` in the same command, which resolves against the payload's
# cwd instead; a body file written in the same command by a program other than
# a redirect, cp, mv, ln, install, rsync or tee (a script, `sed -i`); a body file past 1 MiB is read to
# that point only. `fix_request_post` is keyed to the session's repository,
# not the post's target: a session in an `allow` repository passes a post to
# any repository (`-R`, an API route, MCP `owner`/`repo`), and a session that
# rewrites its local `origin/HEAD` (`git remote set-head`, `git update-ref`)
# chooses the value read.
#
# Escape: the `block_fix_request_post_enabled` userConfig option (true or false;
# any other value keeps the guard on and says so). userConfig resolves at
# plugin-enable time, so an inline env prefix on the command cannot change it.
# Per repository: `fix_request_post: allow`, above.
#
# BLOCKING: exits 2 on a detected post.

set -uo pipefail

# Kill switch FIRST, above every source (scripts/check-killswitch-hoist.sh).
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice; 0 (allow) and 2 (block) pass through, like the other per-call guards.
guard::abort_boundary block-fix-request-post PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=../lib/github-post/github-post-body.sh
source "${CLAUDE_PLUGIN_ROOT:-$_HOOK_SELF/..}/lib/github-post/github-post-body.sh" || exit 70

_bfr_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}"
start=${EPOCHREALTIME:-}

# rc 1 (empty stdin) skips; rc 2 (not JSON) FAILS CLOSED; rc 3 (a payload cut
# short by the pipe) is a loud skip the dispatcher takes once.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
[[ "$_bfr_enabled" == true ]] ||
  guard::bad_switch_notice block_fix_request_post_enabled "$_bfr_enabled" "$INPUT"

hook::require_jq_blocking "guardrails-block-fix-request-post" "block_fix_request_post_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
if ((jq_rc == 2)); then
  guard::refuse_unparsable
  exit 2
fi
((jq_rc != 0)) && exit 0
if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
_BFR_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"

_BFR_PHRASE='pr-fix lane: please fix this finding'
# A request line: the phrase at a line start or right after a value-opening
# quote or `=`, then no word character. The fast form reads the whole text, a
# newline standing for the line start; the line form is for fenced text.
_bfr_q="[\"'=]"
_BFR_RE_ANY="(["$'\n'"\"'=])${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_LINE="^(.*${_bfr_q})?${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_FENCE="^ {0,3}(\`\`\`|~~~)"

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2"
  hook::emit_telemetry "block-fix-request-post" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# _bfr_allowed: 0 when the team file on the payload's repository's default
# branch (origin/HEAD) sets fix_request_post to allow. That ref, never the
# working tree or the index, so one edit and `git add` do not lift it (KNOWN
# GAPS names what does). Read only on a would-block call, so a call that
# posts no request pays nothing. Any other state keeps the block; a value
# other than allow or block, or a file that does not parse, says so.
_BFR_TEAM_REL="docs/conventions/guardrails.yaml"
_bfr_allowed() {
  local root text recs val key=$'\nfix_request_post\t'
  hook::repo_root_to root "$_BFR_CWD" || return 1
  text=$(git -C "$root" show "refs/remotes/origin/HEAD:$_BFR_TEAM_REL" 2>/dev/null) || return 1
  if ! recs=$(LC_ALL=C awk -v STRICT=1 -f "$_HOOK_SELF/yaml-subset.awk" <<<"$text" 2>/dev/null); then
    printf 'guardrails: %s does not parse; fix_request_post stays block.\n' "$_BFR_TEAM_REL" >&2
    return 1
  fi
  recs=$'\n'"$recs"
  [[ "$recs" == *"$key"* ]] || return 1
  val="${recs#*"$key"}"
  val="${val%%$'\n'*}"
  [[ "$val" == allow ]] && return 0
  [[ "$val" == block ]] ||
    printf "guardrails: %s sets fix_request_post: '%s', not allow or block; it stays block.\n" "$_BFR_TEAM_REL" "$val" >&2
  return 1
}

block() {
  if _bfr_allowed; then
    emit_tel ok "$1, allowed by fix_request_post"
    exit 0
  fi
  printf '%s\n' \
    "BLOCKED: this would post the PR-fix lane fix request (a line starting \"PR-fix lane: please fix this finding\") to GitHub ($1)." \
    "Only the repository owner may post a fix request, typed in the GitHub UI: the address-feedback lane acts on it with push credentials, and an agent posts with the owner's token (owner decision, https://github.com/melodic-software/claude-code-plugins/issues/8438)." \
    "Leave the request to the owner. To cite the phrase, put it after \"> \" or inside a code fence." >&2
  emit_tel blocked "$1"
  exit 2
}

# _bfr_lines <lowercased text>: 0 when a line reads as a fix request.
_bfr_lines() {
  [[ "$1" == *"$_BFR_PHRASE"* ]] || return 1
  if [[ "$1" != *'```'* && "$1" != *'~~~'* ]]; then
    [[ $'\n'"$1" =~ $_BFR_RE_ANY ]]
    return
  fi
  local line fenced=0
  local -a lines=()
  mapfile -t lines <<<"$1"
  for line in "${lines[@]}"; do
    if [[ "$line" =~ $_BFR_RE_FENCE ]]; then
      fenced=$((1 - fenced))
    elif ((! fenced)) && [[ "$line" =~ $_BFR_RE_LINE ]]; then
      return 0
    fi
  done
  return 1
}

# _bfr_carries <text>: 0 when <text>, or its JSON- or URL-decoded form, holds a
# request line.
# shellcheck disable=SC1003  # '\' compares a literal backslash, not a quote escape
_bfr_carries() {
  local t="${1,,}" d
  t="${t//$'\r'/}"
  _bfr_lines "$t" && return 0
  if [[ "$t" == *'\'* ]]; then
    d="${t//\\r/}"
    d="${d//\\n/$'\n'}"
    d="${d//\\u000a/$'\n'}"
    d="${d//\\u000d/}"
    d="${d//\\u0020/ }"
    d="${d//\\u002d/-}"
    d="${d//\\u003a/:}"
    d="${d//\\t/$'\t'}"
    d="${d//\\\"/\"}"
    d="${d//\\\'/\'}"
    d="${d//\\ / }"
    _bfr_lines "$d" && return 0
  fi
  if [[ "$t" == *%* || "$t" == *+* ]]; then
    d="${t//%0d/}"
    d="${d//%0a/$'\n'}"
    d="${d//+/ }"
    d="${d//%20/ }"
    d="${d//%2d/-}"
    d="${d//%3a/:}"
    d="${d//%22/\"}"
    d="${d//%27/\'}"
    d="${d//%3d/=}"
    _bfr_lines "$d" && return 0
  fi
  return 1
}

# --- the GitHub MCP server's write tools ------------------------------------
if [[ "$TOOL_NAME" == mcp__* ]]; then
  # hooks.json names the tools; any other MCP payload that reaches here has no
  # body to post.
  jq_rc=0
  hook::jq_fields "$INPUT" '.tool_input.body' '.tool_input.comments' || jq_rc=$?
  if ((jq_rc == 2)); then
    guard::refuse_unparsable
    exit 2
  fi
  ((jq_rc != 0)) && exit 0
  if ((HOOK_JQ_FIELDS_NUL)); then
    guard::refuse_nul
    exit 2
  fi
  for _bfr_t in "${HOOK_JQ_FIELDS[@]}"; do
    _bfr_carries "$_bfr_t" && block "${TOOL_NAME##*__}"
  done
  emit_tel ok ""
  exit 0
fi

[[ -n "$COMMAND" ]] || exit 0
_bfr_lc="${COMMAND,,}"
# Past the row's shared ceiling the command is not parsed; one that names the
# phrase is refused unread.
MAX_COMMAND_LEN=16384
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  [[ "$_bfr_lc" == *"$_BFR_PHRASE"* ]] && block "too-long"
  exit 0
fi
# Cheap pre-filter: a post names the phrase (quotes and escapes aside), or names
# gh or curl with a way to read a body from elsewhere.
_bfr_flat="${_bfr_lc//[\\\'\"]/}"
if [[ "$_bfr_flat" != *"pr-fix lane"* && "$_bfr_flat" != *pr-fix%20lane* && "$_bfr_flat" != *pr-fix+lane* ]]; then
  _bfr_re_cli='(^|[^a-z0-9_.-])(gh|curl)(\.exe)?([^a-z0-9_-]|$)'
  [[ "$_bfr_lc" =~ $_bfr_re_cli ]] || exit 0
  [[ "$_bfr_lc" == *@* || "$_bfr_lc" == *-f* || "$_bfr_lc" == *--input* || "$_bfr_lc" == *'<'* || "$_bfr_lc" == *cat* ]] || exit 0
fi

ghpost::collect "$COMMAND" "$_BFR_CWD" "$TOOL_NAME"
if [[ -z "$GHPOST_POST" ]]; then
  emit_tel ok ""
  exit 0
fi

# Every text the post carries (ghpost::bodies says which, and when the whole
# command counts), in the order the library gives.
ghpost::bodies
for _bfr_i in "${!GHPOST_BODY[@]}"; do
  _bfr_carries "${GHPOST_BODY[_bfr_i]}" &&
    block "$GHPOST_POST${GHPOST_BODY_SRC[_bfr_i]:+, from ${GHPOST_BODY_SRC[_bfr_i]}}"
done
emit_tel ok ""
exit 0
