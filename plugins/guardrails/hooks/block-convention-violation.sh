#!/usr/bin/env bash
# PreToolUse hook: block a commit SUBJECT or `gh pr create --title` that
# violates the team-tracked convention pattern. Triggered on Bash and
# PowerShell tool calls.
#
# WHAT IT ENFORCES — the declarative convention, where one is explicitly
# tracked: the commit subject (first line of the canonical stdin-form message)
# and the `gh pr create --title` value are validated against the POSIX-ERE
# pattern resolved from the consumer's tracked `.claude/source-control.md` by
# the vendored enforcement resolver (resolve-convention-pattern.sh — the
# commit-convention seam, docs/conventions/commit-convention/). The sibling
# block-noncanonical-commit gate enforces the message MECHANIC (`-F -`); this
# gate reads the CONTENT that mechanic carries.
#
# UNRESOLVED = NO ENFORCEMENT. No team-tracked pattern, a non-ERE pattern, or
# an unreadable config -> the gate no-ops. It never blocks against the bundled
# Conventional Commits default: enforcement strength equals the strength of
# explicit team config, so a repo that never opted in is never gated.
#
# NEVER BLOCKS `gh pr create` ITSELF. Only a present-and-violating `--title`
# value blocks; a missing `--title` (interactive/web flow) passes untouched —
# the documented inline fallback when skill discovery is unavailable stays
# usable. PROCESS conventions (rebase, triage, body template) have no command
# signature and remain advisory (flag-commit-pr-skill-bypass).
#
# EXEMPTION TAXONOMY — inherited from block-noncanonical-commit, or this gate
# breaks conflict resolution and history rewriting: --amend, -C/--reuse-message,
# -c/--reedit-message, --fixup/--squash, -F <path>/--file <path> (message not
# on the command line; the file may not even exist yet), and any commit during
# an in-progress merge/rebase/cherry-pick/revert sequencer.
#
# DECLARED BYPASS COVERAGE (out of scope, documented): `gh pr edit --title`,
# `gh pr create --fill`, direct API calls (`gh api .../pulls`), and babysit
# retitles are not gated. A subject supplied by a non-heredoc stdin producer
# (`printf … | git commit -F -`) is not extracted — the canonical /commit form
# is the heredoc, and the mechanic gate already channels traffic into it.
#
# Kill switch: block_convention_gate_enabled userConfig option.
#
# BLOCKING: exits 2 when an extractable subject/title violates the resolved
# pattern. Extraction failure on an exempt-free stdin-form commit is a SKIP,
# not a block — the mechanic gate owns form; this gate only judges content it
# can actually read.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics
# and fails a guard that sources anything ahead of it.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED:-true}" == "true" ]] || exit 0

# The hook's own directory is derived with parameter expansion rather than
# `dirname`. GNU Bash forks a subshell for every command substitution even when
# the body is a builtin (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). On Windows Git Bash that
# fork is a process, and this line runs on every fire — including inside the
# dispatcher, where the include guard makes `source` cheap but `$(dirname …)`
# still execs. `${BASH_SOURCE[0]%/*}` equals `dirname` for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh"

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq "PreToolUse" "guardrails-block-convention-violation" "$INPUT"

# All three payload fields in ONE jq process (hook::jq_fields), not three. A jq
# spawn is fork() emulation on Windows Git Bash and this guard runs on every
# Bash/PowerShell call. Failure semantics are unchanged: a missing jq or an
# unparsable payload yields rc 1 here, which exits 0 exactly as the empty-COMMAND
# skip below did — hook::require_jq above has already made the degraded state
# visible once per session. The `// "Bash"` default moves to the bash-side
# expansion, matching block-dangerous-git.
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0

# A NUL byte in ANY field read above is fail-CLOSED (#2136): the helper strips NUL
# bytes before matching, so a clean verdict would not reflect the bytes carried.
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte, which a command cannot reliably carry." >&2
  echo "What a guard can read is not dependably what would run, so this is refused rather than matched." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
