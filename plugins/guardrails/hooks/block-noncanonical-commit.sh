#!/usr/bin/env bash
# PreToolUse hook: block `git commit` that does not feed its message via stdin.
# Triggered on Bash tool calls.
#
# WHAT IT ENFORCES — the mechanic, not the ritual:
#   `git commit -F -` (or `--file -`), the form the /commit skill emits. The
#   failure mode it prevents is real and silent: `git commit -m "<multi-line>"`
#   flattens newlines unpredictably across shells, so a body that looked right
#   in the tool call lands mangled in history.
#
# WHY NOT `--trailer`: the trailer is POLICY, not mechanic. /commit itself
# omits it when the resolved trailer_policy is `none`, and a repo whose
# convention forbids a co-author trailer is a documented, supported case.
# Gating on it would permanently block the skill's own canonical output in that
# configuration. Only the stdin form belongs in a gate.
#
# WHY NOT "did you type /commit": a hook cannot tell a skill-driven Bash call
# from an ad hoc one — the payload carries no originating-skill field, and the
# upstream request to add one was declined. Gating on command SHAPE is what is
# actually available, and is the better target anyway: it enforces the outcome
# a reviewer can verify in `git log`, not the ceremony that produced it.
#
# NOT BLOCKED (no message-on-stdin form exists for these, and gating them would
# break conflict resolution and history rewriting):
#   --amend                      reusing an existing message
#     (--no-edit alone is NOT exempt: `git commit --no-edit -m x` is an
#      ordinary commit. Amending is covered by --amend; a merge's --no-edit is
#      covered by the sequencer branch.)
#   -C / --reuse-message         "
#   -c / --reedit-message        "
#   --fixup / --squash           message derived from another commit
#   -F <path> / --file <path>    mechanic satisfied, just not via stdin
#   -m during an in-progress sequencer (merge / rebase / cherry-pick / revert):
#                                conflict resolution and rebase continuation
#                                must never be gated
#
# Per-repo/per-user allow-list: the `block_noncanonical_commit_allow` userConfig
# option is a comma-separated list of form tokens (currently just
# "message-flag", which allows a bare `-m`). Set it with
# `/plugin configure guardrails` or headless via `claude plugin install
# --config`; read from the CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW
# process mirror. Kill switch: `block_noncanonical_commit_enabled` set to false.
#
# Detection is ARGV-GRAMMAR-FAITHFUL via the shared parser in hook-utils.sh, so
# a commit body merely MENTIONING `git commit -m` never fires, and `bash -lc`
# wrappers plus git aliases are resolved — inline `-c` (last value wins, as git
# does) and aliases persisted in git config.
#
# RESIDUAL: `--config-env=alias.X=VAR` is not resolved. The shared parser stores
# its value undifferentiated from `-c`, so the environment VARIABLE NAME reaches
# this code in place of the expansion, and separating them needs a hook-utils
# change that block-dangerous-git shares. Static matching over the literal
# command string only: shell variable / command substitution is not evaluated.
# This is a friction guard against the accidental anti-pattern, not a sandbox.
#
# BLOCKING: exits 2 when a commit would take its message off the command line.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_NONCANONICAL_COMMIT"

# Bundled PowerShell-command classifier — the git guards are matched on both the
# Bash and the (opt-in) PowerShell tool, whose command arrives in the same
# tool_input.command field with PowerShell grammar. Resolved under the plugin
# root (CC sets CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract
# tests working when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/powershell/ps-command.sh
source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips; rc 2 (read timed out before a complete payload) FAILS
# CLOSED — the guard cannot evaluate the tool call, and a silent skip would pass
# exactly the traffic this guard exists to stop. Buffering does not require jq
# (hook::buffer_stdin's own JSON-completeness check is jq-optional), so it runs
# before the jq gate below — hook::require_jq needs the buffered input for its
# once-per-session notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-block-noncanonical-commit" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Bash"' 2>/dev/null | tr -d '\r')

SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-noncanonical-commit" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the block_noncanonical_commit_allow userConfig comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW:-},"
  [[ "$list" == *,"$tok",* ]]
}

