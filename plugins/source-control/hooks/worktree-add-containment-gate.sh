#!/usr/bin/env bash
# worktree-add-containment-gate.sh — PreToolUse hook: block a raw
# `git worktree add` whose resolved target lands INSIDE a git repository — a
# working tree, or a .git / bare directory (#2611).
#
# WHY IT EXISTS — the nesting invariant was enforced only on the one creation
# path that already knew about it: the `/worktree create` skill routes through
# scripts/worktree-create.sh, and the WorktreeCreate hook covers the
# harness-driven paths (`claude --worktree`, subagent worktree isolation,
# background sessions). A raw `git worktree add` from a Bash tool call bypassed
# both, and the fleet measurement in #2611 found 9 of 292 linked worktrees
# nested inside their repository and ~245 more at other non-conforming
# locations. This hook is the seam for the raw-Bash path. The invariant itself
# is owned, measured and dated in exactly one place, not restated here:
# skills/worktree/SKILL.md § "The nesting invariant, verified".
#
# WHAT IT BLOCKS — precisely the nesting class, nothing else. The resolved
# target's nearest existing ancestor is asked (via `git rev-parse`) whether it
# sits inside a working tree or a git directory; only a yes blocks. A target
# outside every repository passes SILENTLY even when it is not under the
# configured root — the convention exempts tool-owned conventions (Codex,
# Cursor), and #2611 rules out a generic "use the skill" advisory on every
# `git worktree add` as noise that gets routed around. PreToolUse is the only
# useful moment: advising after the worktree exists adds nothing.
#
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE NESTED TARGET. The
# target is only judged when it can be resolved statically: a literal path,
# relative paths resolved against the payload `cwd` composed with wrapper
# chdirs (`env -C`, `sudo -D`) and `git -C` values. A path carrying an
# unexpanded `$`/backtick, a segment after a `cd`/`pushd`/`popd` (the effective
# directory is a runtime fact), a missing payload cwd for a relative path, or a
# command this hook cannot tokenize all ALLOW: a misplaced worktree is
# reversible (`git worktree remove`), so blocking arbitrary Bash on a guess is
# the worse failure. Same posture and same wrapper/segment machinery as the
# sibling pr-body-linkage-gate; jq gate is the fail-open hook::require_jq per
# the posture doctrine in hook-utils.sh (this guard fails closed on no other
# unparsable-input condition, so it does not join the fail-closed class).
#
# DECLARED BYPASS COVERAGE (out of scope, documented): the PowerShell tool
# (Bash-matcher hook; the PowerShell classifier is guardrails-owned and not
# vendored here); `git -C` / `--work-tree` values that are themselves dynamic;
# a worktree created by a program the command runs (a script, make target, or
# `gh` extension); and `EnterWorktree(name:)`, which is not a Bash call and is
# therefore invisible to any Bash-scoped hook — its misplacement is handled by
# the WorktreeCreate hook (worktree-create-gate.sh) for harness-driven
# creations, and the `/worktree create` skill is contractually forbidden from
# calling the name form at all (SKILL.md safety invariants). Whether
# EnterWorktree(name:) fires WorktreeCreate on the current harness is recorded
# where it is measured, skills/worktree/fixtures/README.md, not asserted here.
#
# Kill switch: worktree_add_containment_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming the resolved target, what encloses it, and the
# configured root (melodic.worktreeroot key, then the worktree_root plugin
# option, then the plugin data dir) so the remedy is concrete.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "WORKTREE_ADD_CONTAINMENT_GATE"

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PreToolUse" "source-control-worktree-add-containment-gate" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
# Applicability pre-filter before any parsing: `git` as its own word (or a
# path's last segment) plus both subcommand words, so an unrelated Bash call
# never pays for the tokenizer. The command text is pre-tokenizer, so quotes
# count as boundaries.
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Ii][Tt][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *worktree* ]] || exit 0
[[ "$COMMAND" == *add* ]] || exit 0

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')

# Set once a segment changes the working directory; every later segment then
# resolves against a directory this hook cannot see (same rule and same
# rationale as pr-body-linkage-gate: only the CURRENT shell's own relocation
# counts).
DIR_CHANGED=0

