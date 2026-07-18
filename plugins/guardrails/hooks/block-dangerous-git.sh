#!/usr/bin/env bash
# PreToolUse hook: block irreversible git operations on Bash tool calls.
#
# Default block-list is irreversible-only (form tokens):
#   push-force     — git push --force / -f / +refspec / --mirror (NOT --force-with-lease)
#   reset-hard     — git reset --hard
#   clean-force    — git clean with a force flag (-f, -fd, -fdx, --force)
#   checkout-dot   — git checkout .  (worktree-wide discard; path-scoped is fine)
#   restore-dot    — git restore .   (worktree discard; --staged-only is fine)
#   checkout-force — git checkout -f / switch -f/--discard-changes
#
# NOT blocked: --force-with-lease (safe force), plain push, soft/mixed reset,
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
  abbrev_match "push-option" "$x" 2 || abbrev_match "repo" "$x" 3 \
    || abbrev_match "receive-pack" "$x" 4 || abbrev_match "exec" "$x" 1
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

# Inspect one already-tokenized segment (its argv words passed as "$@"). Blocks
# when the segment is a real git invocation carrying a default-blocked
# irreversible form. Parsing spine lives in hook-utils.sh; only the form
# matching is this guard's own.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local nseg gi k x rest ch sub sub_idx staged worktree dry excl pos opseen

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

  # An inline alias runs its expansion (`git -c alias.rh='reset --hard' rh`
  # discards — verified), so re-check the expanded command: a shell alias
  # (leading !) re-parses as a full shell command; a git alias splices its
  # words in place of the alias name. One level only — git does not expand
  # the first word of an expansion as another alias — enforced through
  # HOOK_NO_ALIAS, which dynamic scoping carries into the recursive call.
  if ((${HOOK_NO_ALIAS:-0} == 0)); then
    local cv exp reparse a
    local -a cfgv=() expw=()
    cfgv=(${HOOK_GIT_CONFIG_VALUES[@]+"${HOOK_GIT_CONFIG_VALUES[@]}"})
    for cv in ${cfgv[@]+"${cfgv[@]}"}; do
      [[ "$cv" == "alias.${sub}="* ]] || continue
      exp="${cv#*=}"
      if [[ "$exp" == '!'* ]]; then
        # Shell alias: git runs the expansion as a shell command with the
        # invocation's trailing args appended (positional), so append them
        # (shell-quoted) before re-parsing the whole string as a command.
        reparse="${exp#!}"
        for a in "${w[@]:sub_idx+1}"; do reparse+=" $(printf '%q' "$a")"; done
        hook::bash_parse_segments "$reparse" check_segment
      else
        # Git alias: its expansion is dequoted with shell quoting rules
        # (so `push "--force"` yields --force, not "--force"). Splice the
        # dequoted words in place of the alias name and keep the trailing
        # invocation args, which git appends to the expanded argv.
        hook::env_s_split "$exp"
        expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
        HOOK_NO_ALIAS=1
        check_segment "${w[@]:0:gi+1}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}"
        HOOK_NO_ALIAS=0
      fi
      break
    done
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
    dry=0
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
        ;;
      --*)
        if is_push_value_opt "$x"; then
          ((k += 2))
          continue
        fi
        ;;&
      *)
        if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 2 \
          || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
          dry=1
        fi
        ;;
      esac
      ((k++))
    done
    ((dry)) && return 0
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
      --force-with-lease | --force-with-lease=* | --force-if-includes) ;;
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
        if abbrev_match "mirror" "$x" 2; then
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
      if [[ "$x" == "-n" ]] || abbrev_match "dry-run" "$x" 1 \
        || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *n* ]]; then
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
        if [[ "$x" != *=* ]] \
          && { abbrev_match "conflict" "$x" 1 || abbrev_match "orphan" "$x" 2; }; then
          ((k += 2))
          continue
        fi
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 \
          || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
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
    # ambiguous with --detach, so the abbreviation floor is --disc.
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
        if [[ "$x" == "-f" ]] || abbrev_match "force" "$x" 1 \
          || abbrev_match "discard-changes" "$x" 4 \
          || [[ "$x" =~ ^-[A-Za-z]+$ && "$x" == *f* ]]; then
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
          if [[ "$x" != *=* ]] \
            && { abbrev_match "source" "$x" 2 || abbrev_match "conflict" "$x" 1; }; then
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

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
