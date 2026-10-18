#!/usr/bin/env bash
# reap-project-plugin-records.sh — remove the project- and local-scope plugin
# install records Claude Code recorded for the directory this script is standing in,
# through the documented plugin CLI and nothing else.
#
# WHY THIS EXISTS. Claude Code records a project-scope install in
# `~/.claude/plugins/installed_plugins.json` keyed by a literal `projectPath`,
# and nothing reaps that record when the path goes away. A worktree this plugin
# creates and later destroys therefore leaves one record per installed plugin
# behind, forever. Teardown is the only moment at which those records are both
# identifiable and provably dead, so teardown is where they are removed.
#
# THE BOUNDARY, RENDERED IN CODE RATHER THAN IN PROSE. `claude plugin uninstall
# <id> -s project` (and `-s local`) has NO path flag: it resolves strictly against the current
# directory (measured — see skills/worktree/fixtures/README.md). This script
# therefore requires `--worktree-path` to name the directory it is already
# standing in and refuses otherwise, so it structurally cannot act on any path
# other than its own cwd. That is deliberate: a record for a live repository on
# an unmounted network share or a detached external volume is indistinguishable
# from a dead worktree to a bare existence check, and this script must never be
# able to reach one. The trigger is a teardown the caller is performing, never
# path liveness.
#
# TWO CALLS IT NEVER MAKES.
#   * `-s user` — the CLI's own failure text for an id with no project record
#     at this path reads "installed in user scope, not project. Use --scope
#     user to uninstall." Following that hint would uninstall the plugin
#     fleet-wide. A non-zero exit here is a no-op to report, never an
#     escalation.
#   * `--prune` — it reaches past project scope into auto-installed
#     dependencies shared with every other scope.
#
# ONE FLAG IT ALWAYS PASSES.
#   * `--keep-data` — this script reaps stale *records*. Uninstalling from the
#     last remaining scope deletes that plugin's `${CLAUDE_PLUGIN_DATA}`
#     directory by default. The reap never wants that side effect.
#
# It never edits `installed_plugins.json`. That file is Claude Code's internal
# state, not a published contract; every mutation goes through the CLI.
#
# IT LEAVES THE TRACKED SETTINGS FILE AS IT FOUND IT. The uninstall call also
# rewrites `.claude/settings.json` in this directory: it drops the reaped ids'
# `enabledPlugins` entries, and was observed to reorder keys and drop unrelated
# settings. When that file is tracked by git here and unmodified before the
# pass, it is restored from git afterwards and an `info:` line names it, so the
# plain `git worktree remove` that follows does not refuse a tree the reap
# dirtied. Untracked, already modified, or outside a git work tree: the file is
# never touched, and a `warn:` line names it if the CLI changed it.
#
# Usage:
#   reap-project-plugin-records.sh --worktree-path <dir> [--dry-run]
#
# Output: one finding per line — `ok:` / `info:` / `warn:` / `error:`.
# Exit codes:
#   0  pass complete (including "no records recorded here")
#   1  at least one record for this directory survived the pass
#   2  usage error, or --worktree-path is not the current directory
#   3  prerequisite missing (claude CLI, jq), or an enumeration failed — the
#      caller reports the reap as unavailable and proceeds with the removal.
#      This covers BOTH enumerations. A failed POST-reap enumeration means the
#      pass is UNVERIFIED: some records may well have been removed, but nothing
#      confirmed it, and an unverified pass must never read as a clean one.

set -uo pipefail

PROG=${0##*/}

have() { command -v "$1" >/dev/null 2>&1; }

# Print the header block (everything after the shebang up to the first
# non-comment line) with its comment markers stripped. Derived rather than a
# hardcoded line range: such a range silently truncates or over-runs as the
# header grows.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "${BASH_SOURCE[0]}"
}

