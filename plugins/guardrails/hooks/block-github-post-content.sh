#!/usr/bin/env bash
# PreToolUse hook: block a Bash or PowerShell command that posts a secret or a
# machine-specific path to GitHub.
#
# WHY. secret-pattern-detection and hardcoded-path-check scan Write, Edit and
# the GitHub MCP file writes. A `gh pr comment --body ...`, a writing `gh api`
# or a curl POST to the GitHub API run through Bash posts its body publicly
# with neither scan. This guard runs the same two pattern sets over what such
# a command posts.
#
# WHAT IS READ. The bodies lib/github-post/github-post-body.sh finds, which
# block-fix-request-post reads too: the posting command's words, its body
# files (`--body-file`, `-F`, `--input`, `@file`), and in the cases that
# library names, the whole command, here-strings and files fed through `cat`
# or `<`. A script wrapper's command after `--` (`bash gate.sh run KEY --
# gh ...`, split on `+++`) and `bash -c`/`eval` operands are read as commands.
#
# SECRETS. lib/secret-detection/secret-patterns.sh over every body text. A hit
# blocks, naming the pattern class only, never the value.
#
# MACHINE PATHS. lib/path-detection/hardcoded-path-patterns.sh, blocking as
# hardcoded-path-check's GitHub MCP lane does, with the same scan root. Read
# over body files, here-doc and here-string bodies, and the posting command's
# words with every file path it names removed, so a `--body-file` operand or
# the wrapper script's own path is not judged. The whole command is not read
# for paths: it names the wrapper, the working directory and the body file.
#
# STAYS QUIET on a command that posts nothing to GitHub (a `gh api` GET, a
# GraphQL query, curl to another host), whatever it names.
#
# A GitHub-hosted runner's home (the `runner` user on the Linux and macOS
# images, `runneradmin` on Windows) in a quoted CI log is not a machine path.
#
# KNOWN GAPS: block-fix-request-post's (`printf` with a computed argument, a
# script or cmdlet that posts, `xargs` and other launchers it does not step
# over, a wrapper other than a shell script with `--`, a GraphQL mutation held
# in a variable). Other publishing forms (`gh pr merge --body`, `gh release
# --notes`, `gh gist`, `--description` edits) are not read. The path check
# skips text that reaches the post only through the whole command: a body in
# a variable or piped from another command, a here-doc inside a `bash -c`
# operand, and any command past the 16384-character ceiling. A body file past
# 1 MiB is read to that point only.
#
# Escape: the `block_github_post_content_enabled` userConfig option; the
# secret_pattern_detection_enabled and hardcoded_path_check_enabled options
# turn off their half here too.
#
# BLOCKING: exits 2 on a detected post.

set -uo pipefail

# Kill switch FIRST, above every source (scripts/check-killswitch-hoist.sh).
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_GITHUB_POST_CONTENT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice, as the two Write scanners it extends.
guard::abort_boundary block-github-post-content PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
_bgpc_lib="${CLAUDE_PLUGIN_ROOT:-$_HOOK_SELF/..}/lib"
# shellcheck source=../lib/github-post/github-post-body.sh
source "$_bgpc_lib/github-post/github-post-body.sh" || exit 70
# shellcheck source=../lib/secret-detection/secret-patterns.sh
source "$_bgpc_lib/secret-detection/secret-patterns.sh" || exit 70
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
source "$_bgpc_lib/path-detection/hardcoded-path-patterns.sh" || exit 70

start=${EPOCHREALTIME:-}
_bgpc_secrets=0
_bgpc_paths=0
[[ "${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED:-true}" == true ]] && _bgpc_secrets=1
[[ "${CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED:-true}" == true ]] && _bgpc_paths=1
((_bgpc_secrets || _bgpc_paths)) || exit 0

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
hook::require_jq_blocking "guardrails-block-github-post-content" "block_github_post_content_enabled"

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
_BGPC_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"
[[ -n "$COMMAND" ]] || exit 0

# Cheap pre-filter: every post names gh or curl.
_bgpc_re_cli='(^|[^a-z0-9_.-])(gh|curl)(\.exe)?([^a-z0-9_-]|$)'
[[ "${COMMAND,,}" =~ $_bgpc_re_cli ]] || exit 0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2" check "$3"
  hook::emit_telemetry "block-github-post-content" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# block_secret <form> <labels>