# A value the tokenizer could not fully resolve — an unexpanded expansion or a
# command substitution — is not this hook's to judge on its face.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# True for an absolute path in either grammar this hook meets: POSIX `/...` or
# drive-letter `C:/...` / `C:\...`.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_abs_path() {
  [[ "$1" == /* || "$1" =~ ^[A-Za-z]:[/\\] ]]
}

# normalize_path <abs-path> — lexically collapse `.`/`..`/`//`, echoing the
# result. Pure string work (no filesystem), so it resolves `..` even through
# not-yet-existing components — the case `git worktree add` handles by creating
# them. Adapted from scripts/worktree-create.sh, where the hazard it closes is
# documented: a `..` after a nonexistent component otherwise defeats the
# nearest-existing-ancestor walk below.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
normalize_path() {
  local input="$1" root rest seg
  if [[ "$input" == /* ]]; then
    root="/"
    rest="${input#/}"
  elif [[ "$input" =~ ^[A-Za-z]:/ ]]; then
    root="${input:0:2}/"
    rest="${input:3}"
  else
    root=""
    rest="$input"
  fi
  local -a segs=() out=()
  IFS='/' read -r -a segs <<<"$rest"
  for seg in "${segs[@]}"; do
    [[ -z "$seg" || "$seg" == "." ]] && continue
    if [[ "$seg" == ".." ]]; then
      ((${#out[@]})) && out=("${out[@]:0:${#out[@]}-1}")
      continue
    fi
    out+=("$seg")
  done
  local IFS='/'
  printf '%s%s' "$root" "${out[*]}"
}

# resolve_against <base> <path> — absolutize <path> against <base>, echoing the
# result; echoes nothing when neither is absolute. Backslashes are folded to
# forward slashes on Windows shells only, mirroring the helper's canonicalize
# (off-Windows `\` is a legal filename byte).
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
resolve_against() {
  local base="$1" p="$2"
  if [[ ("$p" == *\\* || "$base" == *\\*) && ("${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin*) ]]; then
    local bslash="\\" fwd="/"
    p="${p//"$bslash"/"$fwd"}"
    base="${base//"$bslash"/"$fwd"}"
  fi
  # A leading unquoted `~` would have been expanded by the shell before git ever
  # saw it; reproduce the common case, and let an unresolvable one fall out as
  # relative-with-no-base (allow). SC2088: matching the literal unexpanded tilde
  # is the point.
  # shellcheck disable=SC2088
  if [[ "$p" == "~/"* && -n "${HOME:-}" ]]; then
    p="${HOME}/${p#\~/}"
  fi
  # shellcheck disable=SC2310  # is_abs_path is a pure predicate; both branches are handled
  if is_abs_path "$p"; then
    printf '%s' "$p"
    return 0
  fi
  [[ -n "$base" ]] || return 0
  printf '%s/%s' "${base%/}" "$p"
}

# git_unlocated <git-args…> — run git with the locating env vars unset, so an
# inherited GIT_DIR cannot skew a probe's answer (#972 discipline, same as
# hook::in_git_working_tree). The unset is confined to the subshell, so it never
# reaches the hook's own environment.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
git_unlocated() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM
    git "$@" 2>/dev/null
  )
}

# repo_enclosing <abs-target> — if the target's nearest existing ancestor sits
# inside a git working tree or a git directory, print a two-line
# "<kind>\n<detail>" and return 0; return 1 otherwise. The walk probes the
# target's PARENT side, never the target itself (the target must not exist for
# `git worktree add` to succeed anyway). Every probe goes through
# `git_unlocated` so an inherited GIT_DIR cannot skew the answer.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_enclosing() {
  local target="$1" probe parent top inside
  probe="${target%/*}"
  [[ -n "$probe" ]] || probe="/"
  while [[ ! -e "$probe" ]]; do
    parent="${probe%/*}"
    [[ "$parent" == "$probe" || -z "$parent" ]] && break
    probe="$parent"
  done
  [[ -e "$probe" ]] || return 1
  top=$(git_unlocated -C "$probe" rev-parse --show-toplevel)
  top="${top//$'\r'/}"
  if [[ -n "$top" ]]; then
    printf 'a git working tree\n%s' "$top"
    return 0
  fi
  inside=$(git_unlocated -C "$probe" rev-parse --is-inside-git-dir)
  if [[ "${inside//$'\r'/}" == "true" ]]; then
    local gitdir
    gitdir=$(git_unlocated -C "$probe" rev-parse --absolute-git-dir)
    printf 'a git directory\n%s' "${gitdir//$'\r'/}"
    return 0
  fi
  return 1
}

# configured_root <repo-hint-dir> — the root the block message names, resolved
# with the same precedence the creation helper uses: the melodic.worktreeroot
# key from the repository the command targets (includes on, last value wins,
# gated on the repository actually resolving — never the silent
# dubious-ownership global fallback), then the plugin option, then the plugin
# data dir. Echoes empty when nothing is configured.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
configured_root() {
  local hint="$1" r=""
  if [[ -n "$hint" ]] && git -C "$hint" rev-parse --git-dir >/dev/null 2>&1; then
    r=$(git -C "$hint" config --get-all --type=path melodic.worktreeroot 2>/dev/null | tail -n 1 | tr -d '\r')
  fi
  if [[ -z "$r" ]]; then
    r="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
    # SC2016: the single-quoted ${user_config token is matched literally on
    # purpose — an unexpanded placeholder is an unset value.
    # shellcheck disable=SC2016
    case "$r" in
    *'${user_config'*) r="" ;;
    *) ;;
    esac
  fi
  if [[ -z "$r" && -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    r="${CLAUDE_PLUGIN_DATA%/}/worktrees"
  fi
  printf '%s' "$r"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block() {
  local target="$1" kind="$2" detail="$3" hint="$4" root
  root=$(configured_root "$hint")
  echo "BLOCKED: git worktree add target lands inside $kind." >&2
  echo "  target:  $target" >&2
  echo "  inside:  $detail" >&2
  if [[ -n "$root" ]]; then
    echo "Place worktrees at the configured external root instead: $root" >&2
    echo "  e.g. git worktree add \"$root/<owner>-<repo>-<slug>\" ..." >&2
  else
    echo "No external worktree root is configured. Set one every tool can read:" >&2
    echo "  git config --global melodic.worktreeroot <dir-outside-every-repo>" >&2
  fi
  echo "A worktree nested inside a checkout can pick up that checkout's path-scoped rules as well as its own, and a git-directory placement mixes the checkout into git metadata — measurement, disputed arms and expiry: skills/worktree/SKILL.md \"The nesting invariant, verified\"." >&2
  echo "Or use /source-control:worktree create, which places (and locks) the worktree for you. Convention: the source-control plugin's reference/worktree-root-convention.md. Kill switch: the worktree_add_containment_gate_enabled plugin option." >&2
  exit 2
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 d word

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # Leading `VAR=val` assignments are not the command word.
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done

  # Only the CURRENT shell can relocate later segments; `command`/`builtin`/
  # `eval` dispatch the cd builtin inside this shell, `sudo cd`/`env cd` are
  # separate processes that fail on a builtin and move nothing (they fall
  # through to the resolver, where `cd` is simply not `git`).
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

  hook::git_resolve_index "${w[@]}" || return 0
  local gi="$HOOK_GIT_RESOLVED_GI"
  local -a words=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  local -a wrapper_dirs=()
  ((${#HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]})) && wrapper_dirs=("${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]}")
  n=${#words[@]}

  hook::git_resolve_subcommand "$gi" "${words[@]}" || return 0
  [[ "$HOOK_GIT_SUB" == "worktree" ]] || return 0
  local sub_idx="$HOOK_GIT_SUB_IDX"
  [[ "${words[sub_idx + 1]:-}" == "add" ]] || return 0

  # The effective directory the git process runs in: the payload cwd, composed
  # with each wrapper chdir in execution order, then each git global -C in
  # order (git applies multiple -C values cumulatively). Any dynamic hop makes
  # the base unknowable — allow.
  local base="$HOOK_CWD" hop
  for hop in ${wrapper_dirs[@]+"${wrapper_dirs[@]}"}; do
    # shellcheck disable=SC2310  # is_dynamic is a pure predicate; the match is the verdict
    is_dynamic "$hop" && return 0
    base=$(resolve_against "$base" "$hop")
    [[ -n "$base" ]] || return 0
  done
  local j=$((gi + 1))
  while ((j < sub_idx)); do
    if [[ "${words[j]}" == "-C" ]]; then
      hop="${words[j + 1]:-}"
      [[ -n "$hop" ]] || return 0
      # shellcheck disable=SC2310  # is_dynamic is a pure predicate; the match is the verdict
      is_dynamic "$hop" && return 0
      base=$(resolve_against "$base" "$hop")
      [[ -n "$base" ]] || return 0
      ((j += 2))
      continue
    fi
    ((j++))
  done

  # Walk the `add` arguments for the target path: the first positional word.
  # Value-taking options for `git worktree add` are exactly -b, -B, and
  # --reason (their attached forms are single words); every other option is a
  # boolean the walk steps over, and `--` ends option parsing.
  local target="" seen_ddash=0
  for ((j = sub_idx + 2; j < n; j++)); do
    word="${words[j]}"
    if ((seen_ddash == 0)); then
      case "$word" in
      --)
        seen_ddash=1
        continue
        ;;
      -b | -B | --reason)
        ((j++))
        continue
        ;;
      -*)
        continue
        ;;
      *) ;;
      esac
    fi
    target="$word"
    break
  done
  [[ -n "$target" ]] || return 0
  # shellcheck disable=SC2310  # is_dynamic is a pure predicate; the match is the verdict
  is_dynamic "$target" && return 0

  local abs
  abs=$(resolve_against "$base" "$target")
  [[ -n "$abs" ]] || return 0
  abs=$(normalize_path "$abs")

  local verdict kind detail
  # shellcheck disable=SC2310  # the return status IS the verdict; output is read only on 0
  if verdict=$(repo_enclosing "$abs"); then
    kind="${verdict%%$'\n'*}"
    detail="${verdict#*$'\n'}"
    block "$abs" "$kind" "$detail" "$base"
  fi
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment

exit 0
