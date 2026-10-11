#!/usr/bin/env bash
# PreToolUse(Bash) hook: before a `git push` from a session in this repository,
# run scripts/check-affected.sh and block the push (exit 2, summary on stderr)
# when a check fails, so a lint finding costs a local run instead of a CI round.
#
# Wired in .claude/settings.json with `if: "Bash(git push *)"`, which also
# matches a bare `git push`: a trailing ` *` that is the rule's only wildcard
# matches the bare command
# (https://code.claude.com/docs/en/permissions#wildcard-patterns). That filter is
# best-effort and also fires on any command holding $(), backticks or $VAR
# (https://code.claude.com/docs/en/hooks#bash-if-matching), so this script
# re-checks that a subcommand really is `git push` before it spends a run
# (docs/conventions/hook-precision/README.md, rule 2). A quoted or heredoc
# mention of "git push" is data, not a push.
#
# Stays quiet (exit 0) on: no real push; a push that only deletes remote refs,
# only pushes tags, or is a dry run; a push after a `cd`/`pushd` in the same
# command, whose directory this parser does not track; a push from any working
# tree other than the session's project directory, including another worktree
# of the same clone; a tree with no scripts/check-affected.sh; a payload it
# cannot read; and a check-affected run that could not start (exit 2), since an
# unreadable state is not a finding.
#
# Trust model: it runs scripts/check-affected.sh only from the working tree that
# holds the .claude/settings.json registering this hook and this hook script
# itself. Claude Code runs a project settings file's hooks once the folder is
# trusted, and always in a -p or SDK session
# (https://code.claude.com/docs/en/hooks#workspace-trust), so whatever branch is
# checked out there already decides what this hook does; pinning the script to a
# ref would not narrow that. Running only from that tree adds no code from a
# tree the session did not load its hooks from.
#
# It checks the checked-out HEAD, not a ref the push names: `git push origin
# other-branch` from another branch, or a tag pushed by bare name, is judged by
# HEAD's checks. CI still runs on whatever is pushed.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=../../lib/hook-utils.sh
source "$HOOK_DIR/../../lib/hook-utils.sh" || exit 0