worktree_path=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --worktree-path)
    if [[ $# -lt 2 ]]; then
      printf '%s: --worktree-path requires a value\n' "$PROG" >&2
      exit 2
    fi
    worktree_path="$2"
    shift 2
    ;;
  --dry-run)
    dry_run=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
    exit 2
    ;;
  esac
done

if [[ -z "$worktree_path" ]]; then
  printf '%s: --worktree-path is required\n' "$PROG" >&2
  exit 2
fi

# On MSYS/Git Bash `pwd -W` yields the native long form (`D:/worktrees/x`),
# which is the form Claude Code records. `$PWD` there is a POSIX mount path and
# an inherited value can also carry an 8.3 short component (`ALICE~1` where the
# directory is really `AliceExample`), which compares unequal to the long form
# the CLI writes. Resolve, never compare raw.
native_pwd() {
  local p
  p="$(pwd -W 2>/dev/null)" || p=""
  [[ -n "$p" ]] || p="$(pwd -P 2>/dev/null)" || p="$PWD"
  printf '%s' "$p"
}

is_windows_shell() {
  case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) return 0 ;;
  *) return 1 ;;
  esac
}

# norm_path <path> — comparison key: separators unified, trailing slash
# dropped, case folded only where the filesystem is case-insensitive.
norm_path() {
  local p="$1"
  # `tr`, not `${p//\\//}` — that parameter expansion does not replace a
  # backslash in bash, and Claude Code records every Windows projectPath with
  # backslashes, so the mistake silently matches nothing on the only platform
  # where it matters.
  # `join("\t")` above, not `@tsv`: @tsv escapes each backslash to `\\`, which
  # would survive into the key as a doubled separator. The squeeze below is the
  # second belt on that same class, applied to BOTH sides. It is not a perfect
  # injection: a UNC `//server/share/x` squeezes to `/server/share/x`, so in
  # principle two spellings could merge. No valid Windows path spells the latter,
  # and the cwd guard below confines the ACTION regardless of what the matcher
  # returns — a false match can only ever produce a reported no-op.
  # `\134` is tr's octal for a backslash — written that way because the literal
  # forms are a quoting minefield here.
  p="$(printf '%s' "$p" | tr -d '\r' | tr "\134" '/' | tr -s '/')"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  if is_windows_shell; then
    p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  fi
  printf '%s' "$p"
}

# resolve_dir <dir> — the directory's native absolute form, or empty.
resolve_dir() {
  [[ -d "$1" ]] || return 1
  (cd "$1" 2>/dev/null && native_pwd) || return 1
}

here_native="$(native_pwd)"
here_key="$(norm_path "$here_native")"

arg_native="$(resolve_dir "$worktree_path")" || arg_native=""
if [[ -z "$arg_native" ]]; then
  printf 'error: --worktree-path does not resolve to a directory: %s\n' "$worktree_path"
  printf 'info: the project scope has no path flag, so this script must be run from inside the directory whose records it removes.\n'
  exit 2
fi
arg_key="$(norm_path "$arg_native")"

if [[ "$arg_key" != "$here_key" ]]; then
  printf 'error: --worktree-path is not the current directory — refusing.\n'
  printf 'error:   --worktree-path resolves to: %s\n' "$arg_native"
  printf 'error:   current directory is:        %s\n' "$here_native"
  printf 'info: the project scope acts on the current directory and nothing else; running this from elsewhere could only ever be a no-op or a mistake.\n'
  exit 2
fi

have claude || {
  printf 'warn: claude CLI not on PATH — project-scope install records for this directory cannot be reaped.\n'
  printf 'info: the records survive the removal; re-run this script from a directory recreated at %s once the CLI is available.\n' "$here_native"
  exit 3
}
have jq || {
  printf 'warn: jq not available — cannot read the plugin list JSON, so records for this directory cannot be enumerated.\n'
  exit 3
}