# Effective repo directory for a segment: the hook payload's cwd, with any
# `git -C <path>` applied (last wins, relative joined onto cwd). Without this a
# conflict resolution driven at another repo via `-C` reads the WRONG repo's
# state — the sequencer probe and the alias lookup would both answer for the
# session cwd instead of the repo actually being committed to.
# Value of an explicit `--git-dir` (attached or separated), empty when absent.
# A commit driven with --git-dir concludes a sequencer in THAT git dir, so
# probing the cwd's state would refuse to exempt a real in-progress merge.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
explicit_git_dir() {
  local i n=$# arg
  local -a a=("$@")
  for ((i = 0; i < n; i++)); do
    arg="${a[i]}"
    case "$arg" in
    --git-dir)
      ((i + 1 < n)) && printf '%s' "${a[i + 1]}"
      return 0
      ;;
    --git-dir=*)
      printf '%s' "${arg#--git-dir=}"
      return 0
      ;;
    *) ;;
    esac
  done
}

# Canonical identity of the repository a composed `-C` path lands in, as GIT
# resolves it. This guard does not model git's path semantics anywhere — it asks
# git, because every attempt to model them has been a bypass:
#
#   - Lexically cancelling `x/..` is wrong when `x` is a symlink: on a POSIX host
#     `git -C link/.. …` enters the symlink's parent, not the textual one.
#   - Resolving PHYSICALLY instead (`cd -P` + `pwd -P`) is equally a model, and a
#     wrong one on Windows: verified on git 2.54.0.windows.1, `cd -P link/..`
#     reports the link target's parent while `git -C link/..` reports "not a git
#     repository" — Win32 normalizes `..` textually, so git itself is lexical
#     there. A shell resolver would send the guard to a repository git never
#     enters, which is the same defect wearing the opposite bias.
#
# `rev-parse --show-toplevel` is git's own answer on whatever platform, so it
# cannot drift from git's behavior by construction. It also canonicalizes for
# free: `-C .`, `link/..`, a subdirectory, and any other spelling of one
# repository all collapse to a single identity, which is what lets the
# shell-alias cycle key below detect a repeat instead of walking forever.
#
# Empty means git could not answer — no such directory, or no work tree. Callers
# on the alias-walk path FAIL CLOSED on empty: a guard that cannot determine
# which repository a command will execute in must not allow it. Nothing off that
# path calls this, so an ordinary `git commit -F -` never pays a fork.
#
# Cached per literal path (the fork is the expensive step, and a static guard
# never moves a repository mid-analysis). Published in a global and assigned by a
# PLAIN call, never `$(…)`: a command substitution would run it in a subshell and
# discard the cache.
declare -A _repo_identity=()
HOOK_REPO_IDENTITY=""
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_identity() {
  local dir="$1"
  [[ -n "${_repo_identity[$dir]+x}" ]] ||
    _repo_identity["$dir"]=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  HOOK_REPO_IDENTITY="${_repo_identity[$dir]}"
  [[ -n "$HOOK_REPO_IDENTITY" ]]
}

