# shellcheck shell=bash

[[ -n "${_GUARDRAILS_GUARD_REQUIRES_LOADED:-}" ]] && return 0
_GUARDRAILS_GUARD_REQUIRES_LOADED=1

_GUARD_REQUIRES_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_GUARD_REQUIRES_DIR" == "${BASH_SOURCE[0]}" ]] && _GUARD_REQUIRES_DIR=.

# shellcheck disable=SC2034  # read by run-guards.test.sh, which checks both projections against it
declare -A GUARD_FIELDS=(
  ["run-guards.sh"]='.tool_name .tool_input.command'
  ["block-body-format-violation.sh"]='.tool_input.command .tool_name .cwd'
  ["block-cd-prefix.sh"]='.tool_input.command .tool_name .cwd'
  ["block-convention-violation.sh"]='.tool_input.command .tool_name .cwd'
  ["block-credential-read.sh"]='.tool_input.command'
  ["block-cross-domain.sh"]='.tool_input.command .tool_name .cwd'
  ["block-dangerous-git.sh"]='.tool_input.command .cwd .tool_name'
  ["block-fix-request-post.sh"]='.tool_input.command .tool_name .cwd'
  ["block-github-post-content.sh"]='.tool_input.command .tool_name .cwd'
  ["block-exported-msys-pathconv.sh"]='.tool_input.command .tool_name'
  ["block-foreground-wait.sh"]='.tool_input.command .tool_name'
  ["block-main-checkout-edit.sh"]='.tool_name .tool_input.file_path .tool_input.notebook_path'
  ["block-pr-poller.sh"]='.tool_input.command .tool_name'
  ["block-lane-pr-disable-auto.sh"]='.tool_input.command .tool_name .cwd'
  ["block-no-verify.sh"]='.tool_input.command .tool_name'
  ["block-noncanonical-commit.sh"]='.tool_input.command .cwd .tool_name'
  ["block-root-delete-target.sh"]='.tool_input.command .tool_name .cwd'
  ["merge-guard.sh"]='.tool_input.command .tool_name .cwd'
  ["block-windows-drive-tmp.sh"]='.tool_input.command .tool_name .tool_input.file_path .tool_input.notebook_path'
  ["flag-commit-pr-skill-bypass.sh"]='.tool_input.command .tool_name'
  ["cli-flag-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
  ["hardcoded-path-check.sh"]='.tool_name .tool_input.file_path .tool_input.content .tool_input.new_string .tool_input.new_source .tool_input.path .tool_input.notebook_path'
  ["secret-pattern-detection.sh"]='.tool_name .tool_input.file_path .tool_input.content .tool_input.new_string .tool_input.new_source .tool_input.path .tool_input.notebook_path'
  ["skill-reference-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
  ["stale-path-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
)

# shellcheck disable=SC2034  # read by run-guards.test.sh, which checks both projections against it
declare -A GUARD_FIELDS_UNPRIMED=(
  ["block-body-format-violation.sh"]=$'.tool_input.body\n.tool_input.owner\n.tool_input.repo\n.tool_input.method'
  ["block-fix-request-post.sh"]=$'.tool_input.body\n.tool_input.comments'
  ["block-foreground-wait.sh"]='.tool_input.run_in_background'
  ["block-pr-poller.sh"]='.tool_input.run_in_background'
  ["block-root-delete-target.sh"]='.scratchpad_dir'
  ["merge-guard.sh"]=$'.tool_input.owner\n.tool_input.repo\n.tool_input.pullNumber'
  ["hardcoded-path-check.sh"]='.tool_input.files | length'
  ["secret-pattern-detection.sh"]='.tool_input.files | length'
  ["skill-reference-verify.sh"]='.tool_input.replace_all // false | tostring'
  ["stale-path-verify.sh"]='.tool_input.replace_all // false | tostring'
)

declare -A GUARD_LIBS=(
  ["block-convention-violation.sh"]='lib/powershell/ps-command.sh'
  ["block-dangerous-git.sh"]='lib/powershell/ps-command.sh'
  ["block-no-verify.sh"]='lib/powershell/ps-command.sh'
  ["block-noncanonical-commit.sh"]='lib/powershell/ps-command.sh'
  ["merge-guard.sh"]='lib/powershell/ps-command.sh'
  ["flag-commit-pr-skill-bypass.sh"]='lib/powershell/ps-command.sh'
)

guard::require_libs() {
  local __gr_decl="${GUARD_LIBS[${1:-${BASH_SOURCE[1]##*/}}]-}"
  [[ -n "$__gr_decl" ]] || return 0
  local -a __gr_libs=()
  read -r -a __gr_libs <<<"$__gr_decl"
  local __gr_lib
  for __gr_lib in "${__gr_libs[@]}"; do
    guard::require_lib "$__gr_lib"
  done
}

declare -A _GUARD_LIB_LOADED=()
guard::require_lib() {
  [[ -n "${_GUARD_LIB_LOADED[$1]+x}" ]] && return 0
  _GUARD_LIB_LOADED[$1]=1
  # shellcheck source=../lib/powershell/ps-command.sh
  source "${CLAUDE_PLUGIN_ROOT:-$_GUARD_REQUIRES_DIR/..}/$1"
}
