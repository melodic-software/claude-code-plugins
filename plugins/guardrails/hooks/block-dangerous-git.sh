#!/usr/bin/env bash
# PreToolUse hook: block irreversible git operations on Bash tool calls.
#
# Default block-list is irreversible-only:
#   push-force    — git push --force / -f (NOT --force-with-lease)
#   reset-hard    — git reset --hard
#   clean-force   — git clean with a force flag (-f, -fd, -fdx, --force)
#   checkout-dot  — git checkout .  (worktree-wide discard; path-scoped is fine)
#   restore-dot   — git restore .   (worktree discard; --staged-only is fine)
#
# NOT blocked: --force-with-lease (safe force), plain push, soft/mixed reset,
# clean -n (dry run), path-scoped checkout/restore, and `branch -D` (reflog
# recovers deleted refs, and sanctioned skill flows issue it inline).
#
# Per-repo/per-user allow-list: HOOK_BLOCK_DANGEROUS_GIT_ALLOW is a
# comma-separated list of the form tokens above (e.g. "push-force,reset-hard"),
# settable in a project's .claude/settings.json `env` block (per-repo) or user
# settings (per-user). Kill switch: HOOK_BLOCK_DANGEROUS_GIT_ENABLED=false.
#
# Detection is ARGV-GRAMMAR-FAITHFUL via the shared parser in hook-utils.sh —
# a quoted "git push --force" in prose never fires; `checkout .github/x` never
# matches `checkout .`. Static matching over the literal command string only:
# shell variable / command substitution is not evaluated. This is a friction
# guard against accidental destruction, not a sandbox. An inline env prefix
# (`HOOK_..._ENABLED=false git push -f`) does NOT disable the hook — the
# prefix reaches only the spawned git process, not this hook.
#
# BLOCKING: exits 2 on any detected form not in the allow-list.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_DANGEROUS_GIT"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# jq is required to parse the tool payload. Fail OPEN when it is absent, but make
# the degraded state visible rather than silently disabling the guard.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/block-dangerous-git: jq not found on PATH — guard disabled (install jq to enable)." >&2
  exit 0
fi

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op).
INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0

# Above this length the command is not parsed — a pathologically long command is
# assumed to be obfuscation and blocked FAIL-CLOSED (generous cap; real git
# commands are well under it). The linear parser keeps normal commands cheap.
MAX_COMMAND_LEN=16384

SUBJECT=$(hook::extract_bash_subject "Bash" "$COMMAND")

# Emit one telemetry envelope: $1 status, $2 form ("" when not blocked). Gated
# on the high-res start stamp and the opt-in sink, so the unwired default path
# spawns no telemetry-only subprocess.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:"Bash",subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-dangerous-git" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the HOOK_BLOCK_DANGEROUS_GIT_ALLOW comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${HOOK_BLOCK_DANGEROUS_GIT_ALLOW:-},"
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

# Is an operand a worktree-wide pathspec? `.` from the repo root, the
# root-magic short form `:/`, and long-form magic whose comma list carries
# `top` in any position (`:(top)`, `:(literal,top)` — gitglossary pathspec
# magic) all address the whole tree.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_tree_wide_pathspec() {
  local magic
  case "$1" in
  "." | ":/") return 0 ;;
  ":("*")"*)
    magic="${1#:(}"
    magic="${magic%%)*}"
    [[ ",${magic}," == *",top,"* ]]
    ;;
  *) return 1 ;;
  esac
}

