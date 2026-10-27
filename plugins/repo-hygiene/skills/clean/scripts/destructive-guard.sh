#!/usr/bin/env bash
# Session-scoped PreToolUse guard registered via SKILL.md frontmatter hooks;
# a run-open marker scopes it to a clean run.
# Blocks destructive Bash and PowerShell commands unless the invocation is
# acknowledged with a CLEAN_GUARD_ACK=1 assignment at the very start of the
# command, which the skill body adds ONLY after the dry-run -> user-confirmation
# gate has passed. The spelling is per tool, because each one has to be a real
# assignment that takes effect for the command it prefixes:
#   Bash tool:        CLEAN_GUARD_ACK=1 <command>
#   PowerShell tool:  $env:CLEAN_GUARD_ACK=1; <command>
# Each spelling is accepted only on the tool that runs it, and only that tool.
# Any other `tool_name`, including a missing one, gets no acknowledgement path:
# the guard still blocks, it just offers nothing to unblock with. A third shell
# tool has to be added to the dispatch deliberately before it gets an ack.
#
# Usage: destructive-guard.sh [--help]   (normally invoked by the hook runner
#        with PreToolUse JSON on stdin)
# Exit codes: 0 = allow, 2 = block (stderr reason returned to Claude)

# Threat model: this is a best-effort NET, not a security boundary. It matches
# command words, so obfuscation (base64, aliases, a command built in a variable)
# bypasses it by design. On the Bash tool the command lines a segment hands on
# are parsed in turn (guard_parse below): a $() or backtick substitution bash
# expands (in double quotes or an unquoted here-doc body), every eval operand, a
# shell's -c operand behind any wrapper (sudo, timeout, env, xargs), an ssh
# remote command, and the script a shell or ssh reads from stdin: a here-string,
# a here-doc, or the segment piped into it. A script that reaches a shell any
# other way (a file, a longer pipeline, process substitution) is not read.
# Basis: the Bash manual's Double Quotes,
# Redirections, Invoking Bash and eval pages, and ssh(1), read 2026-10-27.
# Recheck: ssh(1) changes which options take a value. The goal is to catch the common
# destructive spellings an agent might fumble and route them through the clean
# skill's confirmation gate. The durable destructive-op boundary is the consumer's own
# settings.json permissions.deny plus their git hooks, which apply independent
# of clean-session state. Coverage is whatever is_destructive() and
# argv_destructive() list.
#
# Lifetime. Decision: a run-open marker scopes the guard, so the guard does not
# depend on when the host ends skill hooks. The marker is per session,
# <CLAUDE_PLUGIN_DATA>/clean-run/<session_id>.open, which clean-run-marker.sh
# writes when a mutating tier starts (never for scan or
# scan-batch) and removes when the run reaches its final outcome. With no marker
# for the hook input's session_id the guard allows the command. A marker idle for
# RUN_MARKER_IDLE_SECONDS (lib/run-marker.sh) is deleted and the command allowed;
# a call that runs one of the skill's mutating scripts (dry-run included) refreshes
# the marker, even a stale one, as does an acknowledged or destructive call;
# ordinary calls do not. An unresolved CLAUDE_PLUGIN_DATA (unset, or one whose
# last path segment does not name this plugin: run_marker_data_dir_ours), a
# hook-utils.sh that did not load, or a
# missing or unusable session_id keeps the guard armed (fail closed), and so does
# the no-jq mode, which cannot read the session_id. The marker cases are in
# destructive-guard.test.sh.
# Upstream hook lifetime and environment for skill-frontmatter hooks: read them
# live at https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents
# As of 2026-10-20.
# Recheck: the hooks page changes how skill hooks end, or the first live run
# shows the guard armed with no marker.
#
# Precision. On the Bash tool is_destructive_bash() runs argv_destructive() over
# each segment's argv from hook::bash_parse_segments, so destructive text inside
# one quoted argument (a `gh issue comment --body '... git branch -D ...'`) is a
# single inert word and does not match. The PowerShell tool and the other tools
# keep raw-string matching in is_destructive().
#
# Branch deletion. Claim: as of 2026-09-29 this net matches bare
# `git branch -D`/`-d`/`--delete`, and `git push --delete`, `push -d` and
# `git push origin :ref` (also `+:ref`). A push with --dry-run/-n is a preview and is allowed.
# The CLEAN_GUARD_ACK path lifts these blocks like every other, and the
# ack-prefixed spelling is the documented way to run a bare `git branch -D`
# during a clean session. A git alias is not resolved, so one that deletes is
# not blocked. Local deletion through
# git-branch-delete.sh runs `git update-ref -d`, so the confirmed path does not
# go through these patterns. Basis: is_destructive() below and the branch and
# push block cases in destructive-guard.test.sh. Recheck: is_destructive()
# changes.
#
# Apply scripts and forced worktree removal. Claim: as of 2026-09-29 the guard
# matches the seven mutating scripts of the clean skill (clean-caches,
# clean-build, git-prune, git-tree-reset, git-tree-reset-batch, remove-path,
# clean-batch) in their --apply spelling, and `git worktree remove` with a
# force flag. A dry-run of those scripts is allowed so the confirmation gate can
# still run, and the ack prefix lifts either block after the gate. Basis:
# is_destructive() below and section 2e of destructive-guard.test.sh. Recheck:
# is_destructive() changes.

