#!/usr/bin/env bash
# reap-project-plugin-records.sh — remove the project-scope plugin install
# records Claude Code recorded for the directory this script is standing in,
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
# <id> -s project` has NO path flag: it resolves strictly against the current
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
# It never edits `installed_plugins.json`. That file is Claude Code's internal
# state, not a published contract; every mutation goes through the CLI.
#
# Usage:
#   reap-project-plugin-records.sh --worktree-path <dir> [--dry-run]
#
# Output: one finding per line — `ok:` / `info:` / `warn:` / `error:`.
# Exit codes:
#   0  pass complete (including "no records recorded here")
#   1  at least one record for this directory survived the pass
#   2  usage error, or --worktree-path is not the current directory
#   3  prerequisite missing (claude CLI, jq) or enumeration failed — the caller
#      reports the reap as unavailable and proceeds with the removal

set -uo pipefail

PROG=${0##*/}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
# the CLI writes. That mismatch is what made an early probe of this behaviour
# read as a null. Resolve, never compare raw.
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

# enumerate — ids with a project-scope record whose projectPath is this
# directory. `claude plugin list --json` reports every project-scope record on
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
    | map(select(.scope == "project"))
    | .[]
    | [(.id // ""), (.projectPath // "")]
    | join("\t")
  ' 2>/dev/null | tr -d '\r' || return 1
}

# matching_ids — newline-separated, deduplicated.
collect_matches() {
  local rows id path
  rows="$(list_ids)" || return 1
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r id path; do
    [[ -n "$id" ]] || continue
    [[ -n "$path" ]] || continue
    [[ "$(norm_path "$path")" == "$here_key" ]] || continue
    printf '%s\n' "$id"
  done | sort -u
}

matches="$(collect_matches)" || {
  printf 'warn: could not enumerate plugin install records — the plugin list JSON failed or was unreadable.\n'
  printf 'info: records for this directory, if any, survive the removal.\n'
  exit 3
}

if [[ -z "$matches" ]]; then
  printf 'ok: no project-scope plugin install records are recorded for %s — nothing to reap.\n' "$here_native"
  exit 0
fi

count="$(printf '%s\n' "$matches" | grep -c '[^[:space:]]')"
printf 'info: %s project-scope plugin install record(s) recorded for %s\n' "$count" "$here_native"

if [[ "$dry_run" -eq 1 ]]; then
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    printf 'info: would reap %s\n' "$id"
  done <<EOF
$matches
EOF
  printf 'ok: dry run — no record was removed.\n'
  exit 0
fi

reaped=0
noop=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  # -s project only. Never -s user (the CLI's own failure text suggests it and
  # that suggestion is fleet-wide). Never --prune.
  out="$(claude plugin uninstall "$id" -s project 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    reaped=$((reaped + 1))
    printf 'ok: reaped %s\n' "$id"
  else
    noop=$((noop + 1))
    printf 'info: no-op for %s — the CLI resolved no project-scope record here (exit %s): %s\n' \
      "$id" "$rc" "$(printf '%s' "$out" | tr '\r\n' '  ')"
    printf 'info:   this is a report, not an escalation — do NOT retry it with the user scope.\n'
  fi
done <<EOF
$matches
EOF

survivors="$(collect_matches)" || survivors=""
survivor_count=0
if [[ -n "$survivors" ]]; then
  survivor_count="$(printf '%s\n' "$survivors" | grep -c '[^[:space:]]')"
fi

printf 'info: reaped %s, no-op %s, surviving %s\n' "$reaped" "$noop" "$survivor_count"

if [[ "$survivor_count" -gt 0 ]]; then
  printf 'warn: %s record(s) for %s survived the pass — report them; do not hand-edit installed_plugins.json.\n' \
    "$survivor_count" "$here_native"
  exit 1
fi

printf 'ok: every project-scope plugin install record for %s is gone.\n' "$here_native"
exit 0