# push_dir_to <out-var> <command>: assigns the -C directory of the first `git
# push` subcommand that sends a branch ("." when it names none) and returns 0;
# returns 1 when no subcommand is such a push.
push_dir_to() {
  local -n __pd_out="$1"
  local cmd="$2" len=${#2} i=0 c q="" word="" in_word=0 heredoc="" line
  local -a words=()
  # Each unquoted separator ends a segment; quoted text stays inside one word,
  # so `echo "git push"` is the command `echo` with one argument.
  flush_word() {
    ((in_word)) && words+=("$word")
    word=""
    in_word=0
  }
  local moved=0
  end_segment() {
    flush_word
    [[ "${words[0]-}" == @(cd|pushd|popd) ]] && moved=1
    if ((!moved && ${#words[@]})) && segment_push_dir __pd_out "${words[@]}"; then
      return 0
    fi
    words=()
    return 1
  }
  while ((i < len)); do
    c="${cmd:i:1}"
    if [[ -n "$q" ]]; then
      if [[ "$c" == "$q" ]]; then
        q=""
      elif [[ "$q" == '"' && "$c" == "\\" ]]; then
        ((i++))
        word+="${cmd:i:1}"
      else
        word+="$c"
      fi
      ((i++))
      continue
    fi
    case "$c" in
    "'" | '"')
      q="$c"
      in_word=1
      ;;
    "\\")
      ((i++))
      word+="${cmd:i:1}"
      in_word=1
      ;;
    ' ' | $'\t') flush_word ;;
    '<')
      if [[ "${cmd:i:2}" == '<<' && "${cmd:i:3}" != '<<<' ]]; then
        # Heredoc: note the delimiter; its body is skipped at the next newline.
        flush_word
        i=$((i + 2))
        [[ "${cmd:i:1}" == '-' ]] && ((i++))
        while [[ "${cmd:i:1}" == ' ' ]]; do ((i++)); done
        heredoc=""
        while ((i < len)) && [[ "${cmd:i:1}" != [[:space:]\;\&\|\)] ]]; do
          [[ "${cmd:i:1}" == [\'\"\\] ]] || heredoc+="${cmd:i:1}"
          ((i++))
        done
        continue
      fi
      flush_word
      ;;
    $'\n' | ';' | '&' | '|' | '(' | ')' | '`')
      end_segment && return 0
      if [[ "$c" == $'\n' && -n "$heredoc" ]]; then
        while ((i < len)); do
          line="${cmd:i+1}"
          line="${line%%$'\n'*}"
          i=$((i + 1 + ${#line}))
          [[ "${line#"${line%%[!$'\t']*}"}" == "$heredoc" ]] && break
        done
        heredoc=""
      fi
      ;;
    *)
      word+="$c"
      in_word=1
      ;;
    esac
    ((i++))
  done
  end_segment
}

# segment_push_dir <out-var> <word>...: 0 and the -C directory when the words
# are a `git push` that sends a branch.
segment_push_dir() {
  local -n __sp_out="$1"
  shift
  local dir="." w
  # Leading assignments and the shell words that precede a command.
  while (($#)); do
    case "$1" in
    [A-Za-z_]*=*) shift ;;
    '{' | '!' | then | do | else | if | while | until | time | command | env) shift ;;
    *) break ;;
    esac
  done
  [[ "${1-}" == git || "${1-}" == */git ]] || return 1
  shift
  while (($#)); do
    case "$1" in
    -C)
      dir="${2-.}"
      shift 2 || return 1
      ;;
    -c | --git-dir | --work-tree | --namespace) shift 2 || return 1 ;;
    -*) shift ;;
    *) break ;;
    esac
  done
  [[ "${1-}" == push ]] || return 1
  shift
  local tags=0 remote="" refspecs=0 sends=0 pending_tag=0
  while (($#)); do
    w="$1"
    shift
    case "$w" in
    --delete | --dry-run | -[nd]* | -[!-]*[nd]*) return 1 ;;
    --tags) tags=1 ;;
    -o | --push-option | --repo | --receive-pack | --exec) shift ;;
    -*) ;;
    *)
      if [[ -z "$remote" ]]; then
        remote="$w"
        continue
      fi
      refspecs=1
      if ((pending_tag)); then
        pending_tag=0
      elif [[ "$w" == tag ]]; then
        pending_tag=1
      elif [[ "$w" != :* && "$w" != refs/tags/* && "$w" != +refs/tags/* ]]; then
        sends=1
      fi
      ;;
    esac
  done
  # Refspecs that only delete or push tags send no branch; with none at all the
  # push sends the configured branch, unless --tags narrowed it to tags.
  if ((sends)) || ((!refspecs && !tags)); then
    __sp_out="$dir"
    return 0
  fi
  return 1
}

main() {
  local input cmd cwd dir top out rc
  hook::buffer_stdin_to input '.tool_input.command' '.cwd' || exit 0
  cmd="${HOOK_JQ_FIELDS[0]-}"
  cwd="${HOOK_JQ_FIELDS[1]-}"
  [[ -n "$cmd" ]] || exit 0
  push_dir_to dir "$cmd" || exit 0
  [[ "$dir" == /* ]] || dir="${cwd:-.}/$dir"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || exit 0
  # Run only the project directory's own script (the trust model above), never
  # one from another worktree or repository the command points at.
  [[ -n "${CLAUDE_PROJECT_DIR-}" ]] || exit 0
  [[ "$top" == "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" ]] || exit 0
  [[ -x "$top/scripts/check-affected.sh" ]] || exit 0
  rc=0
  out="$(cd "$top" && bash scripts/check-affected.sh 2>&1)" || rc=$?
  ((rc == 1)) || exit 0
  printf 'Push blocked: scripts/check-affected.sh found failing checks on this branch. Fix them, commit, and push again.\n%s\n' "$out" >&2
  exit 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