set -uo pipefail

# Builtins only: the no-jq test runs this script with a PATH that lacks dirname.
_src="${BASH_SOURCE[0]}"
[[ "$_src" == */* ]] || _src="./$_src"
SCRIPT_DIR="$(cd "${_src%/*}" && pwd)"
# shellcheck source=lib/run-marker.sh
source "$SCRIPT_DIR/lib/run-marker.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Drain stdin before any early exit so a pipefail producer never SIGPIPEs.
INPUT="$(cat)"

if [[ "${CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED:-true}" == "false" ]]; then
  exit 0
fi

# rm's recursive (-r/-R/--recursive) and force (-f/--force) flags are matched
# independently, so separated, reordered, capitalized, and long spellings are
# caught — not only the adjacent -rf cluster. git's destructive subcommands
# tolerate global options (-C <path>, -c <cfg>, --git-dir=… or --git-dir <path>,
# flag-only ones such as --no-pager) between `git` and the subcommand; the ones
# read with a separate value are hook::git_resolve_subcommand's list in
# hook-utils.sh. git clean keys on the force flag (-f/--force) only: -x/-X/-d
# without force are git no-ops, so blocking them (including dry-run -nx) is a
# false positive.
# The clean skill's mutating scripts: their names, and their basenames anywhere
# in the raw text.
CLEAN_SCRIPT_NAMES='clean-caches|clean-build|git-prune|git-tree-reset-batch|git-tree-reset|remove-path|clean-batch'
CLEAN_SCRIPT_RE="(^|[[:space:][:punct:]])(${CLEAN_SCRIPT_NAMES})\\.sh([^[:alnum:]_.-]|$)"

is_destructive() {
  local cmd="$1"
  local gopt='((-C|-c|--(config|config-env|git-dir|work-tree|namespace|super-prefix|attr-source|exec-path))[[:space:]]+[^[:space:]]+[[:space:]]+|--[a-zA-Z-]+=[^[:space:]]+[[:space:]]+|(-[pP]|--[a-zA-Z-]+)[[:space:]]+)*'
  local force_re='[[:space:]]-[a-zA-Z]*f|[[:space:]]--force([^[:alnum:]_-]|$)'
  if grep -qE '(^|[[:space:];&|(])rm[[:space:]]' <<<"$cmd" &&
    grep -qE '[[:space:]]-[a-zA-Z]*[rR]|[[:space:]]--recursive([[:space:]]|=|$)' <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}clean[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  # Basename plus --apply, so a path prefix and a dry-run do not both fire.
  # git-tree-reset-batch is its own alternative: git-tree-reset.sh does not
  # match the batch script, because `.sh` has to follow the name.
  if grep -qE "$CLEAN_SCRIPT_RE" <<<"$cmd" &&
    grep -qE '(^|[^[:alnum:]_-])--apply([^[:alnum:]_-]|$)' <<<"$cmd"; then
    return 0
  fi
  if grep -qE "git[[:space:]]+${gopt}worktree[[:space:]]+remove[[:space:]]" <<<"$cmd" &&
    grep -qE "$force_re" <<<"$cmd"; then
    return 0
  fi
  # Branch deletion: a -d/-D short-flag cluster or --delete after `branch`, in the
  # same statement (a `;`, `&` or `|` ends it, so `xargs -d` after a pipe is not read).
  if grep -qE "git[[:space:]]+${gopt}branch[[:space:]]([^;&|]*[[:space:]])?['\"]?(--delete|-[a-zA-Z]*[dD])" <<<"$cmd"; then
    return 0
  fi
  # Remote deletion: `push --delete`, a -d cluster, or a `:ref` or `+:ref` refspec.
  # A dry-run (--dry-run, or an -n cluster with no -o push option) in the same push
  # statement is a preview and stays allowed.
  local push
  while IFS= read -r push; do
    if grep -qE "[[:space:]](['\"]?(--delete|-[a-np-zA-Z]*d)|['\"]?[+]?['\"]?:[^[:space:]'\"])" <<<"$push" &&
      ! grep -qE '[[:space:]](--dry-run|-[a-np-zA-Z]*n[a-np-zA-Z]*)([[:space:]]|$)' <<<"$push"; then
      return 0
    fi
  done < <(grep -oE "git[[:space:]]+${gopt}push[[:space:]][^;&|]*" <<<"$cmd")
  grep -qE "git[[:space:]]+${gopt}reset[[:space:]]+--hard|git[[:space:]]+${gopt}checkout[[:space:]]+--[[:space:]]|git[[:space:]]+${gopt}stash[[:space:]]+(drop|clear)([[:space:]]|$)|Remove-Item[[:space:]].*-Recurse" <<<"$cmd"
}

# argv_destructive <word>... : the same coverage as is_destructive(), over one
# parsed segment's argv. Every test is on a whole word, so destructive text that
# sits inside one quoted argument never matches. Returns 0 when destructive.
# Needs hook-utils.sh to be sourced.
argv_destructive() {
  local -a w=("$@")
  local n=${#w[@]} i j sub word base script=0 apply=0
  local -a rest
  local recursive force dry del
  for ((i = 0; i < n; i++)); do
    word="${w[i]}"
    base="${word##*/}"
    base="${base##*\\}"
    [[ "$word" == "--apply" ]] && apply=1
    case "$base" in
    clean-caches.sh | clean-build.sh | git-prune.sh | git-tree-reset-batch.sh | git-tree-reset.sh | remove-path.sh | clean-batch.sh)
      script=1
      ;;
    rm)
      recursive=0 force=0
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" =~ ^-[a-zA-Z]*[rR] || "${w[j]}" =~ ^--recursive(=.*)?$ ]] && recursive=1
        [[ "${w[j]}" =~ ^-[a-zA-Z]*f || "${w[j]}" == --force ]] && force=1
      done
      ((recursive && force)) && return 0
      ;;
    Remove-Item)
      for ((j = i + 1; j < n; j++)); do
        [[ "${w[j]}" == -Recurse* ]] && return 0
      done
      ;;
    git)
      # The subcommand past git's global options, a separate value included.
      hook::git_resolve_subcommand "$i" "${w[@]}" || continue
      sub="$HOOK_GIT_SUB"
      rest=("${w[@]:HOOK_GIT_SUB_IDX+1}")
      force=0
      for word in "${rest[@]}"; do
        [[ "$word" =~ ^-[a-zA-Z]*f || "$word" == --force ]] && force=1
      done
      case "$sub" in
      clean)
        ((force)) && return 0
        ;;
      worktree)
        [[ "${rest[0]:-}" == remove ]] && ((force)) && return 0
        ;;
      branch)
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^-[a-zA-Z]*[dD] || "$word" =~ ^--delete ]] && return 0
        done
        ;;
      push)
        # A dry-run (--dry-run, or an -n cluster with no -o push option) is a preview.
        del=0 dry=0
        for word in "${rest[@]}"; do
          [[ "$word" =~ ^--delete || "$word" =~ ^-[a-np-zA-Z]*d || "$word" =~ ^[+]?:. ]] && del=1
          [[ "$word" == --dry-run || "$word" =~ ^-[a-np-zA-Z]*n[a-np-zA-Z]*$ ]] && dry=1
        done
        ((del && !dry)) && return 0
        ;;
      reset)
        [[ "${rest[0]:-}" == --hard ]] && return 0
        ;;
      checkout)
        [[ "${rest[0]:-}" == -- ]] && return 0
        ;;
      stash)
        [[ "${rest[0]:-}" == drop || "${rest[0]:-}" == clear ]] && return 0
        ;;
      *) ;;
      esac
      ;;
    *) ;;
    esac
  done
  ((script && apply)) && return 0
  return 1
}

