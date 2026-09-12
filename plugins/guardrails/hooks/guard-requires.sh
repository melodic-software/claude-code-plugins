# shellcheck shell=bash
# What each guard CONSUMES, declared once, for both halves of the dispatch.
#
# A guard needs two things it does not produce: the payload fields it reads
# through hook::jq_fields, and — on the PowerShell lane — the ps:: classifier.
# Both are supplied per EVENT rather than per guard: hooks/run-guards.sh
# extracts every field in one jq process and loads a shared library once, and
# every guard then reads from that. Running alone, a guard satisfies the same
# declaration itself through guard::require_libs below, so the declaration —
# not the dispatcher — is what makes the guard correct.
#
# ONE DECLARATION, TWO PROJECTIONS. run-guards.sh's PRIME_FILTERS and the
# `--lib` arguments in hooks.json are projections of the tables below: the
# union of the fields, and the libraries, of the guards each hook row runs.
# run-guards.test.sh reads the declaration back against BOTH halves — against
# each guard's own hook::jq_fields calls, and against those two projections —
# so a guard that adds a field without declaring it, or declares one the
# dispatcher does not prime, fails there by name.
#
# WHY THAT CHECK EARNS ITS KEEP. The cached hook::jq_fields is all-or-nothing
# per call: ONE filter the dispatcher did not prime sends the whole call to its
# own jq process, on every payload of that lane and not only the ones the field
# belongs to. A disagreement is silent at run time and costs about 50 ms to
# 60 ms per Write and Edit on the reference host, which is why it is settled
# here rather than left to two lists kept in step by hand.

[[ -n "${_GUARDRAILS_GUARD_REQUIRES_LOADED:-}" ]] && return 0
_GUARDRAILS_GUARD_REQUIRES_LOADED=1

# This file's own directory, which is the plugin's hooks/ directory. Parameter
# expansion rather than `dirname` or `$(cd … && pwd)`: GNU Bash forks a
# subshell for every command substitution even when the body is builtins
# (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution), and on Windows Git Bash
# that fork is a process. The fallback covers a bare filename, where the strip
# is a no-op.
_GUARD_REQUIRES_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_GUARD_REQUIRES_DIR" == "${BASH_SOURCE[0]}" ]] && _GUARD_REQUIRES_DIR=.

