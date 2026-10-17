#!/usr/bin/env bash
# PreToolUse(Bash) hook: before a `git push` from a session in this repository,
# run scripts/check-affected.sh and block the push (exit 2, summary on stderr)
# when a check fails, so a lint finding costs a local run instead of a CI round.
#
# With --git-hook it is the lefthook pre-push job (lefthook.yml), which runs the
# merge-base copy of this script: no payload, the repository is the current
# directory's, and a failing check exits 1. As a Claude Code hook it stays quiet
# once lefthook's pre-push shim is installed, since git then runs the job on the
# push itself; until then it runs and says to run `lefthook install`.
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
# of the same clone; no origin/main to compare against, with a notice; a tree
# with no scripts/check-affected.sh; a payload it cannot read; and a
# check-affected run that could not start (exit 2), since an unreadable state is
# not a finding.
#
# Trust model: it runs check code only from the working tree that holds the
# .claude/settings.json registering this hook, and only code that matches the
# merge-base with origin/main. Claude Code reads that settings file once the
# folder is trusted (https://code.claude.com/docs/en/hooks#workspace-trust), but
# the scripts run at push time from whatever branch is checked out then, so a
# contributor branch checked out later in the same tree (to review or fix it)
# could carry its own check code. So this script diffs the working tree and
# untracked files against that merge-base. When no TOOLING path changed, the
# tree's own scripts/check-affected.sh is the merge-base's and runs in place.
# Otherwise the TOOLING files are extracted from the merge-base into a temporary
# directory and that copy runs against the branch, reading the branch's files as
# data only; scripts/check-affected.sh names each check that skips because it
# would run branch code. This script and lib/hook-utils.sh run before that diff,
# so the settings command first requires both to match the merge-base.
#
# The checks judge what a push sends, HEAD. When a file the branch changed has
# uncommitted edits, they run against a detached checkout of HEAD instead of the
# working tree, made with hooks disabled.
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

# Paths the checks execute or load code from, per what scripts/check-affected.sh
# runs without --tests: its scripts and their shell, Node and Python libraries,
# the plugin scripts and mods scripts/validate-plugins.sh runs, and the configs a
# linter loads code from or installs from. A change to any of them moves the run
# to the merge-base copy.
TOOLING=(
  'scripts/*' 'lib/*' '.claude/*' 'package.json' 'package-lock.json'
  '.markdownlint*' '*/.markdownlint*' 'ruff.toml' 'pyproject.toml' 'uv.toml'
  '.github/requirements-ci.txt'
  'plugins/*/hooks/*' 'plugins/autonomy/skills/setup/scripts/*'
  'plugins/harness-ops/skills/audit-native-overlap/scripts/*'
)

# The files a merge-base copy needs: the scripts check-affected.sh runs and their
# libraries, and every config a check reads its rules from.
TOOLS_EXTRACT=(
  scripts .shellcheckrc ruff.toml pyproject.toml .github/requirements-ci.txt
)

# tooling_change_to <out-var> <top> <mb>: assigns the first TOOLING path HEAD,
# the working tree or an untracked file changes against <mb> and returns 0; returns 1 when the tooling is
# unchanged, and 2 when the diff cannot be read.
tooling_change_to() {
  local -n __tc_out="$1"
  local top="$2" mb="$3" changed f p
  changed="$(git -C "$top" diff --no-renames --name-only "$mb" -- &&
    git -C "$top" diff --no-renames --name-only "$mb" HEAD -- &&
    git -C "$top" ls-files --others --exclude-standard)" || return 2
  while IFS= read -r f; do
    for p in "${TOOLING[@]}"; do
      # shellcheck disable=SC2053 # $p is a glob on purpose.
      if [[ "$f" == $p ]]; then
        __tc_out="$f"
        return 0
      fi
    done
  done <<<"$changed"
  return 1
}