# A command line nested deeper than GUARD_DEPTH_MAX is not decided, so it blocks.
ARGV_HIT=0
GUARD_DEPTH=0
GUARD_DEPTH_MAX=32

# guard_parse <command-line> : argv_segment over each segment of the line, then
# guard_parse over each substitution bash expands in it. Needs hook-utils.sh.
guard_parse() {
  ((ARGV_HIT)) && return 0
  if ((GUARD_DEPTH >= GUARD_DEPTH_MAX)); then
    ARGV_HIT=1
    return 0
  fi
  GUARD_DEPTH=$((GUARD_DEPTH + 1))
  # argv_segment's state across the segments of this line (dynamic scope): the
  # segment before the one it reads, with that segment's here-strings and
  # here-doc numbers, the here-docs counted so far, and the numbers of the
  # here-docs a command runs as its script.
  local -a _gp_prev=() _gp_prev_hs=() _gp_prev_hd=() _gp_hd_feed=() _gp_subs=() _gp_bodies=()
  local _gp_hd_seen=0 _gp_s _gp_e _gp_start _gp_end
  hook::bash_parse_segments "$1" argv_segment
  _gp_bodies=(${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"})
  # A here-doc on a segment with no command word reaches no callback, so the
  # count no longer numbers the bodies; then every body is read.
  if ((${#_gp_hd_feed[@]} && ${#_gp_bodies[@]} != _gp_hd_seen)); then
    _gp_hd_feed=("${!_gp_bodies[@]}")
  fi
  for _gp_s in ${_gp_hd_feed[@]+"${_gp_hd_feed[@]}"}; do
    _gp_e="${_gp_bodies[_gp_s]-}"
    [[ -n "$_gp_e" ]] || continue
    _gp_start="${_gp_e%% *}"
    _gp_e="${_gp_e#* }"
    _gp_end="${_gp_e%% *}"
    hook::_c_locale byte_slice_to _gp_e "$1" "$_gp_start" $((_gp_end - _gp_start))
    guard_parse "$_gp_e"
  done
  substitutions_to _gp_subs "$1" ${_gp_bodies[@]+"${_gp_bodies[@]}"}
  for _gp_s in ${_gp_subs[@]+"${_gp_subs[@]}"}; do
    guard_parse "$_gp_s"
  done
  GUARD_DEPTH=$((GUARD_DEPTH - 1))
  return 0
}

# byte_slice_to <var> <string> <offset> [<length>] : bytes of <string> from
# <offset>, the rest or <length> of them. Run under hook::_c_locale, where a
# character is a byte, so the offsets match the parser's.
# shellcheck disable=SC2329  # reached through hook::_c_locale
byte_slice_to() {
  if (($# > 3)); then
    printf -v "$1" '%s' "${2:$3:$4}"
  else
    printf -v "$1" '%s' "${2:$3}"
  fi
}

# substitutions_to <array-var> <command> [<here-doc entry>...] : the command line
# inside each $() and backtick substitution bash expands within double quotes or
# an unquoted here-doc body of <command>. The entries are the parser's
# HOOK_HEREDOC_BODIES for <command>, in byte offsets, so the scan is over bytes
# too. Single quotes, $'' and a quoted here-doc body expand nothing. An unquoted
# substitution is already its own segment to the parser, so only its inside is
# scanned. A nested substitution stays in its operand, for that operand's parse.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
substitutions_to() {
  local -n _st_out="$1"
  local cmd="$2"
  shift 2
  local -a chars=() bodies=("$@")
  local n i=0 b=0 nb=$# dq=0 hd=0 hd_end=0 c rest start j s
  _st_out=()
  # The parser's own byte split, into this function's chars (dynamic scope).
  hook::_bps_chars "$cmd"
  n=${#chars[@]}
  while ((i < n)); do
    ((hd && i >= hd_end)) && hd=0
    if ((!hd && b < nb)); then
      start="${bodies[b]%% *}"
      if ((i >= start)); then
        rest="${bodies[b]#* }"
        hd_end="${rest%% *}"
        rest="${rest#* }"
        b=$((b + 1))
        if [[ "${rest%% *}" == 1 ]]; then
          i=$hd_end
          continue
        fi
        hd=1
      fi
    fi
    c="${chars[i]}"
    case "$c" in
    '\')
      i=$((i + 2))
      continue
      ;;
    "'")
      if ((!dq && !hd)); then
        i=$((i + 1))
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do i=$((i + 1)); done
      fi
      ;;
    '"')
      ((hd)) || dq=$((!dq))
      ;;
    '$')
      if ((dq || hd)) && [[ "${chars[i + 1]-}" == '(' ]]; then
        subst_end_to j $((i + 2))
        hook::_c_locale byte_slice_to s "$cmd" $((i + 2)) $((j - i - 2))
        _st_out+=("$s")
        i=$j
      elif ((!dq && !hd)) && [[ "${chars[i + 1]-}" == "'" ]]; then
        i=$((i + 2))
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
          [[ "${chars[i]}" == '\' ]] && i=$((i + 1))
          i=$((i + 1))
        done
      fi
      ;;
    '`')
      if ((dq || hd)); then
        s=""
        for ((i++; i < n; i++)); do
          [[ "${chars[i]}" == '`' ]] && break
          [[ "${chars[i]}" == '\' && "${chars[i + 1]-}" == [\$\`\\\"] ]] && i=$((i + 1))
          s+="${chars[i]}"
        done
        _st_out+=("$s")
      fi
      ;;
    '#')
      if ((!dq && !hd)) && { ((i == 0)) || [[ "${chars[i - 1]}" == [[:space:]\;\&\|\(\)] ]]; }; then
        while ((i + 1 < n)) && [[ "${chars[i + 1]}" != $'\n' ]]; do i=$((i + 1)); done
      fi
      ;;
    *) ;;
    esac
    i=$((i + 1))
  done
}

# subst_end_to <var> <from> : the index of the `)` that closes a $( whose text
# starts at <from> in substitutions_to's cmd and chars (dynamic scope), or the
# end of the text when none does. Quoted spans, escapes, comments and here-doc
# bodies inside it hold no paren. Only a span holding `<<` pays for the parse
# that finds the bodies.
subst_end_to() {
  local -n _se_out="$1"
  local from="$2" close tail e
  local -a hs=() he=()
  paren_close_to close "$from"
  hook::_c_locale byte_slice_to tail "$cmd" "$from" $((close - from))
  if [[ "$tail" == *'<<'* ]]; then
    hook::_c_locale byte_slice_to tail "$cmd" "$from"
    hook::bash_parse_segments "$tail" :
    for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
      hs+=("$((from + ${e%% *}))")
      e="${e#* }"
      he+=("$((from + ${e%% *}))")
    done
    paren_close_to close "$from"
  fi
  _se_out=$close
}

# paren_close_to <var> <from> : subst_end_to's scan, skipping the here-doc
# bodies in its hs and he (dynamic scope).
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
paren_close_to() {
  local -n _pc_out="$1"
  local k="$2" depth=1 hb=0
  while ((k < n)); do
    if ((hb < ${#hs[@]} && k >= hs[hb])); then
      k=${he[hb]}
      hb=$((hb + 1))
      continue
    fi
    case "${chars[k]}" in
    '#')
      if [[ "${chars[k - 1]}" == [[:space:]\;\&\|\(\)] ]]; then
        while ((k + 1 < n)) && [[ "${chars[k + 1]}" != $'\n' ]]; do k=$((k + 1)); done
      fi
      ;;
    '\') k=$((k + 1)) ;;
    "'")
      k=$((k + 1))
      while ((k < n)) && [[ "${chars[k]}" != "'" ]]; do k=$((k + 1)); done
      ;;
    '"')
      k=$((k + 1))
      while ((k < n)) && [[ "${chars[k]}" != '"' ]]; do
        [[ "${chars[k]}" == '\' ]] && k=$((k + 1))
        k=$((k + 1))
      done
      ;;
    '(') depth=$((depth + 1)) ;;
    ')')
      depth=$((depth - 1))
      ((depth)) || break
      ;;
    *) ;;
    esac
    k=$((k + 1))
  done
  _pc_out=$k
}

# shell_reads_stdin <word>... : 0 when a shell given these arguments reads its
# commands from stdin: -s, or no operand left after the options.
shell_reads_stdin() {
  local -a a=("$@")
  local n=$# i=0 s=0
  while ((i < n)); do
    case "${a[i]}" in
    --)
      i=$((i + 1))
      break
      ;;
    -o | +o | -O | +O | --rcfile | --init-file) i=$((i + 2)) ;;
    -* | +*)
      [[ "${a[i]}" =~ ^-[A-Za-z]*s[A-Za-z]*$ ]] && s=1
      i=$((i + 1))
      ;;
    *) break ;;
    esac
  done
  ((s || i >= n))
}

# ssh_command_to <var> <word>... : the remote command line of an ssh whose
# arguments are <word>...: the words after the destination, joined by spaces,
# empty when there are none. Returns 1 when no destination is given. The options
# that take a value are the ones ssh(1)'s SYNOPSIS shows with one.
ssh_command_to() {
  local -n _sc_out="$1"
  shift
  local -a a=("$@")
  local n=$# i=0 k t IFS=' '
  _sc_out=""
  while ((i < n)) && [[ "${a[i]}" == -* ]]; do
    t="${a[i]}"
    i=$((i + 1))
    [[ "$t" == -- ]] && break
    for ((k = 1; k < ${#t}; k++)); do
      case "${t:k:1}" in
      [BbcDEeFIiJLlmOoPpQRSWw])
        ((k + 1 < ${#t})) || i=$((i + 1))
        break
        ;;
      *) ;;
      esac
    done
  done
  ((i < n)) || return 1
  _sc_out="${a[*]:i+1}"
}

# shell_name_to <var> <word> : <word>'s basename, case-folded and without .exe,
# for matching a shell, eval or ssh by name.
shell_name_to() {
  local -n _sn_out="$1"
  _sn_out="${2##*/}"
  _sn_out="${_sn_out##*\\}"
  _sn_out="${_sn_out,,}"
  _sn_out="${_sn_out%.exe}"
}

# stdin_script_reader <word>... : 0 when the segment's command, past leading
# assignments and wrapper commands, runs its stdin as a script: a shell with no
# -c and no script operand, or an ssh with a destination and no remote command.
# A wrapper option that takes a separate value (sudo -u root) ends the walk.
stdin_script_reader() {
  local -a w=("$@")
  local n=$# i=0 wrapped=0 name line
  while ((i < n)); do
    shell_name_to name "${w[i]}"
    if [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; then
      :
    elif ((wrapped)) && [[ "${w[i]}" == -* || "${w[i]}" =~ ^[0-9.]+[smhd]?$ ]]; then
      :
    else
      case "$name" in
      sudo | doas | env | timeout | nice | nohup | time | command | exec | stdbuf | setsid) wrapped=1 ;;
      *) break ;;
      esac
    fi
    i=$((i + 1))
  done
  ((i < n)) || return 1
  case "$name" in
  bash | sh | zsh | dash | ksh | mksh) shell_reads_stdin "${w[@]:i+1}" ;;
  ssh) ssh_command_to line "${w[@]:i+1}" && [[ -z "$line" ]] ;;
  *) return 1 ;;
  esac
}

# argv_segment <word>... : hook::bash_parse_segments callback. Sets ARGV_HIT when
# the segment is destructive, or a command line it hands on is: an eval operand,
# an ssh remote command or a shell's -c operand anywhere in the segment, and the
# script a stdin_script_reader runs: its own here-strings and here-docs, and what
# the segment before it writes (a pipe into it; the parser does not say which
# operator joined them, so a `;` reads the same): that segment's operands,
# escapes decoded as printf writes them, here-strings and here-docs.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
argv_segment() {
  ((ARGV_HIT)) && return 0
  local -a w=("$@") prev=(${_gp_prev[@]+"${_gp_prev[@]}"})
  local -a prev_hs=(${_gp_prev_hs[@]+"${_gp_prev_hs[@]}"}) prev_hd=(${_gp_prev_hd[@]+"${_gp_prev_hd[@]}"})
  local -a ops=(${HOOK_SEG_REDIR_OP[@]+"${HOOK_SEG_REDIR_OP[@]}"})
  local -a targets=(${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"})
  local -a hs=() hd=()
  local n=$# i j name line dec
  for ((j = 0; j < ${#ops[@]}; j++)); do
    case "${ops[j]}" in
    '<<' | '<<-')
      hd+=("$_gp_hd_seen")
      _gp_hd_seen=$((_gp_hd_seen + 1))
      ;;
    '<<<') hs+=("${targets[j]}") ;;
    *) ;;
    esac
  done
  _gp_prev=("$@")
  _gp_prev_hs=(${hs[@]+"${hs[@]}"})
  _gp_prev_hd=(${hd[@]+"${hd[@]}"})
  if argv_destructive "$@"; then
    ARGV_HIT=1
    return 0
  fi
  # The first command line handed on holds every word after it, so the walk
  # stops there: each later eval or shell would only be parsed again.
  for ((i = 0; i < n; i++)); do
    shell_name_to name "${w[i]}"
    case "$name" in
    eval)
      guard_parse "${w[*]:i+1}"
      break
      ;;
    ssh)
      if ssh_command_to line "${w[@]:i+1}" && [[ -n "$line" ]]; then
        guard_parse "$line"
        break
      fi
      ;;
    bash | sh | zsh | dash | ksh | mksh | wsl)
      if hook::shell_c_operand "${w[@]:i}"; then
        guard_parse "$HOOK_SHELL_C_OPERAND"
        break
      fi
      ;;
    *) ;;
    esac
  done
  ((ARGV_HIT)) && return 0
  stdin_script_reader "$@" || return 0
  _gp_hd_feed+=(${hd[@]+"${hd[@]}"} ${prev_hd[@]+"${prev_hd[@]}"})
  for line in ${hs[@]+"${hs[@]}"} ${prev_hs[@]+"${prev_hs[@]}"}; do
    guard_parse "$line"
  done
  line=""
  for ((j = 1; j < ${#prev[@]}; j++)); do
    hook::ansi_c_decode_to dec "${prev[j]}"
    line+="$dec "
  done
  [[ -z "$line" ]] || guard_parse "$line"
  return 0
}

SCRIPT_HIT=0
# script_segment <word>... : hook::bash_parse_segments callback. Sets SCRIPT_HIT
# when the segment runs one of the skill's mutating scripts: the script is the
# command word, or the first operand of a shell at the command position. Leading
# VAR=val words are skipped and `bash -c` operands re-parsed, as
# hook::shell_c_operand does; a wrapper in front (sudo, env) is not resolved.
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
script_segment() {
  ((SCRIPT_HIT)) && return 0
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" script_segment
    return 0
  fi
  local -a w=("$@")
  local n=${#w[@]} i=0 base
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done
  base="${w[i]:-}"
  base="${base##*/}"
  base="${base##*\\}"
  case "$base" in
  bash | sh)
    for ((i++; i < n; i++)); do [[ "${w[i]}" == -* ]] || break; done
    base="${w[i]:-}"
    base="${base##*/}"
    base="${base##*\\}"
    ;;
  *) ;;
  esac
  [[ "$base" =~ ^(${CLEAN_SCRIPT_NAMES})\.sh$ ]] && SCRIPT_HIT=1
  return 0
}

# invokes_clean_script <command> : 0 when a segment of the command runs one of
# the skill's mutating scripts. Needs hook-utils.sh to be sourced.
invokes_clean_script() {
  SCRIPT_HIT=0
  hook::bash_parse_segments "$1" script_segment
  ((SCRIPT_HIT))
}

# is_destructive_bash <command> : is_destructive() for the Bash tool, over parsed
# segments instead of the raw string. Needs hook-utils.sh to be sourced.
is_destructive_bash() {
  ARGV_HIT=0
  GUARD_DEPTH=0
  guard_parse "$1"
  ((ARGV_HIT))
}

# jq parses the hook payload. Without it the ack prefix cannot be verified, so
# the guard degrades FAIL-CLOSED: destructive patterns matched against the raw
# JSON payload block unconditionally (no ack path) until jq is installed. JSON
# escaping (e.g. tabs as \t) can hide whitespace from the patterns, so degraded
# coverage is best-effort — but a guard that cannot parse must block what it
# can see, never go silently inert (cf. #983, #532 fail-open class).
if ! command -v jq >/dev/null 2>&1; then
  # Quotes become spaces so the patterns' prefix anchors match a command at the
  # start of a JSON string value ("command":"rm -rf ..." puts a quote before rm).
  if is_destructive "${INPUT//\"/ }"; then
    {
      echo "BLOCKED by the clean skill's destructive guard (degraded mode: jq not found)."
      echo "Without jq the guard cannot verify the CLEAN_GUARD_ACK acknowledgement, so destructive commands are blocked outright."
      echo "Install jq to restore the dry-run -> user-confirmation -> CLEAN_GUARD_ACK=1 flow."
    } >&2
    exit 2
  fi
  exit 0
fi

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[[ -n "$CMD" ]] || exit 0
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
SESSION="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"

# Run-open marker (see Lifetime above). No live marker for this session means no
# clean run is open, so the guard stays out of the way. When the marker path
# cannot be resolved, the guard stays armed.
# refresh_marker: restart the idle clock. Called only on run activity (a call to
# one of the skill's mutating scripts, dry-run included, or an acknowledged or
# destructive command), never on ordinary shell calls.
refresh_marker() {
  [[ -z "$MARKER_FILE" ]] || run_marker_write "$MARKER_FILE"
}

MARKER_FILE="" MARKER_STATE=""
if run_marker_data_dir_ours "${CLAUDE_PLUGIN_DATA:-}" &&
  run_marker_path_to MARKER_FILE "${CLAUDE_PLUGIN_DATA:-}" "$SESSION"; then
  run_marker_state_to MARKER_STATE "$MARKER_FILE"
  [[ "$MARKER_STATE" != absent ]] || exit 0
fi

# shellcheck source=hook-utils.sh
source "$SCRIPT_DIR/hook-utils.sh" || {
  echo "BLOCKED by the clean skill's destructive guard: $SCRIPT_DIR/hook-utils.sh did not load, so the guard cannot read the command." >&2
  exit 2
}

# Running one of the skill's scripts is the run's own step, so it keeps even a
# stale marker: an hour-long confirmation gate still reaches its apply gated.
# A command that only names a script is an ordinary call.
if [[ -n "$MARKER_STATE" ]]; then
  if invokes_clean_script "$CMD"; then
    MARKER_STATE=live
    refresh_marker
  fi
  if [[ "$MARKER_STATE" == stale ]]; then
    rm -f "$MARKER_FILE"
    exit 0
  fi
fi

# Acknowledged path: the skill's confirmation gate prefixes the command with an
# assignment. The ack is a deny-to-allow widening, so it is accepted only as
# the FIRST statement of the command, in the one spelling the executing shell
# actually evaluates as an assignment. Anywhere else (a comment, a quoted
# string, after the destructive command, a later pipeline segment) it is inert
# text and does not count. The other tool's spelling is rejected too: PowerShell
# cannot run `CLEAN_GUARD_ACK=1 <cmd>` at all, and Bash treats
# `$env:CLEAN_GUARD_ACK=1;` as a failed command lookup and runs <cmd> anyway.
#
# The dispatch is default-deny on `tool_name`: each spelling is bound to the one
# tool whose shell evaluates it, and an unrecognized, empty, or absent tool falls
# through to no ack at all. Matching on "not PowerShell" instead would hand the
# Bash spelling to every future tool by default, which is a grant nobody chose.
is_acknowledged() {
  local cmd="$1" tool="$2"
  case "$tool" in
  Bash)
    [[ "$cmd" == CLEAN_GUARD_ACK=1\ * ]]
    ;;
  PowerShell)
    # Optional leading whitespace, `$env:CLEAN_GUARD_ACK`, `=`, the value 1
    # (bare or quoted), then the `;` that ends the statement. Nothing else
    # may come before it.
    # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
    local ps_ack_re='^[[:space:]]*\$env:CLEAN_GUARD_ACK[[:space:]]*=[[:space:]]*(1|'"'"'1'"'"'|"1")[[:space:]]*;'
    [[ "$cmd" =~ $ps_ack_re ]]
    ;;
  *)
    return 1
    ;;
  esac
}