# GUARD_FIELDS[<file>] — the jq filters this guard reads and the dispatcher
# primes. Space-separated, and every entry must be a filter the guard's source
# passes to hook::jq_fields verbatim; run-guards.test.sh compares the two. A
# filter carrying a space is declared unprimed below instead: no field worth
# priming needs one, so this table stays readable rather than carrying a record
# separator for a case it does not have.
#
# run-guards.sh appears here as a consumer in its own right: it reads
# `.tool_name` to decide whether the event needs the PowerShell classifier, and
# `.hook_event_name` to name the event in its own abort notice.
#
# shellcheck disable=SC2034  # read by run-guards.test.sh, which checks both projections against it
declare -A GUARD_FIELDS=(
  ["run-guards.sh"]='.tool_name .hook_event_name'
  ["block-convention-violation.sh"]='.tool_input.command .tool_name .cwd'
  ["block-dangerous-git.sh"]='.tool_input.command .cwd .tool_name'
  ["block-exported-msys-pathconv.sh"]='.tool_input.command .tool_name'
  ["block-hook-bypass.sh"]='.tool_input.command .tool_name .cwd'
  ["block-no-verify.sh"]='.tool_input.command .tool_name'
  ["block-noncanonical-commit.sh"]='.tool_input.command .cwd .tool_name'
  ["block-windows-drive-tmp.sh"]='.tool_input.command .tool_name .tool_input.file_path .tool_input.notebook_path'
  ["flag-commit-pr-skill-bypass.sh"]='.tool_input.command .tool_name'
  ["cli-flag-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
  ["hardcoded-path-check.sh"]='.tool_name .tool_input.file_path .tool_input.content .tool_input.new_string .tool_input.new_source .tool_input.path'
  ["secret-pattern-detection.sh"]='.tool_name .tool_input.file_path .tool_input.content .tool_input.new_string .tool_input.new_source .tool_input.path'
  ["skill-reference-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
  ["stale-path-verify.sh"]='.tool_name .tool_input.new_string .tool_input.content'
)

# GUARD_FIELDS_UNPRIMED[<file>] — filters the guard reads that the dispatcher
# deliberately does NOT prime, so a reader can tell "not primed yet" from "not
# primed on purpose". One filter per entry, verbatim (`$'…\n…'` for a guard
# with several), because these are the ones that carry spaces.
#
# `.tool_input.files | length` walks an array whose per-element filters name an
# index the dispatcher cannot know, so the call it belongs to misses the cache
# whatever is primed. `.tool_input.replace_all // false | tostring` is read by
# the two Edit verifiers on the PostToolUse lane.
#
# shellcheck disable=SC2034  # read by run-guards.test.sh, which checks both projections against it
declare -A GUARD_FIELDS_UNPRIMED=(
  ["hardcoded-path-check.sh"]='.tool_input.files | length'
  ["secret-pattern-detection.sh"]='.tool_input.files | length'
  ["skill-reference-verify.sh"]='.tool_input.replace_all // false | tostring'
  ["stale-path-verify.sh"]='.tool_input.replace_all // false | tostring'
)

# GUARD_LIBS[<file>] — plugin-relative libraries the guard calls into, loaded
# through guard::require_libs. The PowerShell classifier is ~104 KB of shell
# that decides nothing on a Bash payload, so it is loaded on the PowerShell
# lane only, and once per event rather than once per guard.
declare -A GUARD_LIBS=(
  ["block-convention-violation.sh"]='lib/powershell/ps-command.sh'
  ["block-dangerous-git.sh"]='lib/powershell/ps-command.sh'
  ["block-hook-bypass.sh"]='lib/powershell/ps-command.sh'
  ["block-no-verify.sh"]='lib/powershell/ps-command.sh'
  ["block-noncanonical-commit.sh"]='lib/powershell/ps-command.sh'
  ["flag-commit-pr-skill-bypass.sh"]='lib/powershell/ps-command.sh'
)

# guard::require_libs [<guard file name>]
#
# Load every library the named guard declared above. The name defaults to the
# calling file's own, so a guard asks for what it declared rather than
# restating a path. Under run-guards.sh the event has already loaded it and
# this decides nothing; alone, this IS the load.
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

# guard::require_lib <plugin-relative path>
#
# Load one library, once per process, under the ONE plugin-root spelling this
# plugin uses for a library. The libraries carry their own include guards, so a
# repeat `source` decides nothing — but it still opens and reads the file, and
# six guards declare the same classifier on a PowerShell event. The ledger
# below makes that one open. Subshells inherit it, so a guard the dispatcher
# sources takes the answer the event already has.
#
# `$dir/..` rather than `$(cd "$dir/.." && pwd)`: the command substitution is a
# fork on every fire where CLAUDE_PLUGIN_ROOT is unset, and `source` resolves
# the two spellings alike. Tradeoff: the kernel resolves `..` physically where
# `cd` resolved it logically, so a hooks/ directory that is itself a symlink
# out of the plugin root needs CLAUDE_PLUGIN_ROOT set. Spaces in the path and
# relative invocation are unaffected.
declare -A _GUARD_LIB_LOADED=()
guard::require_lib() {
  [[ -n "${_GUARD_LIB_LOADED[$1]+x}" ]] && return 0
  _GUARD_LIB_LOADED[$1]=1
  # shellcheck source=../lib/powershell/ps-command.sh
  source "${CLAUDE_PLUGIN_ROOT:-$_GUARD_REQUIRES_DIR/..}/$1"
}