# The base is HOOK_EFFECTIVE_BASE, not the payload cwd directly, because a `!`
# shell alias's body runs as a NEW git invocation from the repository the OUTER
# one resolved — so a relative `-C` in that body composes onto the parent's
# directory instead of restarting from the session cwd. Resetting to the payload
# cwd at every hop made the walk stand still: `alias.a = !git -C child a` in a
# repo and its child resolved to the same directory twice, the second hop read as
# a self-cycle, and the grandchild's `commit -m` was never reached while real git
# committed there. HOOK_EFFECTIVE_BASE is save/restored around each `!` reparse.
#
# The base a `!` reparse inherits is the outer repository's TOP LEVEL, which is
# where git documents it runs a shell body from — not the directory the outer
# command was invoked in. Invoked from `<repo>/sub` with `alias.a = !git -C child
# a`, git reaches `<repo>/child`; carrying the subdirectory forward made the guard
# probe `<repo>/sub/child` and miss the nested repository's `commit -m` entirely.
# repo_identity supplies that top level from git itself.
#
# What this function returns is a LITERAL composed path, deliberately not a
# resolved one: it is handed straight to `git -C`, so git applies its own path
# semantics to it. The guard never normalizes it (see repo_identity).
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
effective_dir() {
  local base="${HOOK_EFFECTIVE_BASE:-${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}}" i n=$# arg
  local -a a=("$@")
  for ((i = 0; i < n; i++)); do
    arg="${a[i]}"
    if [[ "$arg" == "-C" ]] && ((i + 1 < n)); then
      if [[ "${a[i + 1]}" == /* || "${a[i + 1]}" =~ ^[A-Za-z]:[\/] ]]; then
        base="${a[i + 1]}"
      else
        base="$base/${a[i + 1]}"
      fi
      ((i++))
    fi
  done
  printf '%s' "$base"
}

# Is a merge / rebase / cherry-pick / revert in progress? Those commits carry a
# prepared message git supplies, and `git commit` there is the documented way to
# conclude the operation — gating it would strand a conflict resolution
# mid-flight. Unknown git state answers "no": this is the permissive branch, so
# an uncertain answer must not silently open the gate.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir f repo="$1" explicit="$2"
  if [[ -n "$explicit" ]]; then
    # An explicit --git-dir names the git dir outright; asking git to resolve it
    # would just echo it back, and `-C` may point somewhere unrelated.
    dir="$explicit"
    [[ "$dir" == /* || "$dir" =~ ^[A-Za-z]:[\/] ]] || dir="$repo/$dir"
  else
    # --absolute-git-dir, not --git-dir: the latter answers relative to the repo,
    # which would resolve against the HOOK's cwd here and silently miss every
    # sequencer file.
    dir=$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  fi
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

# Resolved persisted alias for a subcommand, cached per (directory, subcommand).
# The lookup forks a `git config`, by far the costliest step on the re-expansion
# path, and this guard never writes config — so the answer for a given directory
# and name cannot change mid-analysis and one fork per analysis path is waste.
# The result is published in a global and assigned by a PLAIN call, never through
# `$(…)`: a command substitution would run this in a subshell and discard the
# cache with it.
declare -A _persisted_alias=()
HOOK_PERSISTED_ALIAS=""
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
persisted_alias() {
  local dir="$1" sub="$2" key
  key="$dir"$'\n'"$sub"
  [[ -n "${_persisted_alias[$key]+x}" ]] ||
    _persisted_alias["$key"]=$(git -C "$dir" config --get "alias.$sub" 2>/dev/null)
  HOOK_PERSISTED_ALIAS="${_persisted_alias[$key]}"
}

# Fail closed when git cannot say which repository a `!` body will run in. Only
# the alias-walk reaches here — a plain `git commit -F -` resolves no path and can
# never trip it — so the cost is narrow: an aliased git command invoked where there
# is no work tree (or no such directory) now blocks instead of being waved through
# on a guessed directory. A commit could not have succeeded there anyway, and a
# guard that cannot determine where a command executes must not allow it.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block_unresolvable_dir() {
  echo "BLOCKED: cannot determine which repository this git alias would run in ('$1' is not a work tree git can resolve) — failing closed rather than guessing." >&2
  echo "Run the subcommand directly, invoke it from inside the intended repository, or set the guardrails block_noncanonical_commit_enabled option to false to bypass." >&2
  emit_tel "blocked" "unresolvable-alias-dir"
  exit 2
}

# Alias re-expansion is this guard's only recursive path, and it BRANCHES: every
# hop re-checks both alias spellings (`alias.<sub>` and `alias.<sub>.command`)
# independently, so a chain where each hop defines both walks 2^depth analysis
# paths — a benign 8-hop, 356-character command measured 14.6s, and a guard that
# stalls stops guarding. Every recursion is admitted through this one gate, which
# applies two bounds:
#
# MEMO — a verdict is a pure function of (analysis state, argv). Every other input
# is invocation-constant: the payload's command and cwd, and the on-disk config and
# sequencer state, which this static guard only ever reads (effective_dir and
# explicit_git_dir derive their answers from the argv alone). A block is a
# process-wide `exit 2`, so a state reached a SECOND time while this process still
# runs provably did not block the first time and cannot decide differently now.
# Skipping the repeat is exact rather than a coverage trade, and it is what
# collapses the common blowup — both spellings of a hop expanding to the same
# thing — to one path per hop.
#
# BUDGET — memoization alone cannot bound a chain whose two spellings DIFFER: the
# splice carries each path's own trailing text forward, so every argv is distinct
# and the 2^depth walk survives. A total re-expansion budget for the invocation
# caps the work, and exhausting it fails CLOSED — the guard could not finish
# deciding, so it must not allow.
#
# The ceiling counts ANALYSES rather than seconds, because a wall clock is
# host- and command-length-dependent. It is calibrated against the linear walk the
# guard already accepts: a memoized traversal spends one analysis per hop, and a
# 60-hop chain measured ~0.5s of guard work here, so this ceiling caps a branching
# walk at the same order as a chain twice that long. It sits far above real usage —
# a chain deeper than a couple of hops is already exotic, and every legitimate
# command measured spends single digits.
HOOK_ALIAS_WORK_MAX=128

# Call as: alias_reexpand_admit <kind> <state-word>... — returns 1 when this exact
# state was already analyzed. The kind tag keeps a `!` reparse STRING from ever
# keying the same as a one-word argv, `%q` keeps a word containing a newline from
# merging into its neighbour, and each seen-set's length prefixes its own words so
# no boundary in the key can shift. Both seen-sets are keyed at every call, even
# where the persisted branch cannot run, so the key shape is uniform.
# `printf -v` keeps the whole key build fork-free — a `$(printf …)` per word would
# cost more than the walk it bounds.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
alias_reexpand_admit() {
  local kind="$1" key q w
  shift
  # The effective base belongs in the key for the same reason it belongs in the
  # shell-alias cycle key: one reparse STRING reached in two different
  # repositories is two different analyses, and collapsing them would skip one.
  printf -v q '%q' "${HOOK_EFFECTIVE_BASE-}"
  key="$kind"$'\n'"$q"$'\n'"${#HOOK_ALIAS_SEEN[@]}"$'\n'"${#HOOK_SHELL_ALIAS_SEEN[@]}"$'\n'
  for w in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"} \
    ${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"} "$@"; do
    printf -v q '%q' "$w"
    key+="$q"$'\n'
  done
  [[ -n "${HOOK_ALIAS_MEMO[$key]+x}" ]] && return 1
  HOOK_ALIAS_MEMO["$key"]=1
  ((++HOOK_ALIAS_WORK <= HOOK_ALIAS_WORK_MAX)) && return 0
  echo "BLOCKED: checking this command's git alias chain needs more than $HOOK_ALIAS_WORK_MAX re-expansions — failing closed rather than stalling the guard." >&2
  echo "Commit with \`git commit -F -\` (or the /commit skill), shorten the alias chain, or set the guardrails block_noncanonical_commit_enabled option to false to bypass." >&2
  emit_tel "blocked" "alias-traversal-cap"
  exit 2
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0 saw_commit=0
  local inline_alias_handled=0
  # This segment's effective repo directory, resolved at most once per frame and
  # only where a path is actually needed — a segment carrying no alias and no
  # commit must not pay effective_dir's subshell.
  local seg_dir=""

  # A shell -c wrapper (`bash -lc 'git commit -m x'`) executes its operand as a
  # full shell command — re-parse it with the same tokenizer.
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX

  # An inline alias runs its expansion (`git -c alias.c=commit c -m x` commits),
  # so re-check the expanded command BEFORE concluding the subcommand is not
  # `commit` — otherwise the alias name is simply not "commit" and the guard
  # waves it through. A shell alias (leading !) re-parses as a full shell
  # command; a git alias splices its words in place of the alias name.
  # The --config-env SHAPE refusal is value-blind, terminal, and must fire at EVERY
  # recursion depth: a wrapping inline alias can expand to `--config-env=alias.<sub>=…`
  # that defines the invoked subcommand (`git -c alias.c='--config-env=alias.foo=AV foo'
  # c`), which git runs.
  # git DOES chain aliases (an expansion whose first word is another alias is
  # expanded again), so both the inline re-expansion and the gitconfig-alias probe
  # below recurse at EVERY hop, carrying the command-line -c/--config/--config-env
  # globals through each hop (the splice keeps indices 0..sub_idx, not gi+1),
  # TERMINATING on HOOK_ALIAS_SEEN — a save/restore seen-set of resolved subcommand
  # names: a repeat is git's own alias-loop stop (runs nothing, allow-safe), and
  # finite distinct alias keys guarantee termination. Terminating is not the same as
  # tractable — the walk branches per hop, and alias_reexpand_admit is what keeps
  # its cost proportional to the chain's length.
  local exp reparse a alias_rc s seen_hit=0 saved_base=""
  local -a expw=() saved_seen=() saved_shell_seen=() nextw=()
  hook::git_alias_expansion "$sub"
  alias_rc=$?
  if ((alias_rc == 2)); then
    # Structural fail-closed: the invoked subcommand's alias is defined via --config-env
    # (here or in a wrapping alias's expansion), whose value is the recurring fail-open
    # surface (fed by an ambient var, an inline/`env` prefix, an `export`, `set -a`, or a
    # nested `bash -c` in any wrapper); a commit smuggled through it cannot be verified,
    # and defining an alias this way on a guarded invocation is never canonical.
    echo "BLOCKED: git alias '$sub' is defined via --config-env, so its expansion cannot be verified — failing closed." >&2
    echo "Commit with \`git commit -F -\` (or the /commit skill), define aliases in git config, or set the guardrails block_noncanonical_commit_enabled option to false to bypass." >&2
    emit_tel "blocked" "config-env-alias"
    exit 2
  fi
  # git stops (runs nothing) if the resolved subcommand is one it already expanded
  # in this chain, so skip the re-expansion on a repeat and let the plain scan
  # decide. Save/restore the seen-sets around BOTH branches so sibling segments
  # and unwound hops start clean. The set models git's IN-PROCESS alias-loop
  # guard only: a `!` shell alias spawns a fresh git process whose loop guard
  # starts empty, so its reparses below run under an emptied set.
  for s in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"}; do
    [[ "$s" == "$sub" ]] && {
      seen_hit=1
      break
    }
  done
  if ((seen_hit == 0)); then
    saved_seen=(${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"})
    saved_shell_seen=(${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"})
    saved_base="${HOOK_EFFECTIVE_BASE-}"
    HOOK_ALIAS_SEEN+=("$sub")
    if ((alias_rc == 0)); then
      # Inline alias (-c/--config): each spelling's expansion is literally present. Re-check
      # EVERY spelling (plain and `.command`) independently so a benign expansion in one
      # never suppresses a dangerous sibling in the other. Keep every command-line global
      # (indices 0..sub_idx) so a nested hop re-reads the carried -c/--config-env config.
      # shellcheck disable=SC2154  # HOOK_GIT_ALIAS_EXPS is set by hook::git_alias_expansion
      for exp in ${HOOK_GIT_ALIAS_EXPS[@]+"${HOOK_GIT_ALIAS_EXPS[@]}"}; do
        [[ -n "$exp" ]] || continue
        inline_alias_handled=1
        if [[ "$exp" == '!'* ]]; then
          # Shell alias: runs in a NEW git process whose alias-loop guard starts
          # empty, so the reparse must not inherit this chain's seen-set — a
          # body that re-invokes a name from the outer chain (`git -c
          # alias.a='!git -c alias.a="commit -m x" a' a`) is re-expanded there,
          # not stopped. Termination stays bounded: every inline definition
          # reachable from the reparse is a strict substring of the parent
          # segment's text, and persisted-config shell hops are bounded by
          # HOOK_SHELL_ALIAS_SEEN below. That new process also starts from THIS
          # segment's repository, so the body's relative `-C` composes onto it.
          reparse="${exp#!}"
          for a in "${w[@]:sub_idx+1}"; do reparse+=" $(printf '%q' "$a")"; done
          [[ -n "$seg_dir" ]] || seg_dir="$(effective_dir "${w[@]}")"
          repo_identity "$seg_dir" || block_unresolvable_dir "$seg_dir"
          HOOK_ALIAS_SEEN=()
          HOOK_EFFECTIVE_BASE="$HOOK_REPO_IDENTITY"
          alias_reexpand_admit shell "$reparse" &&
            hook::bash_parse_segments "$reparse" check_segment
          HOOK_EFFECTIVE_BASE="$saved_base"
          HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"} "$sub")
        else
          hook::env_s_split "$exp"
          expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          nextw=("${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}")
          alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
        fi
      done
    fi

    # An alias can also live in .git/config, ~/.gitconfig, or system config,
    # where HOOK_GIT_CONFIG_VALUES cannot see it — `git config alias.c commit`
    # then `git c -m x` would otherwise pass. Ask git for the resolved value
    # (its own precedence applies) only when no inline alias already matched.
    if ((inline_alias_handled == 0)) && [[ "$sub" != "commit" ]]; then
      local pexp
      [[ -n "$seg_dir" ]] || seg_dir="$(effective_dir "${w[@]}")"
      persisted_alias "$seg_dir" "$sub"
      pexp="$HOOK_PERSISTED_ALIAS"
      if [[ -n "$pexp" ]]; then
        if [[ "$pexp" == '!'* ]]; then
          # Persisted shell alias: same fresh-process semantics as the inline
          # `!` branch — reparse under an emptied git-alias seen-set. Unlike
          # inline definitions, a persisted body does not shrink (it re-reads
          # the same config value at every hop), so a self- or mutually
          # referential persisted shell alias (`a = !git a`) would recurse
          # forever here. Real git forks such a chain endlessly and never
          # reaches a subcommand, so a REPEAT of the same persisted
          # name/expansion pair on this analysis path is skipped (allow-safe):
          # HOOK_SHELL_ALIAS_SEEN, save/restored alongside HOOK_ALIAS_SEEN so
          # sibling segments and unwound hops start clean, bounds the depth.
          #
          # The REPOSITORY is part of that pair, not just the name and expansion.
          # One alias text can appear in nested repos and mean a different hop in
          # each: `alias.a = !git -C child a` in a repo and its child descends
          # further every time, and keying on the text alone read the second hop
          # as a self-cycle — the grandchild's `commit -m` was never analyzed
          # while real git committed there. Composing directories (effective_dir
          # above) makes each hop's key distinct, so descent is followed; a body
          # with no `-C` leaves the directory unchanged, which is what still
          # stops `a = !git a` on the first repeat. A body that keeps rewriting
          # the directory forever (`-C .`) never repeats a key, so termination
          # there rests on the fail-closed traversal budget, not on this set.
          local pkey pseen_hit=0
          repo_identity "$seg_dir" || block_unresolvable_dir "$seg_dir"
          pkey="$HOOK_REPO_IDENTITY"$'\n'"$sub="$'\n'"$pexp"
          for s in ${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"}; do
            [[ "$s" == "$pkey" ]] && {
              pseen_hit=1
              break
            }
          done
          if ((pseen_hit == 0)); then
            HOOK_SHELL_ALIAS_SEEN+=("$pkey")
            local preparse pa
            preparse="${pexp#!}"
            for pa in "${w[@]:sub_idx+1}"; do preparse+=" $(printf '%q' "$pa")"; done
            HOOK_ALIAS_SEEN=()
            HOOK_EFFECTIVE_BASE="$HOOK_REPO_IDENTITY"
            alias_reexpand_admit shell "$preparse" &&
              hook::bash_parse_segments "$preparse" check_segment
            HOOK_EFFECTIVE_BASE="$saved_base"
            HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"} "$sub")
          fi
        else
          local -a pexpw=()
          hook::env_s_split "$pexp"
          pexpw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          nextw=("${w[@]:0:sub_idx}" ${pexpw[@]+"${pexpw[@]}"} "${w[@]:sub_idx+1}")
          alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
        fi
      fi
    fi
    HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"})
    HOOK_SHELL_ALIAS_SEEN=(${saved_shell_seen[@]+"${saved_shell_seen[@]}"})
    HOOK_EFFECTIVE_BASE="$saved_base"
  fi

  [[ "$sub" == "commit" ]] || return 0
  saw_commit=1

  # Scan only the words AFTER the subcommand: a top-level `git -c foo=bar` is
  # config, while `-c` after `commit` is --reedit-message.
  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --)
      break
      ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-)
      stdin_form=1
      ;;
    --file=*)
      exempt=1
      ;;
    -F*)
      exempt=1
      ;;
    --amend | --fixup | --squash | -C | -c | --reuse-message | --reedit-message)
      exempt=1
      ;;
    --fixup=* | --squash=* | --reuse-message=* | --reedit-message=*)
      exempt=1
      ;;
    -C* | -c*)
      exempt=1
      ;;
    *)
      # Any other word (paths, -a, -S, --cleanup, the -m payload) is not a
      # message-source marker and needs no handling here.
      ;;
    esac
  done

  ((saw_commit)) || return 0
  ((stdin_form || exempt)) && return 0
  allowed "message-flag" && return 0
  [[ -n "$seg_dir" ]] || seg_dir="$(effective_dir "${w[@]}")"
  sequencer_in_progress "$seg_dir" "$(explicit_git_dir "${w[@]}")" && return 0

  echo "BLOCKED: \`git commit\` without \`-F -\` — the message must be piped via stdin." >&2
  echo "Use the /commit skill (source-control plugin), or its canonical form directly:" >&2
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    echo "  @'" >&2
    echo "  <subject>" >&2
    echo "  '@ | git commit -F -" >&2
  else
    echo "  git commit -F - --cleanup=verbatim <<'EOF'" >&2
    echo "  <subject>" >&2
    echo "  EOF" >&2
  fi
  echo "A \`-m\` message flattens newlines unpredictably across shells. --amend, -C/-c," >&2
  echo "--fixup/--squash, -F <path>, and an in-progress merge/rebase are exempt." >&2
  emit_tel "blocked" "message-flag"
  exit 2
}

# Reduce a PowerShell command to a Bash-tokenizer-faithful form, or fail closed.
# For the Bash tool this is a no-op (COMMAND unchanged). The canonical PowerShell
# commit form (a here-string piped to `git commit -F -`) reduces to
# `<placeholder> | git commit -F -`, which the parser below recognizes as the
# stdin form and allows.
ps::classify_git_command "$TOOL_NAME" "$COMMAND"
case $? in
2)
  ps::print_unparsable_block_message
  emit_tel "blocked" "powershell-unparsable"
  exit 2
  ;;
1) exit 0 ;; # non-commit PowerShell with an A2b-deferred construct
*) COMMAND="$PS_SAFE_COMMAND" ;;
esac

# Resolved-subcommand names already expanded in the CURRENT alias chain — git's
# own alias-loop guard. Initialized here (not in check_segment, which recurses
# and would reset it) and save/restored around each recursion; a multi-command
# line runs check_segment once per top-level segment, each starting from empty.
# HOOK_SHELL_ALIAS_SEEN bounds persisted-config `!` shell-alias hops (whose
# bodies never shrink) on one analysis path; same lifecycle.
HOOK_ALIAS_SEEN=()
HOOK_SHELL_ALIAS_SEEN=()

# Directory a `!` shell-alias body would run from — the payload cwd at the top
# level, then each `!` reparse's own repository as the walk descends (effective_dir).
# Save/restored alongside the seen-sets, so sibling segments start from the cwd.
HOOK_EFFECTIVE_BASE="${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}"

# The alias-traversal bounds (alias_reexpand_admit). Both are invocation-wide and
# deliberately NOT save/restored: a state analyzed anywhere is analyzed, and the
# budget bounds the whole command's work rather than one path's.
declare -A HOOK_ALIAS_MEMO=()
HOOK_ALIAS_WORK=0

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