HOOK_CWD="${HOOK_JQ_FIELDS[2]}"

HOOK_SELF_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_SELF_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_SELF_DIR="."
RESOLVER="$HOOK_SELF_DIR/resolve-convention-pattern.sh"

# git-config (https://git-scm.com/docs/git-config, fetched 2026-09-06):
# "aliases that hide existing Git commands are ignored except for deprecated
# commands." A current non-deprecated builtin therefore cannot expand to
# commit, so asking git for alias.<builtin> cannot change this gate's verdict
# and can false-block when a leftover ignored alias happens to name commit.
# Asking the installed git for its builtin list would put a spawn back on
# every `git status`. This is a static subset of names that were already
# builtins in git 2.25, minus names git marks DEPRECATED
# (`git --list-cmds=deprecated`; git.c `DEPRECATED` bit, master fetched
# 2026-09-06: `whatchanged` and `pack-redundant`). Names added later
# (`bugreport` 2.27, `maintenance` 2.31, `diagnose` 2.38) stay probed, so an
# older git that still honors `alias.bugreport = commit` cannot slip through.
# git 2.51+ honors `alias.whatchanged = commit` (t/t0014-alias.sh). A name
# not listed here is still probed. Skipping a non-builtin would miss a
# commit alias.
git_subcommand_ignores_alias() {
  case "$1" in
  add | am | annotate | apply | archive | bisect | blame | branch | bundle | \
    cat-file | check-attr | check-ignore | check-mailmap | check-ref-format | checkout | \
    checkout-index | cherry | cherry-pick | clean | clone | column | commit | commit-graph | \
    commit-tree | config | describe | diff | diff-files | diff-index | diff-tree | \
    difftool | fetch | for-each-ref | format-patch | fsck | gc | grep | hash-object | help | \
    init | interpret-trailers | log | ls-files | ls-remote | ls-tree | merge | \
    merge-base | mv | notes | pull | push | range-diff | rebase | reflog | remote | repack | \
    replace | reset | restore | rev-list | rev-parse | revert | rm | shortlog | show | \
    show-ref | sparse-checkout | stash | status | switch | symbolic-ref | tag | \
    update-ref | version | worktree)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# --- resolved pattern cache ---------------------------------------------------
# Resolving costs two resolver forks plus `git rev-parse --show-toplevel`.
# That used to run on EVERY Bash and PowerShell tool call, including
# `echo hello` and `git status`, even though this gate can only block a commit
# subject or a `gh pr create --title`. The pair is loaded on first need and
# cached per repo root; the answer still changes only when the convention
# files do. Measured at 423 ms, 10.1 spawn-equivalents against a 42 ms spawn
# floor on Windows Git Bash for the resolver itself.
#
# The resolver is not edited and not re-implemented here. It stays the single
# authority for what a pattern IS. What is cached is only its answer.
#
# Freshness is `[[ cache -nt dep ]]` per dependency, a bash builtin rather than a
# `stat` process. Equal mtimes read as NOT newer, so a same-timestamp write
# re-resolves rather than serving a stale pattern. That test alone is blind to a
# dependency that DISAPPEARS: `-nt` against a missing file is true, so a cache
# warmed while `.claude/source-control.md` (or the pointer target) existed would
# keep enforcing a policy the team has since deleted, where the resolver now
# answers no enforcement. So the entry also records every dependency with its
# existence at warm time, and any recorded-as-existing dependency now missing,
# or recorded-as-missing dependency now present (a higher-precedence file
# appearing with an OLD mtime, restored from an archive or a `cp -p`), is a
# miss. The repo root is stored in the file and compared on read, so two roots
# that sanitize to the same name cannot serve each other's patterns, and a
# terminator line makes a truncated write read as a miss.
#
# RESIDUAL, deliberately not solved here: the resolver's well-known-path rung
# only honours `docs/conventions/source-control/commit-convention.yml` when git
# reports it TRACKED, and tracked status can change with no mtime change on any
# file below. Such a change is picked up when any dependency is next written,
# not at the moment of `git add`. Probing it would cost the `git ls-files` spawn
# this cache exists to avoid.