# enumerate — id and scope of each project- or local-scope record whose
# projectPath is this directory (user scope is never listed). `claude plugin list --json` reports every project-scope record on
# the machine regardless of cwd — measured, and re-checkable:
# skills/worktree/fixtures/README.md § project-scope-reap-probe.sh arm 2,
# Claude Code 2.1.240, re-run unchanged on 2.1.241 — so enumeration is
# cwd-independent and the cwd guard above is what confines the ACTION.
list_ids() {
  local raw
  raw="$(claude plugin list --json 2>/dev/null)" || return 1
  [[ -n "$raw" ]] || return 1
  # `| tr -d '\r'` is not decoration: jq on Git Bash terminates each line with
  # CRLF, and a trailing CR on the projectPath field compares unequal to the
  # same path resolved locally — the field would silently never match.
  printf '%s' "$raw" | jq -r '
    (if type == "object" then (.installed // .plugins // []) else . end)
    | map(select(.scope == "project" or .scope == "local"))
    | .[]
    | [(.id // ""), (.projectPath // ""), .scope]
    | join("\t")
  ' 2>/dev/null | tr -d '\r' || return 1
}

# collect_matches — `<id><TAB><scope>` rows, deduplicated.
collect_matches() {
  local rows id path scope
  rows="$(list_ids)" || return 1
  printf '%s\n' "$rows" | while IFS=$'\t' read -r id path scope; do
    [[ -n "$id" ]] || continue
    [[ -n "$path" ]] || continue
    [[ "$(norm_path "$path")" == "$here_key" ]] || continue
    printf '%s\t%s\n' "$id" "$scope"
  done | sort -u
}

matches="$(collect_matches)" || {
  printf 'warn: could not enumerate plugin install records — the plugin list JSON failed or was unreadable.\n'
  printf 'info: records for this directory, if any, survive the removal.\n'
  exit 3
}

if [[ -z "$matches" ]]; then
  printf 'ok: no project- or local-scope plugin install records are recorded for %s — nothing to reap.\n' "$here_native"
  exit 0
fi

count="$(printf '%s\n' "$matches" | grep -c '[^[:space:]]')"
printf 'info: %s project- or local-scope plugin install record(s) recorded for %s\n' "$count" "$here_native"

if [[ "$dry_run" -eq 1 ]]; then
  while IFS=$'\t' read -r id scope; do
    [[ -n "$id" ]] || continue
    printf 'info: would reap %s (%s scope)\n' "$id" "$scope"
  done <<<"$matches"
  printf 'ok: dry run — no record was removed.\n'
  exit 0
fi

# The settings file the uninstall CLI rewrites. Relative on purpose: the cwd
# guard above pins the cwd to the directory being reaped, and git resolves a
# relative pathspec against the cwd.
SETTINGS_REL=".claude/settings.json"

# file_fingerprint <path> — a byte-level fingerprint, or `absent`.
file_fingerprint() {
  if [[ -f "$1" ]]; then
    cksum <"$1" 2>/dev/null || printf 'unreadable'
  else
    printf 'absent'
  fi
}

# settings_git_state — `clean` (tracked; worktree and index match HEAD),
# `modified`, `flagged` (assume-unchanged or skip-worktree), `untracked`, or
# `nogit` (no git, or not inside a work tree: the orphaned-directory and
# recreated-directory cases).
settings_git_state() {
  have git || {
    printf 'nogit'
    return
  }
  [[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || {
    printf 'nogit'
    return
  }
  git ls-files --error-unmatch -- "$SETTINGS_REL" >/dev/null 2>&1 || {
    printf 'untracked'
    return
  }
  # assume-unchanged (lowercase tag) or skip-worktree (S) hides local edits from
  # both diffs below, so the file would read clean and the restore would drop them.
  case "$(git ls-files -v -- "$SETTINGS_REL" 2>/dev/null)" in
    [a-z]\ * | S\ *)
      printf 'flagged'
      return
      ;;
    *) ;;
  esac
  # Both halves: `git diff HEAD` alone compares only the worktree to HEAD, so a
  # staged-only change would read clean and the restore's --staged would drop it.
  if git diff --quiet -- "$SETTINGS_REL" 2>/dev/null &&
    git diff --cached --quiet HEAD -- "$SETTINGS_REL" 2>/dev/null; then
    printf 'clean'
  else
    printf 'modified'
  fi
}

settings_before_state="$(settings_git_state)"
settings_before_print="$(file_fingerprint "$SETTINGS_REL")"

# settle_settings — runs once after the uninstall loop and the post-reap
# enumeration, on every exit path that follows them, so the survivor result is
# always read before the file is touched. It restores only this one file, and
# only when git proved it tracked and clean before the pass, so it cannot
# discard anyone's edit. It never touches installed_plugins.json, so it cannot
# bring an install record back.
settle_settings() {
  local reason
  [[ "$(file_fingerprint "$SETTINGS_REL")" != "$settings_before_print" ]] || return 0
  if [[ "$settings_before_state" == "clean" ]]; then
    if git restore --source=HEAD --staged --worktree -- "$SETTINGS_REL" >/dev/null 2>&1 &&
      git diff --quiet HEAD -- "$SETTINGS_REL" 2>/dev/null; then
      printf 'info: restored %s from git: the uninstall CLI rewrote it, and it was tracked and unmodified before the pass.\n' \
        "$SETTINGS_REL"
    else
      printf 'warn: the uninstall CLI rewrote %s and restoring it from git failed; the tree is dirty, so plain removal will refuse it.\n' \
        "$SETTINGS_REL"
    fi
    return 0
  fi
  case "$settings_before_state" in
    modified) reason="it already had uncommitted changes before the pass" ;;
    flagged) reason="assume-unchanged or skip-worktree is set, so git cannot see local edits" ;;
    untracked) reason="git does not track it here" ;;
    *) reason="this directory is not inside a git work tree" ;;
  esac
  printf 'warn: the uninstall CLI changed %s; left as is because %s.\n' "$SETTINGS_REL" "$reason"
}