if is_acknowledged "$CMD" "$TOOL"; then
  refresh_marker
  exit 0
fi

DESTRUCTIVE=0
if [[ "$TOOL" == Bash ]]; then
  is_destructive_bash "$CMD" && DESTRUCTIVE=1
else
  is_destructive "$CMD" && DESTRUCTIVE=1
fi
if ((DESTRUCTIVE)); then
  refresh_marker
  # shellcheck disable=SC2016  # literal `$env:` is the PowerShell spelling
  case "$TOOL" in
  Bash) ack_form='CLEAN_GUARD_ACK=1 <command>' ;;
  PowerShell) ack_form='$env:CLEAN_GUARD_ACK=1; <command>' ;;
  *) ack_form='' ;;
  esac
  {
    echo "BLOCKED by the clean skill's destructive guard (session-scoped skill hook)."
    echo "Destructive commands during a clean run go ONLY through the skill's dry-run -> user-confirmation gate."
    if [[ -n "$ack_form" ]]; then
      echo "After the user has explicitly confirmed, re-issue with the acknowledgement prefix for this tool: $ack_form"
    else
      echo "This tool has no acknowledgement path, so there is nothing to re-issue with here. Run the confirmed command through the Bash or PowerShell tool instead."
    fi
  } >&2
  exit 2
fi

exit 0
