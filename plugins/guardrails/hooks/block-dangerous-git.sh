#!/usr/bin/env bash
# PreToolUse hook: block irreversible git operations on Bash tool calls.
#
# Default block-list is irreversible-only (form tokens):
#   push-force     — git push --force / -f / +refspec / --mirror
#   push-lease-unsafe — git push --force-with-lease leasing against something
#                    git resolves at push time, in either of the two forms
#                    git treats differently:
#                      * NO expected value (bare `--force-with-lease` or
#                        `=<refname>`) — leases against the remote-tracking
#                        ref; blocked unless --force-if-includes is present,
#                        which git documents as the mitigation for this form.
#                      * a MOVABLE `=<refname>:<expect>` — <expect> is a name
#                        git resolves at push time; blocked unconditionally,
#                        because git declares --force-if-includes a no-op
#                        alongside an explicit `:<expect>`.
#   reset-hard     — git reset --hard
#   clean-force    — git clean with a force flag (-f, -fd, -fdx, --force)
#   checkout-dot   — git checkout .  (worktree-wide discard; path-scoped is fine)
#   restore-dot    — git restore .   (worktree discard; --staged-only is fine)
#   checkout-force — git checkout -f / switch -f/--discard-changes
#
# NOT blocked: a push whose lease spellings all pin an immutable <expect> — a
# object id of the repository's own hash width, or the empty string asserting
# the ref must not exist —
# so no background fetch can satisfy the lease on the pusher's behalf; a
# no-expected-value lease paired with --force-if-includes; a lease
# cancelled by a trailing --no-force-with-lease, plain push, soft/mixed reset,
# clean -n (dry run), path-scoped checkout/restore, and `branch -D` (reflog
# recovers deleted refs, and sanctioned skill flows issue it inline).
#
# Per-repo/per-user allow-list: the guardrails `block_dangerous_git_allow`
# userConfig option is a comma-separated list of the form tokens above (e.g.
# "push-force,reset-hard"). Set it with `/plugin configure guardrails` or
# headless via `claude plugin install --config`; the hook reads it from the
# CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW process mirror. Kill switch:
# the `block_dangerous_git_enabled` userConfig option set to false.
#
# Detection is ARGV-GRAMMAR-FAITHFUL via the shared parser in hook-utils.sh —
# a quoted "git push --force" in prose never fires; `checkout .github/x` never
# matches `checkout .`. Static matching over the literal command string only:
# shell variable / command substitution is not evaluated. This is a friction
# guard against accidental destruction, not a sandbox. userConfig options are
# resolved at plugin-enable time, so an inline env prefix on the command line
# (`FOO=bar git push -f`) cannot alter this guard's behavior.
#
# BLOCKING: exits 2 on any detected form not in the allow-list.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_DANGEROUS_GIT"

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
# (empty stdin) skips like the empty-COMMAND guard below; rc 2 (read timed out
# before a complete payload) FAILS CLOSED — the guard cannot evaluate the tool
# call, and a silent skip would pass exactly the traffic this guard exists to
# stop. buffer_stdin already printed the BLOCKED reason to stderr. Buffering
# does not require jq (hook::buffer_stdin's own JSON-completeness check is
# jq-optional), so it runs before the jq gate below — hook::require_jq needs
# the buffered input for its once-per-session notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-block-dangerous-git" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Bash"' 2>/dev/null | tr -d '\r')

# Above this length the command is not parsed — a pathologically long command is
# assumed to be obfuscation and blocked FAIL-CLOSED (generous cap; real git
# commands are well under it). The linear parser keeps normal commands cheap.
MAX_COMMAND_LEN=16384

SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-dangerous-git" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the block_dangerous_git_allow userConfig comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW:-},"
  [[ "$list" == *,"$tok",* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block() {
  local form="$1" msg1="$2" msg2="$3"
  allowed "$form" && return 0
  echo "$msg1" >&2
  echo "$msg2" >&2
  emit_tel "blocked" "$form"
  exit 2
}

# Does a word match a long option or an accepted unique-prefix abbreviation of
# it? git's parse-options accepts any unambiguous prefix (gitcli(7)), so
# `reset --h` runs --hard. $1 = option name without dashes, $2 = the word,
# $3 = minimum prefix length that is unique among the subcommand's options
# (verified empirically per call site — a shorter prefix is ambiguous and git
# rejects it, so matching it would only false-block an erroring command).
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
abbrev_match() {
  local full="$1" word="$2" min="$3" p
  [[ "$word" == --* ]] || return 1
  p="${word#--}"
  [[ -n "$p" ]] || return 1
  ((${#p} >= min)) || return 1
  [[ "$full" == "$p"* ]]
}

# Does a bare word (no `=`) name a value-consuming push option, in full or
# as an accepted unique-prefix abbreviation? git push consumes the next word
# as the value for these, so the scans must skip that word — otherwise a
# `--dry-run`/`--force` sitting in the value slot is misread as a flag.
# Floors verified empirically (shortest prefix git accepts without
# "ambiguous option"): --pu (push-option), --rep (repo), --rece
# (receive-pack; --rec is ambiguous with --recurse-submodules), --e (exec).
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_push_value_opt() {
  local x="$1"
  [[ "$x" == *=* ]] && return 1
  abbrev_match "push-option" "$x" 2 || abbrev_match "repo" "$x" 3 ||
    abbrev_match "receive-pack" "$x" 4 || abbrev_match "exec" "$x" 1
}

# `--force-with-lease` and `--force-with-lease=<refname>` state no expected
# value, so git leases against the remote-tracking ref. git-push(1), "A general
# note on safety", warns that this "interacts very badly with anything that
# implicitly runs `git fetch`" and is "trivially defeated if some background
# process is updating refs in the background" — the lease passes while still
# clobbering work the pusher never saw. Only `=<refname>:<expect>` states the
# expectation explicitly (an empty <expect> means the ref must not exist, which
# is still explicit). `--force-if-includes` (git 2.30+) is git's documented
# mitigation for exactly the no-expected-value forms, and git declares it a
# no-op alongside an explicit `:<expect>`.
#
# Abbreviation floor 7: `--force`, `--force-with-lease` and `--force-if-includes`
# share the `--force` prefix, so `--force-w` / `--force-i` are the shortest
# unique spellings git accepts. A shorter `--forc` is ambiguous and git rejects
# it, which is why the exact `--force` arm needs no abbreviation handling.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_lease_opt() { abbrev_match "force-with-lease" "${1%%=*}" 7; }

# Does a lease spelling state an expectation git cannot resolve to something
# newer at push time? Only `=<refname>:<expect>` with <expect> a FULL-LENGTH
# object id qualifies, plus the empty <expect> (git: "the named ref must not
# already exist"). A symbolic name in the <expect> slot — `origin/main`,
# `refs/remotes/origin/main`, `HEAD`, `@{u}` — is resolved when the push runs,
# so a background fetch moves it first and the lease passes while clobbering
# work the pusher never saw: the exact hole the bare form has.
#
# An ABBREVIATED object id is deliberately NOT accepted. gitrevisions permits
# both ref names and unique object-id prefixes as revision syntax, and git
# resolves a word as a ref BEFORE trying it as a short object id — so a tag
# literally named `dead` beats the object whose id starts `dead`, and a short
# hex expectation is a moving target after all. Only a word of exactly the
# repository hash format's full width is unambiguously an object id.
#
# The width is the LOCAL repository's, not either width. git ignores a ref whose
# name is full-width hex for its own format, but a hex name of the OTHER width
# is an ordinary ref name it resolves normally: a 64-hex tag in a SHA-1
# repository, or a 40-hex tag in a SHA-256 one, is movable and satisfies the
# lease against whatever it points at. Accepting the union would let either
# shape through in the repository where it is a name.
#
# Width of the repository THIS PUSH will run in, which is not always the hook's
# own directory: git's repository-locating global options (`-C`, `--git-dir`,
# `--work-tree`, `--namespace`) redirect it, and a `git -C <sha256-repo> push`
# issued from a SHA-1 directory must be judged by the target's format. Those
# options are replayed verbatim onto the probe rather than modelled, so git
# resolves the repository by its own rules — including several `-C` values,
# which git applies cumulatively.
#
# `-C` takes the value as a SEPARATE word: git rejects an attached `-C<path>`
# with its usage message (verified, git 2.54.0). The walk therefore mirrors
# hook::git_resolve_subcommand's two-word consumption so the option values stay
# aligned with the words the parser skipped.
#
# 0 means "undeterminable" — no git, no repository, or a path this static guard
# cannot resolve (an unexpanded `$VAR` reaches the probe literally and simply
# fails). That fails closed.
#
# Known gap: a compound `cd <elsewhere> && git push …` pushes from a directory
# no option names, so the probe cannot see it. Resolving the cd target would
# mean evaluating arbitrary shell word expansion, which this guard deliberately
# does not do (static matching over the literal command string only). The
# residual case needs a SHA-256 repository, a lease pinned to a full-width hex
# word that is also a ref name there, and a compound cd into it.
#
# Resolved at most once per option set and only on the rare path that sees a hex
# expectation — the guard shells out nowhere else. The result is assigned by a
# plain call, never through `$(…)`: a command substitution runs the function in
# a SUBSHELL, so the cache would be discarded and a command carrying many lease
# expectations would spawn one git per expectation.
_repo_oid_width=""
_repo_oid_width_key=""
# repo_oid_width <locating-option...> — sets $_repo_oid_width.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_oid_width() {
  local key="$*"
  [[ -n "$_repo_oid_width" && "$key" == "$_repo_oid_width_key" ]] && return 0
  _repo_oid_width_key="$key"
  case "$(git "$@" rev-parse --show-object-format 2>/dev/null)" in
  sha1) _repo_oid_width=40 ;;
  sha256) _repo_oid_width=64 ;;
  *) _repo_oid_width=0 ;;
  esac
}

# Reads $git_locating_opts from the calling check_segment frame.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
lease_expect_is_immutable() {
  local expect="$1"
  [[ -z "$expect" ]] && return 0
  [[ "$expect" =~ ^[0-9a-fA-F]+$ ]] || return 1
  repo_oid_width ${git_locating_opts[@]+"${git_locating_opts[@]}"}
  ((_repo_oid_width)) && ((${#expect} == _repo_oid_width))
}

# The repository-locating subset of git's global options, collected between the
# git word and the subcommand. Two-word options whose value is consumed the same
# way hook::git_resolve_subcommand consumes it, so the walk cannot desynchronize
# from the parser's own.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
collect_git_locating_opts() {
  local gi="$1" sub_idx="$2"
  shift 2
  local -a w=("$@")
  local j=$((gi + 1))
  git_locating_opts=()
  while ((j < sub_idx)); do
    case "${w[j]}" in
    -C | --git-dir | --work-tree | --namespace)
      ((j + 1 < sub_idx)) && git_locating_opts+=("${w[j]}" "${w[j + 1]}")
      ((j += 2))
      ;;
    --git-dir=* | --work-tree=* | --namespace=*)
      git_locating_opts+=("${w[j]}")
      ((j++))
      ;;
    -c | --config | --config-env | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    *) ((j++)) ;;
    esac
  done
}

# Has an earlier lease spelling in this same command already claimed <refname>?
# git's apply_cas() walks the --force-with-lease entries in command-line order
# and RETURNS on the first whose refname matches the ref being updated, so a
# later entry for a ref an earlier one already pinned is dead text. Matching
# entries by their literal spelling is the conservative reading of git's
# refname_match(): two different spellings of one ref (`main` vs
# `refs/heads/main`) are treated as distinct here, so an unsafe later entry is
# still counted rather than silently dropped.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
lease_ref_claimed() {
  local seen="$1" ref="$2"
  [[ $'\n'"$seen" == *$'\n'"$ref"$'\n'* ]]
}

# Is an operand a worktree-wide pathspec? `.` from the repo root, the
# root-magic short form `:/` (bare or with a wildcard-only pattern — `:/*`
# and `:/?*` match the whole tree from the repository root regardless of
# cwd), long-form magic with an empty or wildcard-only pattern
# (`:(top)`, `:(literal)`, `:(glob)**` — empirically git selects the whole
# tree scope for all of them), bare/empty short magic (`:`, `::`, `:*`),
# and any bare operand built only from wildcard and dot/slash characters
# (`*`, `?*`, `./*`, `**/*`, `./`, `..`) all address the whole tree —
# git's pathspec fnmatch lets `*` cross directories and `?` match any
# character, and dot-slash-only operands are the same cwd-or-wider discard
# as `.`. Magic followed by a real path (`:(top)src/a`, `:/src`) scopes to
# it and passes, as does any pattern containing a literal name character.
# Exclude magic (`:!x`, `:^x`, `:(exclude)x`) never selects on its own —
# the operand scans track it at set level via is_exclude_pathspec.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_tree_wide_pathspec() {
  local magic pattern
  case "$1" in
  "." | ":/") return 0 ;;
  ":("*")"*)
    magic="${1#:(}"
    pattern="${magic#*)}"
    magic="${magic%%)*}"
    [[ ",${magic}," == *",exclude,"* ]] && return 1
    [[ -z "$pattern" || "$pattern" =~ ^[./*?]+$ ]]
    ;;
  ":/"*)
    [[ "${1#:/}" =~ ^[./*?]+$ ]]
    ;;
  ":!"* | ":^"*) return 1 ;;
  ":"*)
    [[ "${1#:}" =~ ^:?[./*?]*$ ]]
    ;;
  *)
    [[ "$1" =~ ^[./*?]+$ ]]
    ;;
  esac
}

# Is an operand an exclude-magic pathspec (`:!x`, `:^x`, `:(exclude)x`)?
# An exclude-ONLY pathspec set selects everything OUTSIDE the excluded set
# (git applies the exclusion against the full tree when no positive
# pathspec accompanies it — verified empirically), so the checkout/restore
# scans block when excludes appear without any positive operand.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_exclude_pathspec() {
  local magic
  case "$1" in
  ":!"* | ":^"*) return 0 ;;
  ":("*")"*)
    magic="${1#:(}"
    magic="${magic%%)*}"
    [[ ",${magic}," == *",exclude,"* ]]
    ;;
  *) return 1 ;;
  esac
}

# Alias re-expansion is this guard's only recursive path, and it BRANCHES: every
# hop re-checks both alias spellings (`alias.<sub>` and `alias.<sub>.command`)
# independently, so a chain where each hop defines both walks 2^depth analysis
# paths — a benign 10-hop, 402-character command measured 5.4s, and a guard that
# stalls stops guarding. Every recursion is admitted through this one gate, which
# applies two bounds:
#
# MEMO — a verdict is a pure function of (analysis state, argv); every other input
# is invocation-constant (the payload's command, the repository's config and object
# format). A block is a process-wide `exit 2`, so a state reached a SECOND time
# while this process still runs provably did not block the first time and cannot
# decide differently now. Skipping the repeat is exact rather than a coverage
# trade, and it is what collapses the common blowup — both spellings of a hop
# expanding to the same thing — to one path per hop.
#
# BUDGET — memoization alone cannot bound a chain whose two spellings DIFFER: the
# splice carries each path's own trailing text forward, so every argv is distinct
# and the 2^depth walk survives (10 hops of `-c alias.aN='a(N+1) --xN'
# -c alias.aN.command='a(N+1) --yN'` measured 5.7s). A total re-expansion budget
# for the invocation caps the work, and exhausting it fails CLOSED — the guard
# could not finish deciding, so it must not allow.
#
# The ceiling counts ANALYSES rather than seconds, because a wall clock is host-
# and command-length-dependent. It is calibrated against the linear walk this guard
# already accepts: a memoized traversal spends one analysis per hop, and
# MAX_COMMAND_LEN admits chains of roughly 430 hops (a dual-spelling hop costs ~38
# characters), so this ceiling caps a branching walk at strictly less work than the
# longest non-branching chain the guard must already handle. It sits far above real
# usage — a chain deeper than a couple of hops is already exotic, and every
# legitimate command measured spends single digits.
HOOK_ALIAS_WORK_MAX=128

# Call as: alias_reexpand_admit <kind> <state-word>... — returns 1 when this exact
# state was already analyzed. The kind tag keeps a `!` reparse STRING from ever
# keying the same as a one-word argv, `%q` keeps a word containing a newline from
# merging into its neighbour, and the seen-set's length prefixes its own words so
# the set/argv boundary cannot shift. `printf -v` keeps the whole key build
# fork-free — a `$(printf …)` per word would cost more than the walk it bounds.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
alias_reexpand_admit() {
  local kind="$1" key q w
  shift
  key="$kind"$'\n'"${#HOOK_ALIAS_SEEN[@]}"$'\n'
  for w in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"}; do
    printf -v q '%q' "$w"
    key+="$q"$'\n'
  done
  for w in "$@"; do
    printf -v q '%q' "$w"
    key+="$q"$'\n'
  done
  [[ -n "${HOOK_ALIAS_MEMO[$key]+x}" ]] && return 1
  HOOK_ALIAS_MEMO["$key"]=1
  ((++HOOK_ALIAS_WORK <= HOOK_ALIAS_WORK_MAX)) && return 0
  echo "BLOCKED: checking this command's git alias chain needs more than $HOOK_ALIAS_WORK_MAX re-expansions — failing closed rather than stalling the guard." >&2
  echo "Run the subcommand directly, shorten the alias chain, or set the guardrails block_dangerous_git_enabled option to false to bypass." >&2
  emit_tel "blocked" "alias-traversal-cap"
  exit 2
}

# Inspect one already-tokenized segment (its argv words passed as "$@"). Blocks
# when the segment is a real git invocation carrying a default-blocked
# irreversible form. Parsing spine lives in hook-utils.sh; only the form
# matching is this guard's own.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local nseg gi k x rest ch sub sub_idx staged worktree dry excl pos opseen
  local if_includes lease_tracking lease_movable lease_seen lease_ref lease_expect
  # Read by lease_expect_is_immutable further down the call chain; per-frame, so
  # a recursive re-check of an alias expansion collects its own.
  local -a git_locating_opts=()

  # A shell -c wrapper (`bash -lc 'git reset --hard'`) executes its operand as
  # a full shell command — re-parse it with the same tokenizer so the wrapped
  # git invocation is checked faithfully (operators and quoting included).
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  # env -S splicing may have rewritten the argv — match on the resolved words.
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX
  collect_git_locating_opts "$gi" "$sub_idx" "${w[@]}"

  # An inline alias runs its expansion (`git -c alias.rh='reset --hard' rh`
  # discards — verified), so re-check the expanded command: a shell alias
  # (leading !) re-parses as a full shell command; a git alias splices its
  # words in place of the alias name. A --config-env alias for the invoked
  # subcommand is refused by SHAPE — its expansion lives in an env var this guard
  # never reads (hook::git_alias_expansion).
  #
  # The SHAPE refusal must fire at EVERY recursion depth: a wrapping inline alias
  # can expand to `--config-env=alias.<sub>=<envvar>` defining the invoked sub
  # (`git -c alias.rh='--config-env=alias.foo=AV foo' rh`), which git runs. It is
  # value-blind, cheap, and terminal.
  #
  # git DOES chain aliases: when an expansion's first word is itself an alias git
  # expands it again, until a non-alias subcommand is reached OR git detects a
  # loop — a subcommand name it already expanded in this chain — and runs nothing.
  # So the inline re-expansion recurses at EVERY hop, carrying the command-line
  # -c/--config/--config-env globals into each hop (the splice starts at index 0
  # through sub_idx, not gi+1, so no global between git and the subcommand is
  # dropped). Recursion TERMINATES on HOOK_ALIAS_SEEN, a save/restore seen-set of
  # resolved subcommand names: a repeat is git's own alias-loop stop (allow-safe),
  # and finite distinct alias keys guarantee termination. Terminating is not the
  # same as tractable — the walk branches per hop, and alias_reexpand_admit is what
  # keeps its cost proportional to the chain's length.
  local exp reparse a alias_rc s seen_hit=0
  local -a expw=() saved_seen=() nextw=()
  hook::git_alias_expansion "$sub"
  alias_rc=$?
  if ((alias_rc == 2)); then
    # Structural fail-closed: the invoked subcommand is an alias whose LAST definition
    # (here or in a wrapping alias's expansion) is `--config-env=alias.<sub>=<envvar>`,
    # so its expansion is an environment variable's value. Reading that value is the
    # recurring fail-open surface (fed by an ambient var, an inline/`env` prefix, an
    # `export`, `set -a`, or a nested `bash -c` in any wrapper); the shape alone is
    # sufficient. The allow-list is not consulted, as with the too-long-command path.
    echo "BLOCKED: git alias '$sub' is defined via --config-env, so its expansion cannot be verified — failing closed." >&2
    echo "Define the alias in git config, run the subcommand directly, or set the guardrails block_dangerous_git_enabled option to false to bypass." >&2
    emit_tel "blocked" "config-env-alias"
    exit 2
  fi
  # git stops (runs nothing) if the resolved subcommand is one it already expanded
  # in this chain, so skip the re-expansion on a repeat and let the plain scan
  # decide. The set models git's IN-PROCESS alias-loop guard only: a `!` shell
  # alias spawns a fresh git process whose loop guard starts empty, so its
  # reparse below runs under an emptied set.
  for s in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"}; do
    [[ "$s" == "$sub" ]] && {
      seen_hit=1
      break
    }
  done
  if ((alias_rc == 0)) && ((seen_hit == 0)); then
    # Inline alias (-c/--config): each spelling's expansion is literally present. Re-check
    # EVERY spelling (plain and `.command`) independently so a benign expansion in one
    # never suppresses a dangerous sibling in the other. Save/restore the seen-set around
    # the recursion so sibling segments and unwound hops start clean.
    # shellcheck disable=SC2154  # HOOK_GIT_ALIAS_EXPS is set by hook::git_alias_expansion
    saved_seen=(${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"})
    HOOK_ALIAS_SEEN+=("$sub")
    for exp in ${HOOK_GIT_ALIAS_EXPS[@]+"${HOOK_GIT_ALIAS_EXPS[@]}"}; do
      [[ -n "$exp" ]] || continue
      if [[ "$exp" == '!'* ]]; then
        # Shell alias: git runs the expansion as a shell command with the
        # invocation's trailing args appended (positional), so append them
        # (shell-quoted) before re-parsing the whole string as a command.
        # That command runs in a NEW git process whose alias-loop guard starts
        # empty, so the reparse must not inherit this chain's seen-set: a body
        # that re-invokes a name from the outer chain (`git -c
        # alias.a='!git -c alias.a="reset --hard" a' a`) is re-expanded there,
        # not stopped. Termination stays text-bounded — this guard resolves
        # only inline aliases, and every definition reachable from the reparse
        # is a strict substring of the parent segment's text.
        reparse="${exp#!}"
        for a in "${w[@]:sub_idx+1}"; do reparse+=" $(printf '%q' "$a")"; done
        HOOK_ALIAS_SEEN=()
        alias_reexpand_admit shell "$reparse" &&
          hook::bash_parse_segments "$reparse" check_segment
        HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"} "$sub")
      else
        # Git alias: its expansion is dequoted with shell quoting rules
        # (so `push "--force"` yields --force, not "--force"). Splice the
        # dequoted words in place of the alias name, keeping every command-line
        # global (indices 0..sub_idx) and the trailing invocation args, which
        # git appends to the expanded argv.
        hook::env_s_split "$exp"
        expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
        nextw=("${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}")
        alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
      fi
    done
    HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"})
  fi

  case "$sub" in
  push)
    # --force blocks; --force-with-lease / --force-if-includes do not (safe
    # force). A leading-`+` refspec operand and --mirror force-update refs the
    # same way --force does, so they carry the same form token. Skip values of
    # value-taking push options (space-separated and attached `-oVALUE`) so a
    # value word never matches as a flag. Short bundle: any `f` means --force.
    # A push dry-run flag anywhere (-n, --dry-run or an accepted unique
    # abbreviation ≥ --dr; --d is ambiguous with --delete) makes the push a
    # preview that updates nothing — it disarms the force check. Option values
    # are skipped in this pre-scan too so a value word never reads as a flag.
    # `--` ends option parsing everywhere below (gitcli): after it, words are
    # operands — a literal "--dry-run" refspec is not a preview flag, and a
    # literal "-f" is not force. Only the leading-+ refspec check applies past
    # the marker.
    # Dry-run is last-wins: `--no-dry-run` after a dry token re-arms the push
    # (git's --[no-]dry-run pair), so track state instead of early-returning.
    # The mitigation flag is last-wins for the same reason: git spells it
    # `--[no-]force-if-includes`, so a trailing negation must clear it or the
    # lease check disarms while git pushes unmitigated.
    dry=0
    if_includes=0
    lease_tracking=0
    lease_movable=0
    lease_seen=""
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --) break ;;
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*) ;;
      --no-*)
        abbrev_match "dry-run" "--${x#--no-}" 2 && dry=0
        abbrev_match "force-if-includes" "--${x#--no-}" 7 && if_includes=0
        # git: "--no-force-with-lease will cancel all the previous
        # --force-with-lease on the command line" — every spelling, and the
        # per-ref claims they staked, not just the bare one.
        if abbrev_match "force-with-lease" "--${x#--no-}" 7; then
          lease_tracking=0
          lease_movable=0
          lease_seen=""
        fi
        # Consume the word here. Falling through would let
        # `--no-force-with-lease` re-match below as the positive option and
        # undo the clear that just happened.
        ((k++))
        continue
        ;;
      --*)
        if is_push_value_opt "$x"; then
          ((k += 2))
          continue
        fi
        ;;&
      *)
        if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 2 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
          dry=1
        fi
        abbrev_match "force-if-includes" "${x%%=*}" 7 && if_includes=1
        # Lease spellings are INDEPENDENT of one another, and the two unsafe
        # kinds are tracked separately because git mitigates only one of them.
        # A pinned `=<refname>:<expect>` is scoped by git to the ref it names
        # and says nothing about the others, so it can never make a bare
        # fallback safe.
        if is_lease_opt "$x"; then
          if [[ "$x" != *=* ]]; then
            # Bare form: the tracking-based fallback for every ref no explicit
            # entry claims. No refname to key on, so it is its own slot.
            lease_tracking=1
          else
            lease_ref="${x#*=}"
            lease_ref="${lease_ref%%:*}"
            # First entry for a ref wins in git; a later one for the same ref
            # is never consulted, so it must not drive the verdict either.
            if ! lease_ref_claimed "$lease_seen" "$lease_ref"; then
              lease_seen="$lease_seen$lease_ref"$'\n'
              if [[ "$x" != *=*:* ]]; then
                lease_tracking=1
              else
                lease_expect="${x#*=}"
                lease_expect="${lease_expect#*:}"
                lease_expect_is_immutable "$lease_expect" || lease_movable=1
              fi
            fi
          fi
        fi
        ;;
      esac
      ((k++))
    done
    ((dry)) && return 0
    # Decided after the scan, never mid-scan: every one of these options is
    # last-wins, so an early match cannot be acted on before the segment ends.
    if ((lease_movable)); then
      block "push-lease-unsafe" \
        "BLOCKED: git push --force-with-lease=<refname>:<expect> whose <expect> is a name git resolves at push time (origin/main, HEAD, a tag, an abbreviated object id, or hex of the wrong width for this repository's hash format) leases against a moving target, and git-push(1) declares --force-if-includes a no-op alongside an explicit :<expect>, so nothing mitigates it." \
        "Pin the expectation to an object id of this repository's full hash width (--force-with-lease=<refname>:\$(git rev-parse <ref>)), or allow via the block_dangerous_git_allow option (add push-lease-unsafe)."
    fi
    if ((lease_tracking)) && ((!if_includes)); then
      block "push-lease-unsafe" \
        "BLOCKED: git push --force-with-lease without an expected value leases against the remote-tracking ref, which a background fetch can satisfy while still clobbering unseen work." \
        "State the expectation (--force-with-lease=<refname>:<full-sha>), or add --force-if-includes, or allow via the block_dangerous_git_allow option (add push-lease-unsafe)."
    fi
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --)
        for ((k++; k < nseg; k++)); do
          [[ "${w[k]}" == +* ]] && block "push-force" \
            "BLOCKED: a leading + on a push refspec is a force-push (same as --force)." \
            "Drop the + or use --force-with-lease, or allow via the block_dangerous_git_allow option (add push-force)."
        done
        break
        ;;
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*)
        ((k++))
        continue
        ;;
      --*)
        # An abbreviated value-consuming push option eats the next word;
        # otherwise fall through (`;;&`) so --force and --mirror below still
        # match.
        if is_push_value_opt "$x"; then
          ((k += 2))
          continue
        fi
        ;;&
      --force)
        block "push-force" \
          "BLOCKED: git push --force is irreversible for anyone sharing the branch." \
          "Use --force-with-lease (refuses to clobber unseen remote work), or allow via the block_dangerous_git_allow option (add push-force)."
        ;;
      # The lease family is decided in the pre-scan above, not here: every one
      # of its options is last-wins, so no single occurrence can be acted on
      # until the segment ends.
      --force-*) ;;
      +*)
        block "push-force" \
          "BLOCKED: a leading + on a push refspec is a force-push (same as --force)." \
          "Drop the + or use --force-with-lease, or allow via the block_dangerous_git_allow option (add push-force)."
        ;;
      -[A-Za-z]*)
        if [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "push-force" \
            "BLOCKED: git push -f is irreversible for anyone sharing the branch." \
            "Use --force-with-lease (refuses to clobber unseen remote work), or allow via the block_dangerous_git_allow option (add push-force)."
        fi
        ;;
      *)
        # --mirror's unique prefix floor is 1: `--m` is the only push option
        # starting with m, and git accepts `git push --m` as a mirror push.
        if abbrev_match "mirror" "$x" 1; then
          block "push-force" \
            "BLOCKED: git push --mirror force-updates every remote ref." \
            "Push specific refs instead, or allow via the block_dangerous_git_allow option (add push-force)."
        fi
        ;;
      esac
      ((k++))
    done
    ;;
  reset)
    # --hard and its accepted unique abbreviations (git parse-options accepts
    # any unambiguous prefix: `reset --h` runs --hard, verified empirically).
    # --pathspec-from-file (and its unique abbreviations ≥ --pathspec-fr —
    # --pathspec-f is ambiguous with --pathspec-file-nul) consumes the next
    # word as its value.
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      if [[ "$x" != *=* ]] && abbrev_match "pathspec-from-file" "$x" 11; then
        ((k++))
        continue
      fi
      abbrev_match "hard" "$x" 1 && block "reset-hard" \
        "BLOCKED: git reset --hard discards uncommitted work with no recovery path." \
        "Commit or stash first (git stash push -u), use git reset --keep, or allow via the block_dangerous_git_allow option (add reset-hard)."
    done
    ;;
  clean)
    # Force flag required before clean deletes anything: --force (or a unique
    # abbreviation ≥ --f), or f in a short bundle (-f, -fd, -fdx, -ff). A
    # dry-run flag anywhere (-n, --dry-run ≥ --d, or n in a bundle) makes the
    # whole command a preview — git honors it regardless of flag order — so it
    # disarms the force check. -e/--exclude consumes the next word as its
    # pattern in BOTH scans, so a flag-looking value (`-e --dry-run`) neither
    # disarms nor triggers anything.
    # `--` ends option parsing: a pathspec literally named "--dry-run" after
    # the marker must not disarm the force check, and no force flag can
    # appear there either.
    # Dry-run is last-wins here too: `--no-dry-run` after a dry token re-arms
    # the deletion, so track state instead of early-returning. --exclude and
    # its accepted abbreviations (`--ex`) consume the next word as a pattern
    # in BOTH scans, so a flag-looking exclude value neither disarms nor
    # triggers anything.
    dry=0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      case "$x" in
      -e)
        ((k++))
        continue
        ;;
      -e?*) continue ;;
      --no-*)
        abbrev_match "dry-run" "--${x#--no-}" 1 && dry=0
        continue
        ;;
      *) ;;
      esac
      if [[ "$x" == --*=* ]] && abbrev_match "exclude" "${x%%=*}" 1; then
        continue
      fi
      if [[ "$x" != *=* ]] && abbrev_match "exclude" "$x" 1; then
        ((k++))
        continue
      fi
      # In a short bundle `-e` absorbs the REST of the bundle as its value
      # (`-fen` = -f -e n — verified: it deletes), or the next word when it
      # is the last letter (`-fe -n` = exclude pattern "-n" — also
      # deletes). Only letters before the `e` are flags.
      if [[ "$x" =~ ^-[A-Za-z]*e[A-Za-z]*$ ]]; then
        rest="${x%%e*}"
        [[ "$x" == *e ]] && ((k++))
        [[ "$rest" == *n* ]] && dry=1
        continue
      fi
      if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 1 ||
        [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
        dry=1
      fi
    done
    ((dry)) && return 0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      case "$x" in
      -e)
        ((k++))
        continue
        ;;
      -e?*) continue ;;
      *) ;;
      esac
      if [[ "$x" == --*=* ]] && abbrev_match "exclude" "${x%%=*}" 1; then
        continue
      fi
      if [[ "$x" != *=* ]] && abbrev_match "exclude" "$x" 1; then
        ((k++))
        continue
      fi
      # Same bundle rule as the dry-run pre-scan: letters at and after the
      # first `e` are its value, so only the prefix carries flags.
      if [[ "$x" =~ ^-[A-Za-z]*e[A-Za-z]*$ ]]; then
        rest="${x%%e*}"
        [[ "$x" == *e ]] && ((k++))
        if [[ "$rest" == *f* ]]; then
          block "clean-force" \
            "BLOCKED: git clean with a force flag permanently deletes untracked files." \
            "Preview with git clean -n first; then allow via the block_dangerous_git_allow option (add clean-force) if intended."
        fi
        continue
      fi
      if abbrev_match "force" "$x" 1 || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
        block "clean-force" \
          "BLOCKED: git clean with a force flag permanently deletes untracked files." \
          "Preview with git clean -n first; then allow via the block_dangerous_git_allow option (add clean-force) if intended."
      fi
    done
    ;;
  checkout)
    # Worktree-wide discard: a tree-wide pathspec operand, an exclude-only
    # pathspec set (selects everything outside the excluded set — with or
    # without a tree-ish: `checkout HEAD -- ':!docs'` and `checkout main
    # ':!docs'` both overwrite everything except the exclusion), or a
    # forced checkout (`-f`/`--force` throws away local modifications even
    # while switching branches). Path-scoped checkouts (`checkout
    # .github/x`) tokenize as different words and never match. Skip values
    # of value-taking options so a branch named "." cannot be created but
    # its option value never false-matches the operand scan. Only real
    # pathspec operands count as positive scope: the first plain-word
    # operand is the optional tree-ish (git puts the tree-ish before all
    # pathspecs), so it never clears the exclude-only condition; a
    # magic-prefixed first operand is already a pathspec and counts.
    excl=0
    pos=0
    opseen=0
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      # After `--` every word is a pathspec — flags stop matching, but the
      # tree-wide pathspec check still applies.
      --)
        for ((k++; k < nseg; k++)); do
          is_tree_wide_pathspec "${w[k]}" && block "checkout-dot" \
            "BLOCKED: a worktree-wide git checkout pathspec discards every unstaged change." \
            "Checkout specific paths, stash first, or allow via the block_dangerous_git_allow option (add checkout-dot)."
          if is_exclude_pathspec "${w[k]}"; then ((excl++)); else ((pos++)); fi
        done
        break
        ;;
      # A pathspec file can carry `.` — unverifiable statically, so it fails
      # closed under the same form token (allow-list to permit). git accepts
      # unique prefixes (≥ --pathspec-fr; --pathspec-f is ambiguous with
      # --pathspec-file-nul), in space and `=` forms alike.
      --pathspec-*)
        rest="${x%%=*}"
        if abbrev_match "pathspec-from-file" "$rest" 11; then
          block "checkout-dot" \
            "BLOCKED: git checkout --pathspec-from-file can address the whole worktree; the file cannot be verified statically." \
            "Pass explicit paths instead, or allow via the block_dangerous_git_allow option (add checkout-dot)."
          if [[ "$x" == *=* ]]; then ((k++)); else ((k += 2)); fi
        else
          ((k++))
        fi
        continue
        ;;
      -b | -B | --orphan | --conflict)
        ((k += 2))
        continue
        ;;
      # Attached branch-name values (`-bname`) are values, not flag bundles.
      -b?* | -B?*)
        ((k++))
        continue
        ;;
      *)
        # Value-taking options in accepted abbreviated form (--c for
        # --conflict, --or for --orphan — verified unique floors) consume
        # the next word, which must not count as an operand.
        if [[ "$x" != *=* ]] &&
          { abbrev_match "conflict" "$x" 1 || abbrev_match "orphan" "$x" 2; }; then
          ((k += 2))
          continue
        fi
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "checkout-force" \
            "BLOCKED: git checkout -f/--force throws away local modifications." \
            "Commit or stash first, or allow via the block_dangerous_git_allow option (add checkout-force)."
        fi
        is_tree_wide_pathspec "$x" && block "checkout-dot" \
          "BLOCKED: a worktree-wide git checkout pathspec discards every unstaged change." \
          "Checkout specific paths, stash first, or allow via the block_dangerous_git_allow option (add checkout-dot)."
        if [[ "$x" != -* ]]; then
          if is_exclude_pathspec "$x"; then
            ((excl++))
            opseen=1
          elif ((opseen)) || [[ "$x" == :* ]]; then
            ((pos++))
            opseen=1
          else
            opseen=1
          fi
        fi
        ;;
      esac
      ((k++))
    done
    ((excl > 0 && pos == 0)) && block "checkout-dot" \
      "BLOCKED: an exclude-only git checkout pathspec restores everything outside the excluded set." \
      "Add positive paths to scope the checkout, or allow via the block_dangerous_git_allow option (add checkout-dot)."
    ;;
  switch)
    # switch -f/--force (alias --discard-changes) throws away local
    # modifications the same way forced checkout does. `--d` alone is
    # ambiguous with --detach, so the discard-changes floor is --di (the
    # shortest unambiguous prefix: `--di`/`--dis` are accepted, verified).
    # -c/-C/--orphan/--conflict consume a branch-name/style value — space
    # or attached `-cname` form (gitcli stuck values) — which must not be
    # scanned as a flag bundle (`switch -cfix` creates branch "fix").
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      --) break ;;
      -c | -C | --orphan | --conflict)
        ((k += 2))
        continue
        ;;
      -c?* | -C?*)
        ((k++))
        continue
        ;;
      *)
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 ||
          abbrev_match "discard-changes" "$x" 2 ||
          [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "checkout-force" \
            "BLOCKED: git switch -f/--discard-changes throws away local modifications." \
            "Commit or stash first, or allow via the block_dangerous_git_allow option (add checkout-force)."
        fi
        ;;
      esac
      ((k++))
    done
    ;;
  restore)
    # `restore .` discards the worktree unless the restore is staged-only
    # (--staged without --worktree restores the index from HEAD — reversible).
    staged=0
    worktree=0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      [[ "$x" == "--" ]] && break
      # --st is the shortest unique prefix of --staged (vs --source); --w is
      # unique for --worktree. Both are --[no-] pairs and git honors the
      # LAST selector (`--staged --worktree --no-worktree .` is index-only
      # — verified), so --no- forms clear the corresponding flag.
      case "$x" in
      --staged) staged=1 ;;
      --worktree) worktree=1 ;;
      --no-*)
        rest="--${x#--no-}"
        abbrev_match "staged" "$rest" 2 && staged=0
        abbrev_match "worktree" "$rest" 1 && worktree=0
        ;;
      --s* | --w*)
        abbrev_match "staged" "$x" 2 && staged=1
        abbrev_match "worktree" "$x" 1 && worktree=1
        ;;
      -[A-Za-z]*)
        if [[ "$x" =~ ^-[A-Za-z]+$ ]]; then
          rest="${x#-}"
          for ((ch = 0; ch < ${#rest}; ch++)); do
            case "${rest:ch:1}" in
            S) staged=1 ;;
            W) worktree=1 ;;
            *) ;;
            esac
          done
        fi
        ;;
      *) ;;
      esac
    done
    if ((staged == 0 || worktree == 1)); then
      excl=0
      pos=0
      k=$((sub_idx + 1))
      while ((k < nseg)); do
        x="${w[k]}"
        case "$x" in
        # After `--` every word is a pathspec — only the tree-wide check applies.
        --)
          for ((k++; k < nseg; k++)); do
            is_tree_wide_pathspec "${w[k]}" && block "restore-dot" \
              "BLOCKED: a worktree-wide git restore pathspec discards every unstaged change." \
              "Restore specific paths, stash first, or allow via the block_dangerous_git_allow option (add restore-dot)."
            if is_exclude_pathspec "${w[k]}"; then ((excl++)); else ((pos++)); fi
          done
          break
          ;;
        # A pathspec file can carry `.` — unverifiable statically, so it fails
        # closed under the same form token (allow-list to permit). git accepts
        # unique prefixes (≥ --pathspec-fr; --pathspec-f is ambiguous with
        # --pathspec-file-nul), in space and `=` forms alike.
        --pathspec-*)
          rest="${x%%=*}"
          if abbrev_match "pathspec-from-file" "$rest" 11; then
            block "restore-dot" \
              "BLOCKED: git restore --pathspec-from-file can address the whole worktree; the file cannot be verified statically." \
              "Pass explicit paths instead, or allow via the block_dangerous_git_allow option (add restore-dot)."
            if [[ "$x" == *=* ]]; then ((k++)); else ((k += 2)); fi
          else
            ((k++))
          fi
          continue
          ;;
        -s | --source | --conflict)
          ((k += 2))
          continue
          ;;
        *)
          # Value-taking options in accepted abbreviated form (--so for
          # --source, --c for --conflict — verified unique floors) consume
          # the next word, which must not count as a positive pathspec.
          if [[ "$x" != *=* ]] &&
            { abbrev_match "source" "$x" 2 || abbrev_match "conflict" "$x" 1; }; then
            ((k += 2))
            continue
          fi
          is_tree_wide_pathspec "$x" && block "restore-dot" \
            "BLOCKED: a worktree-wide git restore pathspec discards every unstaged change." \
            "Restore specific paths, stash first, or allow via the block_dangerous_git_allow option (add restore-dot)."
          if [[ "$x" != -* ]]; then
            if is_exclude_pathspec "$x"; then ((excl++)); else ((pos++)); fi
          fi
          ;;
        esac
        ((k++))
      done
      ((excl > 0 && pos == 0)) && block "restore-dot" \
        "BLOCKED: an exclude-only git restore pathspec discards everything outside the excluded set." \
        "Add positive paths to scope the restore, or allow via the block_dangerous_git_allow option (add restore-dot)."
    fi
    ;;
  *) ;;
  esac

  return 0
}

# Fail-closed by construction: this path never consults the allow-list — an
# unparsable command cannot prove which forms it carries, so no form token
# can honestly allow it. Only the kill switch bypasses.
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  echo "BLOCKED: command too long to parse safely (> $MAX_COMMAND_LEN chars)." >&2
  echo "Shorten the command, or set the guardrails block_dangerous_git_enabled option to false (/plugin configure) to bypass." >&2
  emit_tel "blocked" "too-long"
  exit 2
fi

# Reduce a PowerShell command to a Bash-tokenizer-faithful form, or fail closed.
# For the Bash tool this is a no-op (COMMAND unchanged). The classifier's sink is
# git-presence-based (ps::might_invoke_git), so an unparsable PowerShell command
# that could reach git at all is blocked — this guard owns destructive non-commit
# forms (reset/clean/checkout/restore), and an unparsable `git --% reset --hard`
# must not slip through. A non-git unparsable PowerShell command is not this
# guard's concern and is allowed.
ps::classify_git_command "$TOOL_NAME" "$COMMAND"
case $? in
2)
  ps::print_unparsable_git_block_message
  emit_tel "blocked" "powershell-unparsable"
  exit 2
  ;;
1) exit 0 ;; # non-git PowerShell with an A2b-deferred construct
*) COMMAND="$PS_SAFE_COMMAND" ;;
esac

# Resolved-subcommand names already expanded in the CURRENT alias chain — git's
# own alias-loop guard. Initialized here (not in check_segment, which recurses
# and would reset it) and save/restored around each recursion; a multi-command
# line runs check_segment once per top-level segment, each starting from empty.
HOOK_ALIAS_SEEN=()

# The alias-traversal bounds (alias_reexpand_admit). Both are invocation-wide and
# deliberately NOT save/restored: a state analyzed anywhere is analyzed, and the
# budget bounds the whole command's work rather than one path's.
declare -A HOOK_ALIAS_MEMO=()
HOOK_ALIAS_WORK=0

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
