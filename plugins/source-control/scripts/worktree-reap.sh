#!/usr/bin/env bash
set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $PROG [--dry-run] [--root DIR]... [--reap-after-hours N] [--idle-minutes N] [--log FILE | --no-log] [--no-pr-proof]

Removes a linked worktree under configured worktree roots, and its local branch,
only when every guard holds: after one \`git fetch --prune\` per repository the
branch's upstream is [gone], or the branch has no remote of its own and both the
worktree and its last commit are older than N hours; landed-work.sh reports a
safe clean idle verdict (landed, or ok for [gone] only); HEAD has not moved; no
process holds a path in it; any lock is proven stale by worktree-claim.sh; and
no .worktreeinclude carried file differs from or is new relative to main.

Options:
  --dry-run             Report what would be removed; remove nothing.
  --root DIR            Worktree root to scan (repeatable; default: all roots
                        from worktree-root-resolve.sh --all, else ~/worktrees).
  --reap-after-hours N  Reap age in hours (default: CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS
                        > settings.json pluginConfigs > 48).
  --idle-minutes N      Stale-lock idle window in minutes (default: 120).
  --log FILE            Append output to FILE and hold FILE.lock via flock
                        (default: \${XDG_STATE_HOME:-~/.local/state}/worktree-reap/reap.log).
  --no-log              Write to stdout/stderr only (skip log file and flock).
  --no-pr-proof         Do not pass --merged-pr-proof to landed-work.sh (offline).
  -h, --help            Show this help text.

Environment seams:
  WORKTREE_REAP_SCRIPTS    Override the source-control scripts directory.
  WORKTREE_REAP_PROC_ROOT  Override /proc for process-hold scans (testing).
  WORKTREE_REAP_NOW        Override current epoch seconds (testing).
EOF
}

resolve_default_hours() {
  local val="${CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS:-}"
  # shellcheck disable=SC2016
  if [[ -n "$val" && "$val" != *'${'* && "$val" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s' "$val"
    return 0
  fi
  local settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  if [[ -f "$settings" && -r "$settings" ]]; then
    val=""
    if command -v jq >/dev/null 2>&1; then
      val="$(jq -r '
        (.pluginConfigs["source-control@melodic-software"].options.worktree_reap_after_hours
         // .pluginConfigs["source-control"].options.worktree_reap_after_hours
         // empty) | tostring' "$settings" 2>/dev/null)" || val=""
    elif command -v python3 >/dev/null 2>&1; then
      val="$(python3 -I -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    pc = d.get("pluginConfigs") or {}
    for k in ("source-control@melodic-software", "source-control"):
        v = (pc.get(k) or {}).get("options", {}).get("worktree_reap_after_hours")
        if v is not None:
            print(v)
            break
except Exception:
    pass
' "$settings" 2>/dev/null)" || val=""
    fi
    if [[ "$val" =~ ^[1-9][0-9]*$ ]]; then
      printf '%s' "$val"
      return 0
    fi
  fi
  printf '48'
}

dry_run=false
hours=""
idle_minutes=120
use_log=true
no_pr_proof=false
log="${XDG_STATE_HOME:-$HOME/.local/state}/worktree-reap/reap.log"
cli_roots=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    dry_run=true
    shift
    ;;
  --root)
    [[ $# -ge 2 ]] || {
      printf '%s: --root requires a value\n' "$PROG" >&2
      exit 2
    }
    cli_roots+=("$2")
    shift 2
    ;;
  --reap-after-hours)
    [[ $# -ge 2 ]] || {
      printf '%s: --reap-after-hours requires a value\n' "$PROG" >&2
      exit 2
    }
    hours="$2"
    shift 2
    ;;
  --idle-minutes)
    [[ $# -ge 2 ]] || {
      printf '%s: --idle-minutes requires a value\n' "$PROG" >&2
      exit 2
    }
    idle_minutes="$2"
    shift 2
    ;;
  --log)
    [[ $# -ge 2 ]] || {
      printf '%s: --log requires a value\n' "$PROG" >&2
      exit 2
    }
    log="$2"
    use_log=true
    shift 2
    ;;
  --no-log)
    use_log=false
    shift
    ;;
  --no-pr-proof)
    no_pr_proof=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -n "$hours" ]]; then
  [[ "$hours" =~ ^[1-9][0-9]*$ ]] || {
    printf '%s: --reap-after-hours must be a positive integer\n' "$PROG" >&2
    exit 2
  }
else
  hours="$(resolve_default_hours)"
fi

[[ "$idle_minutes" =~ ^[0-9]{1,9}$ ]] || {
  printf '%s: --idle-minutes must be a non-negative integer\n' "$PROG" >&2
  exit 2
}

proc_root="${WORKTREE_REAP_PROC_ROOT:-/proc}"
now="${WORKTREE_REAP_NOW:-$(date +%s)}"
[[ "$now" =~ ^[0-9]+$ ]] || {
  printf '%s: WORKTREE_REAP_NOW must be epoch seconds\n' "$PROG" >&2
  exit 2
}

if $use_log; then
  mkdir -p "$(dirname -- "$log")"
  exec > >(tee -a "$log") 2>&1
  exec 9>"$log.lock"
  if ! flock -n 9; then
    printf '%s another reap run holds %s; exiting\n' "$(date -Is)" "$log.lock"
    exit 0
  fi
fi

export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never

scripts="${WORKTREE_REAP_SCRIPTS:-$SCRIPT_DIR}"
for s in lib/worktree-facts.sh landed-work.sh worktree-claim.sh worktree-root-resolve.sh worktree-include.sh; do
  [[ -f "$scripts/$s" ]] || {
    printf '%s: source-control script %s not found under %s; refusing\n' "$PROG" "$s" "$scripts"
    exit 2
  }
done

raw_roots=()
if ((${#cli_roots[@]} > 0)); then
  raw_roots=("${cli_roots[@]}")
else
  while IFS= read -r line; do
    line="${line%$'\r'}"
    [[ -n "$line" ]] && raw_roots+=("$line")
  done < <(bash "$scripts/worktree-root-resolve.sh" --all 2>/dev/null)
  if ((${#raw_roots[@]} == 0)); then
    raw_roots=("$HOME/worktrees")
  fi
fi

roots=()
declare -A seen_roots=()
for r in "${raw_roots[@]}"; do
  resolved=""
  if resolved="$(realpath -e -- "$r" 2>/dev/null)" && [[ -d "$resolved" ]]; then
    if [[ -z "${seen_roots[$resolved]+x}" ]]; then
      seen_roots["$resolved"]=1
      roots+=("$resolved")
    fi
  else
    printf '%s: worktree root %s does not resolve; skipping root\n' "$PROG" "$r"
  fi
done

if ((${#roots[@]} == 0)); then
  printf '%s: no worktree root resolved; nothing to do\n' "$PROG"
  exit 0
fi

mode=reap
$dry_run && mode=dry-run
roots_display="$(
  IFS=,
  printf '%s' "${roots[*]}"
)"
printf '%s start (%s): roots %s, reap age %s h, idle %s m, scripts %s\n' \
  "$(date -Is)" "$mode" "$roots_display" "$hours" "$idle_minutes" "$scripts"
avail_before=$(df -Pk -- "${roots[0]}" | awk 'NR==2 {print $4}')

scan_proc_targets_z() {
  (
    shopt -s nullglob
    local -a entries=("$proc_root"/[0-9]*/cwd "$proc_root"/[0-9]*/fd/*)
    ((${#entries[@]} > 0)) || exit 0
    find "${entries[@]}" -maxdepth 0 -type l -printf '%l\0' 2>/dev/null || true
  )
}

path_under_any_root() {
  local p="$1" r
  for r in "${roots[@]}"; do
    [[ "$p" == "$r"/* ]] && return 0
  done
  return 1
}

declare -A held=()
while IFS= read -r -d '' target; do
  while path_under_any_root "$target"; do
    held["$target"]=1
    target="${target%/*}"
  done
done < <(scan_proc_targets_z)

declare -A plugin_records=()
installed_plugins="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
if [[ -f "$installed_plugins" && -r "$installed_plugins" ]]; then
  read_plugin_paths() {
    if command -v jq >/dev/null 2>&1; then
      jq -r '.plugins // {} | .[]? | .[]?
        | select((.scope == "project" or .scope == "local")
          and (.projectPath | type == "string") and (.projectPath | length > 0))
        | .projectPath' "$installed_plugins" 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
      python3 -I -c '
import json, sys
d = json.load(open(sys.argv[1]))
for entries in (d.get("plugins") or {}).values():
    for e in entries:
        if e.get("scope") in ("project", "local") and e.get("projectPath"):
            print(e["projectPath"])
' "$installed_plugins" 2>/dev/null || true
    fi
  }
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    p_canon="$(realpath -e -- "$p" 2>/dev/null)" || p_canon="$p"
    plugin_records["$p_canon"]=$((${plugin_records["$p_canon"]:-0} + 1))
  done < <(read_plugin_paths)
fi

declare -A repos=()
for r in "${roots[@]}"; do
  while IFS= read -r -d '' gitfile; do
    [[ -f "$gitfile" && ! -L "$gitfile" ]] || continue
    gitdir="$(sed -n 's/^gitdir: //p' "$gitfile")"
    common="${gitdir%/worktrees/*}"
    [[ "$common" == */.git && -d "$common" ]] || continue
    repo_root="$(realpath -e -- "${common%/.git}" 2>/dev/null)" || repo_root="${common%/.git}"
    repos["$repo_root"]=1
  done < <(
    shopt -s nullglob
    for gf in "$r"/*/.git "$r"/.[!.]*/.git; do
      printf '%s\0' "$gf"
    done
  )
done

declare -A skipped=()
removed=0 removed_kib=0 would=0 would_kib=0 failed=0 gh_calls=0
skip() {
  skipped[$1]=$((${skipped[$1]:-0} + 1))
  case "$1" in
  remote-not-gone | detached | under-age) ;;
  *) printf '  skip %-16s %s%s\n' "$1" "$2" "${3:+ ($3)}" ;;
  esac
}
gh_limited=false
lw_err="$(mktemp)"
lw_stats="$(mktemp)"
trap 'rm -f "$lw_err" "$lw_stats"' EXIT
branch_ok() { [[ "$1" =~ ^[A-Za-z0-9._/-]+$ && "$1" != -* && "$1" != *..* ]]; }

mapfile -t repo_list < <(printf '%s\n' "${!repos[@]}" | sort)
for repo in "${repo_list[@]}"; do
  [[ -n "$repo" ]] || continue
  printf '%s repo %s\n' "$(date -Is)" "$repo"
  if $dry_run; then
    git -C "$repo" worktree prune --dry-run --verbose
  else
    git -C "$repo" worktree prune --verbose
  fi
  if ! timeout 180 git -C "$repo" fetch --prune --no-tags --quiet origin; then
    printf '  skip repo: fetch from origin failed or timed out; its worktrees are left alone\n'
    skipped[fetch-failed]=$((${skipped[fetch-failed]:-0} + 1))
    continue
  fi
  base=''
  for ref in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
    git -C "$repo" rev-parse -q --verify "$ref^{commit}" >/dev/null && {
      base=$ref
      break
    }
  done
  if [[ -n "$base" ]] && grep -qw down < <(git -C "$repo" show "$base:docs/conventions/workspace-environment.md" 2>/dev/null); then
    printf '  skip repo: declares a Workspace environment down command\n'
    skipped[workspace-down]=$((${skipped[workspace-down]:-0} + 1))
    continue
  fi

  declare -A gone=() own=()
  while IFS= read -r b; do
    own["${b#origin/}"]=1
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes/origin)
  while IFS=$'\t' read -r b track; do
    [[ "$track" == '[gone]' ]] && gone["$b"]=1
  done < <(git -C "$repo" for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads)

  cand=()
  declare -A cand_branch=() cand_locked=() cand_reason=() cand_head=() need_landed=()
  while IFS=$'\t' read -r path head branch _bare linked locked reason _prunable; do
    [[ "$path" == path || "$linked" != yes ]] && continue
    [[ -d "$path" ]] || continue
    path="$(realpath -e -- "$path" 2>/dev/null)" || continue
    path_under_any_root "$path" || continue
    branch="${branch#refs/heads/}"
    if [[ "$branch" == "(detached)" || "$branch" == "-" ]]; then
      skip detached "$path"
      continue
    fi
    if [[ -z "${gone[$branch]+x}" ]]; then
      if [[ -n "${own[$branch]+x}" ]]; then
        skip remote-not-gone "$path"
        continue
      fi
      # portability-ok: tries GNU stat -c first and falls back to BSD stat -f
      born="$(stat -c %Y -- "$path/.git" 2>/dev/null || stat -f %m -- "$path/.git" 2>/dev/null)" || born=''
      if [[ ! "$born" =~ ^[0-9]+$ ]] || (((now - born) / 3600 < hours)); then
        skip under-age "$path"
        continue
      fi
      need_landed["$path"]=1
    fi
    ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null)" || ct=''
    if [[ ! "$ct" =~ ^[0-9]+$ ]] || (((now - ct) / 3600 < hours)); then
      skip under-age "$path"
      continue
    fi
    if [[ -n "${held[$path]+x}" ]]; then
      skip process-holds "$path"
      continue
    fi
    cand_locked["$path"]="$locked"
    if [[ "$locked" == yes ]]; then
      if [[ "$reason" == "-" ]]; then
        cand_reason["$path"]=""
      else
        cand_reason["$path"]="$reason"
      fi
    fi
    cand+=("$path")
    cand_branch["$path"]="$branch"
    cand_head["$path"]="$head"
  done < <(bash "$scripts/lib/worktree-facts.sh" list "$repo")
  unset gone own
  if ((${#cand[@]} == 0)); then
    unset cand_branch cand_locked cand_reason cand_head need_landed
    continue
  fi

  args=(--repo-dir "$repo" --no-peers --stats-file "$lw_stats")
  if ! $no_pr_proof && ! $gh_limited; then
    args+=(--merged-pr-proof)
  fi
  for p in "${cand[@]}"; do
    args+=(--worktree "$p")
  done
  declare -A risk_ok=()
  rc=0
  : >"$lw_stats"
  record="$(bash "$scripts/landed-work.sh" "${args[@]}" 2>"$lw_err")" || rc=$?
  if ((rc)); then
    printf '  skip repo: landed-work.sh failed (exit %s); %s candidates left alone\n' "$rc" "${#cand[@]}"
    sed -n '1,5s/^/    landed-work.sh: /p' "$lw_err"
    skipped[landed-work-failed]=$((${skipped[landed-work-failed]:-0} + ${#cand[@]}))
    unset cand_branch cand_locked cand_reason cand_head risk_ok need_landed
    continue
  fi
  run_gh_calls=0
  run_rate_limited="no"
  while IFS='=' read -r k v; do
    case "$k" in
    gh_calls) [[ "$v" =~ ^[0-9]+$ ]] && run_gh_calls="$v" ;;
    rate_limited) run_rate_limited="$v" ;;
    *) ;;
    esac
  done <"$lw_stats"
  gh_calls=$((gh_calls + run_gh_calls))
  if ! $gh_limited && [[ "$run_rate_limited" == "yes" ]]; then
    gh_limited=true
    printf '  GitHub answered with a rate limit; the merged-PR proof is off for the rest of this run\n'
  fi

  while IFS=$'\t' read -r path _b _h _u _l _m _base inprog staged unstaged conflicted untracked _peers risk why; do
    [[ "$path" == path ]] && continue
    allowed='^(landed|ok)$'
    [[ -n "${need_landed[$path]+x}" ]] && allowed='^landed$'
    if [[ "$risk" =~ $allowed && "$inprog" == none && "$staged$unstaged$conflicted$untracked" == 0000 ]]; then
      risk_ok["$path"]=1
    else
      risk_ok["$path"]="risk=$risk inprogress=$inprog staged=$staged unstaged=$unstaged conflicted=$conflicted untracked=$untracked: $why"
    fi
  done <<<"$record"

  eligible=()
  locked_cands=()
  for path in "${cand[@]}"; do
    branch="${cand_branch[$path]}"
    if [[ "${risk_ok[$path]:-}" != 1 ]]; then
      skip unsafe-work "$path" "${risk_ok[$path]:-no landed-work row}"
      continue
    fi
    inc_rc=0
    inc_out="$(bash "$scripts/worktree-include.sh" diff "$path" --main-root "$repo" --worktree-only 2>/dev/null)" || inc_rc=$?
    if ((inc_rc == 1)); then
      first_rel="$(printf '%s\n' "$inc_out" | head -n 1 | cut -f2)"
      skip carried-file "$path" "${first_rel:-carried file} differs from the main checkout"
      continue
    elif ((inc_rc != 0)); then
      skip carried-file "$path" "worktree-include diff unreadable (exit $inc_rc)"
      continue
    fi
    if ! branch_ok "$branch"; then
      skip branch-name "$path" "$branch"
      continue
    fi
    eligible+=("$path")
    if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
      locked_cands+=("$path")
    fi
  done

  declare -A stale_rc=() stale_note=()
  if ((${#locked_cands[@]} > 0)); then
    batch_rc=0
    batch_out="$(printf '%s\0' "${locked_cands[@]}" |
      bash "$scripts/worktree-claim.sh" stale --batch --repo-dir "$repo" --idle-minutes "$idle_minutes" 2>/dev/null)" || batch_rc=$?
    if ((batch_rc == 0)); then
      while IFS=$'\t' read -r s_rc s_path s_note; do
        [[ -n "$s_path" ]] || continue
        stale_rc["$s_path"]="$s_rc"
        stale_note["$s_path"]="$s_note"
      done <<<"$batch_out"
    fi
  fi

  for path in "${eligible[@]}"; do
    branch="${cand_branch[$path]}"
    if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
      if [[ "${stale_rc[$path]:-1}" != "0" ]]; then
        skip live-lock "$path" "${cand_reason[$path]:-<no reason>}"
        continue
      fi
      printf '  stale lock %s: %s\n' "$path" "${stale_note[$path]}"
    fi
    kib="$(du -sk -- "$path" 2>/dev/null | cut -f1)" || kib=0
    kib="${kib:-0}"
    records="${plugin_records[$path]:-0}"
    if $dry_run; then
      printf '  would remove %s (branch %s, %s KiB)\n' "$path" "$branch" "$kib"
      ((records)) && printf '    leaves %s project/local-scope plugin record(s)\n' "$records"
      would=$((would + 1))
      would_kib=$((would_kib + kib))
      continue
    fi

    seen_proc=0
    proc_hit=0
    while IFS= read -r -d '' target; do
      seen_proc=1
      if [[ "$target" == "$path" || "$target" == "$path"/* ]]; then
        proc_hit=1
        break
      fi
    done < <(scan_proc_targets_z)
    if ((seen_proc == 0)); then
      skip process-scan "$path" 'no /proc entries readable'
      continue
    fi
    if ((proc_hit)); then
      skip process-holds "$path" 'a process entered it during the run'
      continue
    fi

    head="${cand_head[$path]}"
    if [[ "$(git -C "$path" rev-parse -q --verify HEAD)" != "$head" ||
      "$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch")" != "$head" ]]; then
      skip head-moved "$path" "HEAD moved after the analysis of $head"
      continue
    fi

    if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
      if ! bash "$scripts/worktree-claim.sh" stale "$path" --repo-dir "$repo" --idle-minutes "$idle_minutes" >/dev/null 2>&1; then
        skip live-lock "$path" 'lock went live before removal'
        continue
      fi
      git -C "$repo" worktree unlock "$path" || {
        skip unlock-failed "$path"
        continue
      }
    fi

    if ! git -C "$repo" worktree remove "$path"; then
      if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
        if [[ -n "${cand_reason[$path]}" ]]; then
          git -C "$repo" worktree lock --reason "${cand_reason[$path]}" "$path" || true
        else
          git -C "$repo" worktree lock "$path" || true
        fi
      fi
      printf '  FAILED to remove %s; left in place\n' "$path"
      failed=$((failed + 1))
      continue
    fi

    if [[ -e "$path" ]]; then
      printf '  HUSK REMAINS %s (unregistered; a process may hold it)\n' "$path"
      failed=$((failed + 1))
    fi
    if [[ "$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch")" != "$head" ]]; then
      printf '  kept branch %s: it moved off the analyzed %s\n' "$branch" "$head"
    else
      git -C "$repo" branch -D --end-of-options "$branch" ||
        printf '  kept branch %s: git refused to delete it\n' "$branch"
    fi
    printf '  removed %s (branch %s, %s KiB)\n' "$path" "$branch" "$kib"
    ((records)) && printf '    left %s project/local-scope plugin record(s); reap with reap-orphaned-plugin-records.sh\n' "$records"
    removed=$((removed + 1))
    removed_kib=$((removed_kib + kib))
  done

  $dry_run || git -C "$repo" worktree prune
  unset cand_branch cand_locked cand_reason cand_head risk_ok need_landed stale_rc stale_note
done

avail_after=$(df -Pk -- "${roots[0]}" | awk 'NR==2 {print $4}')
summary=''
for r in $(printf '%s\n' "${!skipped[@]}" | sort); do
  summary+=" $r=${skipped[$r]}"
done
if $dry_run; then
  printf '%s total: would remove %s worktrees, %s KiB (%s GiB); gh calls %s; skipped:%s\n' "$(date -Is)" \
    "$would" "$would_kib" "$((would_kib / 1048576))" "$gh_calls" "${summary:- none}"
else
  printf '%s total: removed %s worktrees, %s KiB by du (%s GiB); free space on %s went %s -> %s KiB; %s failed; gh calls %s; skipped:%s\n' \
    "$(date -Is)" "$removed" "$removed_kib" "$((removed_kib / 1048576))" "${roots[0]}" "$avail_before" "$avail_after" "$failed" "$gh_calls" "${summary:- none}"
fi
((failed == 0))