block_secret() {
  printf '%s\n' \
    "BLOCKED: this command would post a secret/credential pattern to GitHub ($1): $2." \
    "GitHub bodies are public and cannot be unposted cleanly. Remove the value from the body; never paste a token into a comment, PR or API call." >&2
  emit_tel blocked "$1" secret
  exit 2
}

# Past the row's shared ceiling the command is not parsed; one holding a secret
# is refused unread.
MAX_COMMAND_LEN=16384
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  ((_bgpc_secrets)) && secrets::any_match "$COMMAND" && block_secret "too-long" "a secret pattern"
  exit 0
fi

ghpost::collect "$COMMAND" "$_BGPC_CWD" "$TOOL_NAME"
if [[ -z "$GHPOST_POST" ]]; then
  emit_tel ok "" ""
  exit 0
fi
ghpost::bodies
ghpost::heredocs

if ((_bgpc_secrets)); then
  _bgpc_labels=""
  _bgpc_hit=0
  for _bgpc_t in ${GHPOST_BODY[@]+"${GHPOST_BODY[@]}"} ${GHPOST_HEREDOCS[@]+"${GHPOST_HEREDOCS[@]}"}; do
    secrets::any_match "$_bgpc_t" || continue
    _bgpc_hit=1
    while IFS= read -r _bgpc_l; do
      _bgpc_l="${_bgpc_l%% (line *}"
      [[ -n "$_bgpc_l" && ", $_bgpc_labels, " != *", $_bgpc_l, "* ]] && _bgpc_labels+="${_bgpc_labels:+, }$_bgpc_l"
    done < <(secrets::scan_text "$_bgpc_t")
  done
  ((_bgpc_hit)) && block_secret "$GHPOST_POST" "${_bgpc_labels:-a secret pattern}"
fi

if ((_bgpc_paths)); then
  hpp::resolve_scan_root "${CLAUDE_PROJECT_DIR:-}"
  _bgpc_viol=""
  _bgpc_texts=()
  for _bgpc_i in "${!GHPOST_BODY[@]}"; do
    _bgpc_t="${GHPOST_BODY[_bgpc_i]}"
    case "${GHPOST_BODY_KIND[_bgpc_i]}" in
    command) continue ;;
    word)
      for _bgpc_f in ${GHPOST_PATHS[@]+"${GHPOST_PATHS[@]}"}; do
        _bgpc_t="${_bgpc_t//"$_bgpc_f"/}"
      done
      ;;
    *) ;;
    esac
    _bgpc_texts+=("$_bgpc_t")
  done
  for _bgpc_t in ${_bgpc_texts[@]+"${_bgpc_texts[@]}"} ${GHPOST_HEREDOCS[@]+"${GHPOST_HEREDOCS[@]}"}; do
    # A GitHub-hosted runner's home in a quoted CI log names no machine of
    # ours (the runner user on Linux, macOS and Windows images).
    _bgpc_t="${_bgpc_t//\/home\/runner\//<runner>/}"
    _bgpc_t="${_bgpc_t//\/Users\/runner\//<runner>/}"
    _bgpc_t="${_bgpc_t//Users\\runneradmin\\/<runner>\\}"
    _bgpc_t="${_bgpc_t//Users\/runneradmin\//<runner>/}"
    hpp::prefilter "$_bgpc_t" "$SCAN_ROOT"
    [[ "$HPP_GATE" == clean ]] && continue
    _bgpc_out=$(
      hpp::scan_text "$_bgpc_t" "$SCAN_ROOT" ""
      printf x
    )
    _bgpc_viol+="${_bgpc_out%x}"
  done
  if [[ -n "$_bgpc_viol" ]]; then
    {
      printf 'BLOCKED: this command would post hardcoded machine-specific path(s) to GitHub (%s):\n\n' "$GHPOST_POST"
      while IFS= read -r _bgpc_l || [[ -n "$_bgpc_l" ]]; do
        ((${#_bgpc_l} > 160)) && _bgpc_l="${_bgpc_l:0:157}..."
        printf '%s\n' "$_bgpc_l"
      done < <(printf '%s' "$_bgpc_viol")
      # shellcheck disable=SC2016  # the `$` spellings are literal advice, not expansions
      printf 'Use portable alternatives: ~/, $HOME, a repo-relative path, or <placeholder> notation.\n'
    } >&2
    emit_tel blocked "$GHPOST_POST" path
    exit 2
  fi
fi

emit_tel ok "$GHPOST_POST" ""
exit 0