# Inspect one already-tokenized segment (its argv words passed as "$@"). Blocks
# when the segment is a real git invocation carrying a default-blocked
# irreversible form. Parsing spine lives in hook-utils.sh; only the form
# matching is this guard's own.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local nseg gi k x rest ch sub sub_idx staged worktree

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  # env -S splicing may have rewritten the argv — match on the resolved words.
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX

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
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*) ;;
      *)
        if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 2 \
          || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
          return 0
        fi
        ;;
      esac
      ((k++))
    done
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      -o | --push-option | --repo | --receive-pack | --exec)
        ((k += 2))
        continue
        ;;
      -o?* | --push-option=* | --repo=* | --receive-pack=* | --exec=*)
        ((k++))
        continue
        ;;
      --force)
        block "push-force" \
          "BLOCKED: git push --force is irreversible for anyone sharing the branch." \
          "Use --force-with-lease (refuses to clobber unseen remote work), or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force."
        ;;
      --force-with-lease | --force-with-lease=* | --force-if-includes) ;;
      +*)
        block "push-force" \
          "BLOCKED: a leading + on a push refspec is a force-push (same as --force)." \
          "Drop the + or use --force-with-lease, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force."
        ;;
      -[A-Za-z]*)
        if [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "push-force" \
            "BLOCKED: git push -f is irreversible for anyone sharing the branch." \
            "Use --force-with-lease (refuses to clobber unseen remote work), or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force."
        fi
        ;;
      *)
        if abbrev_match "mirror" "$x" 2; then
          block "push-force" \
            "BLOCKED: git push --mirror force-updates every remote ref." \
            "Push specific refs instead, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=push-force."
        fi
        ;;
      esac
      ((k++))
    done
    ;;
  reset)
    # --hard and its accepted unique abbreviations (git parse-options accepts
    # any unambiguous prefix: `reset --h` runs --hard, verified empirically).
    # --pathspec-from-file consumes the next word as its value.
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      if [[ "$x" == "--pathspec-from-file" ]]; then
        ((k++))
        continue
      fi
      abbrev_match "hard" "$x" 1 && block "reset-hard" \
        "BLOCKED: git reset --hard discards uncommitted work with no recovery path." \
        "Commit or stash first (git stash push -u), use git reset --keep, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=reset-hard."
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
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      case "$x" in
      -e | --exclude)
        ((k++))
        continue
        ;;
      -e?* | --exclude=*) continue ;;
      *) ;;
      esac
      if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 1 \
        || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
        return 0
      fi
    done
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      case "$x" in
      -e | --exclude)
        ((k++))
        continue
        ;;
      -e?* | --exclude=*) continue ;;
      *) ;;
      esac
      if abbrev_match "force" "$x" 1 || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
        block "clean-force" \
          "BLOCKED: git clean with a force flag permanently deletes untracked files." \
          "Preview with git clean -n first; then allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=clean-force if intended."
      fi
    done
    ;;
  checkout)
    # Worktree-wide discard: a tree-wide pathspec operand, or a forced
    # checkout (`-f`/`--force` throws away local modifications even while
    # switching branches). Path-scoped checkouts (`checkout .github/x`)
    # tokenize as different words and never match. Skip values of
    # value-taking options so a branch named "." cannot be created but its
    # option value never false-matches the operand scan.
    k=$((sub_idx + 1))
    while ((k < nseg)); do
      x="${w[k]}"
      case "$x" in
      -b | -B | --orphan | --conflict | --pathspec-from-file)
        ((k += 2))
        continue
        ;;
      # Attached branch-name values (`-bname`) are values, not flag bundles.
      -b?* | -B?*)
        ((k++))
        continue
        ;;
      *)
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 \
          || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
          block "checkout-force" \
            "BLOCKED: git checkout -f/--force throws away local modifications." \
            "Commit or stash first, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=checkout-force."
        fi
        is_tree_wide_pathspec "$x" && block "checkout-dot" \
          "BLOCKED: a worktree-wide git checkout pathspec discards every unstaged change." \
          "Checkout specific paths, stash first, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=checkout-dot."
        ;;
      esac
      ((k++))
    done
    ;;
  switch)
    # switch -f/--force (alias --discard-changes) throws away local
    # modifications the same way forced checkout does. `--d` alone is
    # ambiguous with --detach, so the abbreviation floor is --disc.
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 \
        || abbrev_match "discard-changes" "$x" 4 \
        || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
        block "checkout-force" \
          "BLOCKED: git switch -f/--discard-changes throws away local modifications." \
          "Commit or stash first, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=checkout-force."
      fi
    done
    ;;
  restore)
    # `restore .` discards the worktree unless the restore is staged-only
    # (--staged without --worktree restores the index from HEAD — reversible).
    staged=0
    worktree=0
    for ((k = sub_idx + 1; k < nseg; k++)); do
      x="${w[k]}"
      case "$x" in
      --staged) staged=1 ;;
      --worktree) worktree=1 ;;
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
      k=$((sub_idx + 1))
      while ((k < nseg)); do
        x="${w[k]}"
        case "$x" in
        -s | --source)
          ((k += 2))
          continue
          ;;
        *)
          is_tree_wide_pathspec "$x" && block "restore-dot" \
            "BLOCKED: a worktree-wide git restore pathspec discards every unstaged change." \
            "Restore specific paths, stash first, or allow via HOOK_BLOCK_DANGEROUS_GIT_ALLOW=restore-dot."
          ;;
        esac
        ((k++))
      done
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
  echo "Shorten the command, or set HOOK_BLOCK_DANGEROUS_GIT_ENABLED=false to bypass." >&2
  emit_tel "blocked" "too-long"
  exit 2
fi

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