reaped=0
noop=0
while IFS=$'\t' read -r id scope; do
  [[ -n "$id" ]] || continue
  # The record's own scope: project or local, never another (the enumeration
  # yields no other). Never -s user (the CLI's own failure text suggests it and
  # that suggestion is fleet-wide). Never --prune. Always --keep-data: this
  # script reaps stale records, never a plugin's persistent data directory.
  out="$(claude plugin uninstall "$id" -s "$scope" --keep-data 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    reaped=$((reaped + 1))
    printf 'ok: reaped %s (%s scope)\n' "$id" "$scope"
  else
    noop=$((noop + 1))
    printf 'info: no-op for %s — the CLI resolved no %s-scope record here (exit %s): %s\n' \
      "$id" "$scope" "$rc" "$(printf '%s' "$out" | tr '\r\n' '  ')"
    printf 'info:   this is a report, not an escalation — do NOT retry it with the user scope.\n'
  fi
done <<<"$matches"

# The post-reap pass is the only thing that turns "the uninstall calls returned
# 0" into "the records are gone". A failure here therefore means UNVERIFIED, not
# zero survivors — the identical failure the PRE-reap enumeration already treats
# as a degrade. Absorbing it into an empty list is how a script comes to report
# certainty it does not have, and it is the one outcome a caller acts on by
# deleting the directory.
if ! survivors="$(collect_matches)"; then
  settle_settings
  printf 'info: reaped %s, no-op %s, surviving UNKNOWN\n' "$reaped" "$noop"
  printf 'warn: the post-reap check could not enumerate plugin install records — this pass is UNVERIFIED.\n'
  printf 'warn:   %s uninstall call(s) reported success and %s reported a no-op, but nothing confirmed any record is gone.\n' \
    "$reaped" "$noop"
  printf 'info: treat this exactly as the pre-reap degrade: say so, and do not report a clean reap.\n'
  exit 3
fi

survivor_count=0
if [[ -n "$survivors" ]]; then
  survivor_count="$(printf '%s\n' "$survivors" | grep -c '[^[:space:]]')"
fi

settle_settings
printf 'info: reaped %s, no-op %s, surviving %s\n' "$reaped" "$noop" "$survivor_count"

if [[ "$survivor_count" -gt 0 ]]; then
  printf 'warn: %s record(s) for %s survived the pass — report them; do not hand-edit installed_plugins.json.\n' \
    "$survivor_count" "$here_native"
  exit 1
fi

printf 'ok: every project- and local-scope plugin install record for %s is gone.\n' "$here_native"
exit 0