SUBJECT_ERE=""
TITLE_ERE=""
CONV_LOADED=0

# An explicit `## convention_source` H2 names a third file the resolver reads.
# Scanned with bash builtins, never a process: the whole point here is that the
# hit path spawns nothing. Reading the pointer wrong can only DELAY an
# invalidation until the team file itself changes, never enforce a pattern the
# resolver did not produce.
conv_pointer() {
  local f="$REPO_ROOT/.claude/source-control.md" line t in_sec=0
  CONV_POINTER=""
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == '##'[[:space:]]* ]]; then
      t="${line#\#\#}"
      t="${t#"${t%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "$t" == "convention_source" ]] && in_sec=1 || in_sec=0
      continue
    fi
    ((in_sec)) || continue
    t="${line#"${line%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ -n "$t" ]] || continue
    CONV_POINTER="$t"
    return 0
  done <"$f"
  return 0
}

ensure_convention_patterns() {
  ((CONV_LOADED)) && return 0
  CONV_LOADED=1
  REPO_ROOT=$(hook::repo_root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}")
  CONV_DEPS=(
    "$REPO_ROOT/.claude/source-control.md"
    "$REPO_ROOT/docs/conventions/source-control/commit-convention.yml"
  )
  conv_pointer
  [[ -n "$CONV_POINTER" ]] && CONV_DEPS+=("$REPO_ROOT/$CONV_POINTER")

  CONV_CACHE=""
  [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] &&
    CONV_CACHE="$CLAUDE_PLUGIN_DATA/convention-pattern/${REPO_ROOT//[^A-Za-z0-9]/_}"

  CONV_HIT=0
  # Entry layout: root, subject pattern, title pattern, one `DEP <0|1> <path>`
  # line per dependency in CONV_DEPS order (1 = existed at warm time), `END`.
  # One pass over the file, bash builtins only: a dependency line is checked as
  # it is read, and the first stale one ends the read as a miss.
  # shellcheck disable=SC2094  # the entry is only READ here; the write below is a separate branch
  if [[ -n "$CONV_CACHE" && -f "$CONV_CACHE" ]]; then
    conv_root=""
    conv_subj=""
    conv_title=""
    conv_end=""
    conv_i=0
    conv_fresh=1
    {
      IFS= read -r conv_root
      IFS= read -r conv_subj
      IFS= read -r conv_title
      while IFS= read -r conv_line; do
        if [[ "$conv_line" == "END" ]]; then
          conv_end="END"
          break
        fi
        # Recorded set must be the current set, in order: a pointer that changed
        # already moved the team file's mtime, but this keeps the read honest.
        [[ "$conv_line" == "DEP "[01]" "* && "${conv_line:6}" == "${CONV_DEPS[conv_i]:-}" ]] || {
          conv_fresh=0
          break
        }
        conv_dep="${conv_line:6}"
        if [[ -e "$conv_dep" ]]; then
          [[ "${conv_line:4:1}" == 1 && "$CONV_CACHE" -nt "$conv_dep" ]] || conv_fresh=0
        else
          [[ "${conv_line:4:1}" == 0 ]] || conv_fresh=0
        fi
        ((conv_fresh)) || break
        ((conv_i++))
      done
    } <"$CONV_CACHE"
    if ((conv_fresh && conv_i == ${#CONV_DEPS[@]})) &&
      [[ "$conv_end" == "END" && "$conv_root" == "$REPO_ROOT" ]]; then
      SUBJECT_ERE="$conv_subj"
      TITLE_ERE="$conv_title"
      CONV_HIT=1
    fi
  fi

  if ((CONV_HIT == 0)) && [[ -f "$RESOLVER" ]]; then
    # Existence is sampled BEFORE the resolver forks, so the entry records the
    # dependency set the answer was resolved against.
    conv_dep_lines=""
    for conv_dep in "${CONV_DEPS[@]}"; do
      if [[ -e "$conv_dep" ]]; then
        conv_dep_lines+="DEP 1 $conv_dep"$'\n'
      else
        conv_dep_lines+="DEP 0 $conv_dep"$'\n'
      fi
    done
    for conv_key in subject_pattern pr_title_pattern; do
      # The redirect sits on a single-command group, NOT inside the
      # substitution. Bash execs the body in the substitution's own subshell
      # only when that body carries no redirection of its own, so
      # `$(cmd 2>/dev/null)` pays a second fork that `{ v=$(cmd); } 2>/dev/null`
      # does not (measured with `strace -f -e trace=clone,clone3,execve`). The
      # group holds exactly one command, so its status is still the resolver's
      # and the `|| conv_val=""` fallback fires on exactly the same failures.
      { conv_val=$(bash "$RESOLVER" "$REPO_ROOT" "$conv_key"); } 2>/dev/null || conv_val=""
      case "$conv_key" in
      subject_pattern) SUBJECT_ERE="$conv_val" ;;
      *) TITLE_ERE="$conv_val" ;;
      esac
    done
    # Write through a temp name and rename, so a reader never sees a half file.
    if [[ -n "$CONV_CACHE" ]] && mkdir -p "${CONV_CACHE%/*}" 2>/dev/null; then
      if printf '%s\n%s\n%s\n%sEND\n' "$REPO_ROOT" "$SUBJECT_ERE" "$TITLE_ERE" "$conv_dep_lines" \
        >"$CONV_CACHE.$$" 2>/dev/null; then
        mv -f "$CONV_CACHE.$$" "$CONV_CACHE" 2>/dev/null || rm -f "$CONV_CACHE.$$" 2>/dev/null
      else
        rm -f "$CONV_CACHE.$$" 2>/dev/null
      fi
    fi
  fi
}

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data subject
  subject=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-convention-violation" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# First non-empty line of the FIRST heredoc body in the raw Bash command.
# Empty output when no heredoc exists. The canonical /commit form carries
# exactly one heredoc; a command with several is judged by its first, which is
# the one `git commit -F -` reads in the canonical composition.
# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_heredoc_subject() {
  local cmd="$1" line delim="" in_hd=0 trimmed
  # POSIX ERE (no backreferences in [[ =~ ]]): capture the raw delimiter word,
  # then trim its quoting — the same shape flag-commit-pr-skill-bypass's
  # stripper uses.
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ "$trimmed" == "$delim" ]] && return 0
      # Blank-detection uses the trimmed copy, but the subject git receives is
      # the RAW line (CR aside) — leading/trailing spaces are part of what a
      # `--cleanup=verbatim` commit records, so validate exactly that.
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  return 0
}