# head_is_dirty <top> <mb>: 0 when a file changed in <mb>..HEAD has uncommitted
# edits, so the working tree is not what the push sends.
head_is_dirty() {
  local -a changed
  mapfile -t changed < <(git -C "$1" diff --name-only --diff-filter=d "$2" HEAD)
  [[ -n "${changed[0]-}" ]] || return 1
  ! git -C "$1" diff --quiet HEAD -- "${changed[@]}"
}

# extract_tools <top> <mb> <dir>: writes <mb>'s TOOLS_EXTRACT paths and every
# markdownlint config into <dir>.
extract_tools() {
  local -a paths
  mapfile -t paths < <(
    git -C "$1" ls-tree --name-only "$2" -- "${TOOLS_EXTRACT[@]}"
    git -C "$1" ls-tree -r --name-only "$2" | grep -E '(^|/)\.markdownlint[^/]*$'
  )
  ((${#paths[@]})) || return 1
  mkdir -p "$3" && git -C "$1" archive "$2" -- "${paths[@]}" | tar -x -C "$3"
}

# run_checks <top> <mb> <tooling-changed> <dirty>: prints the output of
# scripts/check-affected.sh run against the tree the push sends, a detached HEAD
# checkout when <dirty> is 1, with the script taken from <mb> when
# <tooling-changed> is 1; exits with its exit. A subshell, so the trap removes
# the checkout and temporary files however the run ends.
run_checks() (
  top="$1" mb="$2" data="$1" rc=0
  tmp="$(mktemp -d)" || exit 2
  trap '[[ "$data" == "$top" ]] || git -C "$top" worktree remove --force "$data" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
  trap 'exit 143' INT TERM HUP
  if [[ "$4" == 1 ]]; then
    data="$tmp/head"
    git -C "$top" -c core.hooksPath=/dev/null worktree add -q --detach "$data" HEAD >/dev/null 2>&1 || exit 2
  fi
  script="$data/scripts/check-affected.sh"
  if [[ "$3" == 1 ]]; then
    script="$tmp/tools/scripts/check-affected.sh"
    extract_tools "$top" "$mb" "$tmp/tools" || exit 2
  fi
  [[ -x "$script" ]] || exit 2
  (cd "$data" && bash "$script" 2>&1) || rc=$?
  exit "$rc"
)

main() {
  local input cmd cwd dir top out rc mb changed_tool tooling=0 dirty=0 git_hook=0 hooks
  [[ "${1-}" == --git-hook ]] && git_hook=1
  if ((git_hook)); then
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
  else
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
    hooks="$(git -C "$top" rev-parse --path-format=absolute --git-path hooks 2>/dev/null)"
    grep -qs lefthook "$hooks/pre-push" && exit 0
    printf 'check-affected pre-push: run lefthook install so git runs this check on every push.\n' >&2
  fi
  [[ -x "$top/scripts/check-affected.sh" ]] || exit 0
  if ! mb="$(git -C "$top" merge-base HEAD refs/remotes/origin/main 2>/dev/null)"; then
    printf 'check-affected pre-push: skipped, no origin/main merge-base to take check tooling from; CI checks it.\n' >&2
    exit 0
  fi
  rc=0
  tooling_change_to changed_tool "$top" "$mb" || rc=$?
  ((rc == 2)) && exit 0
  ((rc == 0)) && tooling=1
  head_is_dirty "$top" "$mb" && dirty=1
  rc=0
  out="$(run_checks "$top" "$mb" "$tooling" "$dirty")" || rc=$?
  if ((rc != 1 && tooling)); then
    printf 'check-affected pre-push: the branch changes check tooling (%s), so the checks ran from the merge-base copy of it.\n' \
      "$changed_tool" >&2
    grep '^check-affected: SKIP' <<<"$out" >&2
  fi
  ((rc == 1)) || exit 0
  printf 'Push blocked: scripts/check-affected.sh found failing checks on this branch. Fix them, commit, and push again.\n%s\n' "$out" >&2
  exit $((git_hook ? 1 : 2))
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
