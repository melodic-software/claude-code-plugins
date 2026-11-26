#!/usr/bin/env bash
# Exit codes:
#   0  pass complete (including "no records recorded here")
#   1  at least one record for this directory survived the pass
#   2  usage error, or --worktree-path is unresolvable or a main working tree
#   3  prerequisite missing (claude CLI, jq), or an enumeration failed — the
#      caller reports the reap as unavailable and proceeds with the removal.
#      This covers BOTH enumerations. A failed POST-reap enumeration means the
#      pass is UNVERIFIED: some records may well have been removed, but nothing
#      confirmed it, and an unverified pass must never read as a clean one.

set -uo pipefail

PROG=${0##*/}

have() { command -v "$1" >/dev/null 2>&1; }

# hook::git_untrusted: the worktree-remove-gate hook runs this script in a repository it did not create.
# shellcheck source=../hooks/hook-utils.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../hooks/hook-utils.sh" || exit 2

usage() {
  cat <<'EOF'
reap-project-plugin-records.sh: remove the project- and local-scope plugin records Claude Code holds for one worktree.

Usage:
  reap-project-plugin-records.sh --worktree-path <dir> [--dry-run]

  --worktree-path  the linked worktree whose records to reap (never a main working tree)
  --dry-run        list what would be reaped, change nothing

Output: one finding per line, `ok:` / `info:` / `warn:` / `error:`.

Exit codes:
  0  pass complete (including "no records recorded here")
  1  at least one record for this directory survived the pass
  2  usage error, or --worktree-path is unresolvable or a main working tree
  3  prerequisite missing (claude CLI, jq), or an enumeration failed
EOF
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

native_pwd() {
  local p
  p="$(pwd -W 2>/dev/null)" || p=""
  [[ -n "$p" ]] || p="$(pwd -P 2>/dev/null)" || p="$PWD"
  printf '%s' "$p"
}

windows_shell=false
case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*) windows_shell=true ;;
*) ;;
esac

norm_path() {
  local p="$1"
  p="$(printf '%s' "$p" | tr -d '\r' | tr "\134" '/' | tr -s '/')"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  if [[ "$windows_shell" == "true" ]]; then
    p="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  fi
  printf '%s' "$p"
}

resolve_dir() {
  [[ -d "$1" ]] || return 1
  (cd "$1" 2>/dev/null && native_pwd) || return 1
}

arg_native="$(resolve_dir "$worktree_path")" || arg_native=""
if [[ -z "$arg_native" ]]; then
  printf 'error: --worktree-path does not resolve to a directory: %s\n' "$worktree_path"
  printf 'info: the project scope has no path flag, so this script acts on the directory it stands in, which is the one --worktree-path names.\n'
  exit 2
fi

refuse_main_tree() {
  printf 'error: --worktree-path is a main working tree (%s) — refusing: %s\n' "$1" "$arg_native"
  printf 'info: this script reaps the records of a worktree being torn down, never those of a main checkout.\n'
  exit 2
}

[[ -d "$arg_native/.git" ]] && refuse_main_tree "its .git is a directory"
if [[ -f "$arg_native/.git" ]] && have git; then
  git_dirs="$(hook::git_untrusted -C "$arg_native" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)" || git_dirs=""
  if [[ -n "$git_dirs" && "${git_dirs%%$'\n'*}" == "${git_dirs#*$'\n'}" ]]; then
    refuse_main_tree "its git dir is its common dir"
  fi
fi

cd "$arg_native" 2>/dev/null || {
  printf 'error: could not enter --worktree-path: %s\n' "$arg_native"
  exit 2
}
here_native="$(native_pwd)"
here_key="$(norm_path "$here_native")"

have claude || {
  printf 'warn: claude CLI not on PATH — project-scope install records for this directory cannot be reaped.\n'
  printf 'info: the records survive the removal; re-run this script against a directory recreated at %s once the CLI is available.\n' "$here_native"
  exit 3
}
have jq || {
  printf 'warn: jq not available — cannot read the plugin list JSON, so records for this directory cannot be enumerated.\n'
  exit 3
}

list_ids() {
  local raw
  raw="$(claude plugin list --json 2>/dev/null)" || return 1
  [[ -n "$raw" ]] || return 1
  printf '%s' "$raw" | jq -r '
    (if type == "object" then (.installed // .plugins // []) else . end)
    | map(select(.scope == "project" or .scope == "local"))
    | .[]
    | [(.id // ""), (.projectPath // ""), .scope]
    | join("\t")
  ' 2>/dev/null | tr -d '\r' || return 1
}

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

SETTINGS_REL=".claude/settings.json"

file_fingerprint() {
  if [[ -f "$1" ]]; then
    cksum <"$1" 2>/dev/null || printf 'unreadable'
  else
    printf 'absent'
  fi
}

settings_git_state() {
  have git || {
    printf 'nogit'
    return
  }
  [[ "$(hook::git_untrusted rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || {
    printf 'nogit'
    return
  }
  hook::git_untrusted ls-files --error-unmatch -- "$SETTINGS_REL" >/dev/null 2>&1 || {
    printf 'untracked'
    return
  }
  case "$(hook::git_untrusted ls-files -v -- "$SETTINGS_REL" 2>/dev/null)" in
    [a-z]\ * | S\ *)
      printf 'flagged'
      return
      ;;
    *) ;;
  esac
  if hook::git_untrusted diff --quiet -- "$SETTINGS_REL" 2>/dev/null &&
    hook::git_untrusted diff --cached --quiet HEAD -- "$SETTINGS_REL" 2>/dev/null; then
    printf 'clean'
  else
    printf 'modified'
  fi
}

settings_before_state="$(settings_git_state)"
settings_before_print="$(file_fingerprint "$SETTINGS_REL")"

settle_settings() {
  local reason
  [[ "$(file_fingerprint "$SETTINGS_REL")" != "$settings_before_print" ]] || return 0
  if [[ "$settings_before_state" == "clean" ]]; then
    if hook::git_untrusted restore --source=HEAD --staged --worktree -- "$SETTINGS_REL" >/dev/null 2>&1 &&
      hook::git_untrusted diff --quiet HEAD -- "$SETTINGS_REL" 2>/dev/null; then
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