# First non-empty line of the FIRST PowerShell here-string body (@'…'@ / @"…"@).
# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_herestring_subject() {
  local cmd="$1" line in_hs=0 hs_quote="" closer trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hs)); then
      closer="${hs_quote}@"
      [[ "${line:0:2}" == "$closer" ]] && return 0
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      # Blank-detection uses the trimmed copy; the subject is the RAW line
      # (CR aside) — a here-string body preserves leading/trailing spaces.
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if [[ "$line" == *"@'" || "$line" == *'@"' ]]; then
      hs_quote="${line: -1}"
      in_hs=1
    fi
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  return 0
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_subject() {
  echo "BLOCKED: commit subject violates the team convention." >&2
  echo "  subject: $1" >&2
  echo "  pattern: $SUBJECT_ERE   (from .claude/source-control.md, team layer)" >&2
  echo "Rewrite the subject to match, or use the /commit skill (source-control plugin)," >&2
  echo "which drafts against the resolved convention." >&2
  emit_tel "blocked" "subject-pattern"
  exit 2
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_title() {
  echo "BLOCKED: PR title violates the team convention." >&2
  echo "  title:   $1" >&2
  echo "  pattern: $TITLE_ERE   (from .claude/source-control.md, team layer)" >&2
  echo "Retitle to match, or use /pull-request create (source-control plugin)." >&2
  emit_tel "blocked" "pr-title-pattern"
  exit 2
}

# Same repo-dir/sequencer helpers as block-noncanonical-commit — an in-progress
# sequencer commit carries a prepared message and is never content-gated.
#
# CALLERS MUST PASS GIT'S OWN GLOBALS ONLY — the slice from the resolved git token
# (`gi`) up to the subcommand, preceded by any wrapper chdir replayed as leading
# `-C` words. The full reasoning for that contract, and for why the wrapper replay
# is a separate input rather than something this walk could find for itself, is in
# `block-noncanonical-commit.sh`'s docblock on its own `effective_dir`; the sibling
# mechanic guard `block-dangerous-git.sh` binds `collect_git_locating_opts` to the
# same boundary. In short: a 0-based scan reads `-C` words that are not git's, and
# a slice that starts at `gi` cannot see a relocation a wrapper really performed,
# so the caller must supply both halves.
#
# This guard was the last caller still scanning the WHOLE argv, which invented
# chdirs that were not there — the opposite failure from the sibling's. `env -u -C
# git <alias> …` moves nothing (GNU env's `-u` consumes `-C` as the variable name),
# yet the every-word scan composed `<cwd>/git` and read that directory's aliases;
# the guard then never learned the real subcommand and the convention went
# unenforced. A post-subcommand `-C` is `--reuse-message`, not a directory, and the
# distinction is purely positional.
#
# The base is HOOK_EFFECTIVE_BASE, not the payload cwd directly, because a `!`
# shell alias's body re-parses as a NEW top-level command whose argv no longer
# carries the wrapper that moved git. Without the fallback, `env -C <dir> git
# <alias>` resolved the alias in <dir> and then evaluated the alias body's
# sequencer probe against the payload cwd — so a prepared merge subject in <dir>
# was BLOCKED where the docblock below promises an exemption. The caller
# save/sets/restores it around each reparse.
#
# What this composes is the caller's directory, where the sibling
# `block-noncanonical-commit.sh` asks git for the alias's real LAUNCH directory
# (its `alias_launch_dir`, since git starts a `!` body at the work tree's top
# level). For this guard's two consumers the two agree: both `config --get` and
# `rev-parse --absolute-git-dir` answer identically from any directory inside one
# repository. They diverge only when a SEPARATE repository is nested below the
# composed path, which is the narrower case the sibling's extra probe exists for
# and which is deliberately not modelled here.
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

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir repo="$1" f
  # Redirect on a single-command group, not inside the substitution — see the
  # note in ensure_convention_patterns. One command in the group, so the
  # `|| return 1` still reads git's own status and a sequencer probe that fails
  # is still "no sequencer", exactly as before.
  { dir=$(git -C "$repo" rev-parse --absolute-git-dir); } 2>/dev/null || return 1
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # gh pr create --title validation (independent of git parsing). `gh` is
  # commonly wrapped in command-scoped environment settings
  # (`GH_PROMPT_DISABLED=1 gh …`, `env GH_TOKEN=… gh …`) — skip leading
  # assignments and `env`/`command` wrappers before deciding this is not gh.
  local -a gw=("$@")
  local gn=$# gs=0 gt
  while ((gs < gn)); do
    gt="${gw[gs]}"
    if [[ "$gt" == *=* && "$gt" != -* ]]; then
      ((gs++))
      continue
    fi
    case "${gt##*/}" in
    env | command)
      ((gs++))
      while ((gs < gn)) && [[ "${gw[gs]}" == -* || ("${gw[gs]}" == *=* && "${gw[gs]}" != -*) ]]; do ((gs++)); done
      continue
      ;;
    *) break ;;
    esac
  done
  if [[ "${gw[gs]:-}" == "gh" && "${gw[gs + 1]:-}" == "pr" && "${gw[gs + 2]:-}" == "create" ]]; then
    ensure_convention_patterns
    if [[ -n "$TITLE_ERE" ]]; then
      local t="" ti
      for ((ti = gs + 3; ti < gn; ti++)); do
        case "${gw[ti]}" in
        --title)
          ((ti + 1 < gn)) && t="${gw[ti + 1]}"
          ;;
        --title=*)
          t="${gw[ti]#--title=}"
          ;;
        -t)
          ((ti + 1 < gn)) && t="${gw[ti + 1]}"
          ;;
        *) ;;
        esac
      done
      if [[ -n "$t" ]] && ! [[ "$t" =~ $TITLE_ERE ]]; then
        block_title "$t"
      fi
    fi
    return 0
  fi

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  # A wrapper's chdir happens before git starts, so it composes ahead of git's
  # own globals — spelled as leading `-C` words so the one path-composition rule
  # in effective_dir covers both. hook::git_resolve_index is the only parser that
  # can tell a real `env -C <dir>` from the `-C` in `env -u -C git`, which moves
  # nothing; the slice below deliberately cannot see either, so this replays what
  # the resolver found.
  local -a wrapper_cd=()
  local wdir
  for wdir in ${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]+"${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]}"}; do
    wrapper_cd+=(-C "$wdir")
  done

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX

  # The directory this segment's git actually runs in. Computed ONCE, and only
  # when an alias probe or a commit needs it — a `git status` that cannot hide
  # behind an alias must not pay effective_dir's subshell.
  local seg_dir=""

  # Alias-expanded commits must be content-gated too (`git -c alias.c=commit c
  # -F - <<EOF` and persisted `git qc` aliases create commits) — mirror the
  # sibling mechanic guard's expansion: re-check every inline spelling, then
  # the gitconfig-resolved alias, one level (HOOK_NO_ALIAS bounds recursion).
  # rc 2 (--config-env-shaped alias) is the MECHANIC guard's fail-closed
  # concern — it blocks the call outright, so this content gate just skips.
  local exp reparse a alias_rc inline_alias_handled=0
  local -a expw=()
  hook::git_alias_expansion "$sub"
  alias_rc=$?
  ((alias_rc == 2)) && return 0
  if ((${HOOK_NO_ALIAS:-0} == 0)); then
    if ((alias_rc == 0)); then
      # shellcheck disable=SC2154  # HOOK_GIT_ALIAS_EXPS is set by hook::git_alias_expansion
      for exp in ${HOOK_GIT_ALIAS_EXPS[@]+"${HOOK_GIT_ALIAS_EXPS[@]}"}; do
        [[ -n "$exp" ]] || continue
        inline_alias_handled=1
        if [[ "$exp" == '!'* ]]; then
          reparse="${exp#!}"
          for a in "${w[@]:sub_idx+1}"; do reparse+=" $(printf '%q' "$a")"; done
          # The body is a fresh top-level parse, so it carries no wrapper and no
          # git globals. Hand it the directory this invocation resolved to, or
          # the reparse silently restarts from the payload cwd.
          [[ -n "$seg_dir" ]] ||
            seg_dir="$(effective_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}")"
          local saved_base="${HOOK_EFFECTIVE_BASE:-}"
          HOOK_EFFECTIVE_BASE="$seg_dir"
          hook::bash_parse_segments "$reparse" check_segment
          HOOK_EFFECTIVE_BASE="$saved_base"
        else
          hook::env_s_split "$exp"
          expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          HOOK_NO_ALIAS=1
          check_segment "${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}"
          HOOK_NO_ALIAS=0
        fi
      done
    fi
    if ((inline_alias_handled == 0)) && [[ "$sub" != "commit" ]] &&
      ! git_subcommand_ignores_alias "$sub"; then
      local pexp
      [[ -n "$seg_dir" ]] ||
        seg_dir="$(effective_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}")"
      # Redirect on a single-command group, not inside the substitution — see
      # the note in ensure_convention_patterns. This is the one of the three
      # that sits on the per-tool-call path: every non-builtin git subcommand
      # is probed for an alias. `pexp` empty (git found nothing, or git is
      # absent) still means "no alias", unchanged.
      { pexp=$(git -C "$seg_dir" config --get "alias.$sub"); } 2>/dev/null
      if [[ -n "$pexp" ]]; then
        if [[ "$pexp" == '!'* ]]; then
          local preparse pa
          preparse="${pexp#!}"
          for pa in "${w[@]:sub_idx+1}"; do preparse+=" $(printf '%q' "$pa")"; done
          # Same reason as the inline `!` branch above.
          local psaved_base="${HOOK_EFFECTIVE_BASE:-}"
          HOOK_EFFECTIVE_BASE="$seg_dir"
          hook::bash_parse_segments "$preparse" check_segment
          HOOK_EFFECTIVE_BASE="$psaved_base"
        else
          local -a pexpw=()
          hook::env_s_split "$pexp"
          pexpw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          HOOK_NO_ALIAS=1
          check_segment "${w[@]:0:sub_idx}" ${pexpw[@]+"${pexpw[@]}"} "${w[@]:sub_idx+1}"
          HOOK_NO_ALIAS=0
        fi
      fi
    fi
  fi

  [[ "$sub" == "commit" ]] || return 0
  ensure_convention_patterns
  [[ -n "$SUBJECT_ERE" ]] || return 0
  [[ -n "$seg_dir" ]] ||
    seg_dir="$(effective_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}")"

  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --) break ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-) stdin_form=1 ;;
    --file=* | -F*) exempt=1 ;;
    --amend | --fixup | --squash | -C | -c | --reuse-message | --reedit-message) exempt=1 ;;
    --fixup=* | --squash=* | --reuse-message=* | --reedit-message=*) exempt=1 ;;
    -C* | -c*) exempt=1 ;;
    *) ;;
    esac
  done

  ((stdin_form)) || return 0
  ((exempt)) && return 0
  sequencer_in_progress "$seg_dir" && return 0

  local subj=""
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    subj=$(first_herestring_subject "$COMMAND")
  else
    subj=$(first_heredoc_subject "$COMMAND")
  fi
  # No extractable message body (non-heredoc stdin producer): content unknown,
  # skip — form is the mechanic gate's concern, and guessing here would block
  # compliant subjects it cannot see.
  [[ -n "$subj" ]] || return 0

  [[ "$subj" =~ $SUBJECT_ERE ]] || block_subject "$subj"
  return 0
}

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  # Reduce the PowerShell command to a Bash-tokenizer-faithful form, or defer:
  # rc 1 (provably git-free unparsable) has nothing to gate — and if it could
  # still carry a `gh pr create`, the quote-intact reduced text was already
  # scanned by the classifier's own sink; rc 2 (git-shaped unparsable) is
  # `block-dangerous-git`/`block-no-verify`'s fail-closed concern, not a content
  # decision.
  PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
  # shellcheck source=../lib/powershell/ps-command.sh
  source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"
  ps::classify_git_command "$TOOL_NAME" "$COMMAND"
  ps_rc=$?
  ((ps_rc == 0)) || {
    emit_tel "ok" ""
    exit 0
  }
  hook::bash_parse_segments "$PS_SAFE_COMMAND" check_segment
else
  hook::bash_parse_segments "$COMMAND" check_segment
fi

emit_tel "ok" ""
exit 0
