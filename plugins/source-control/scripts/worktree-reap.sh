#!/usr/bin/env bash
set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $PROG [--dry-run] [--root DIR]... [--reap-after-hours N] [--idle-minutes N] [--log FILE | --no-log] [--no-pr-proof]
       $PROG --report [RUN-FILE] [--log FILE]

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
  --report [RUN-FILE]   Print the report for RUN-FILE (default: the newest run
                        file) and exit. Needs jq or python3.
  -h, --help            Show this help text.

Run record: each run writes runs/<utc>.jsonl in the log's directory (also under
--no-log): one {"type":"worktree"} line per examined worktree with its facts,
verdict (remove, keep or review), reason and outcome, and one closing
{"type":"run"} line. Run and reviews/ files older than 14 days are deleted at
start. The closing summary is the report for the run's own file.

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

# Prints the run report from a run file: verdict counts, then the closing total line.
# shellcheck disable=SC2016 # jq variables, not shell expansions
REPORT_JQ='
  (map(select(.type == "worktree"))) as $w
  | ((map(select(.type == "run")) | .[0]) // {}) as $r
  | ($w | map(select(.outcome == "kept")) | group_by(.reason)
      | map("\(.[0].reason)=\(length)") | join(" ")) as $sk
  | ($w | group_by(.verdict) | map("\(.[0].verdict)=\(length)") | join(" ")) as $vc
  | ($w | map(select(.outcome == "remove-failed" or .outcome == "husk")) | length) as $fl
  | ($r.memory_cgroup // "unknown") as $cg
  | ($r.stale_work // []) as $sw
  | "verdicts: \(if $vc == "" then "none" else $vc end)",
    "phases: \(($r.phases_ms // {}) | to_entries | map("\(.key)=\(.value)ms") | join(" "))",
    "memory peak: \($r.memory_peak // "unknown") bytes\(if $cg == "unknown" then "" elif ($cg | endswith(".service")) then " (cgroup \($cg))" else " (cgroup \($cg), not the reap service own scope)" end)",
    "stale .work: \($sw | length) item(s), \($sw | map(.kib) | add // 0) KiB",
    ($sw[] | "  \(.kib) KiB \(.path)"),
    (if $r.mode == "dry-run" then
      "\($r.end) total: would remove \($r.would) worktrees, \($r.would_kib) KiB (\($r.would_kib / 1048576 | floor) GiB); gh calls \($r.gh_calls); skipped: \(if $sk == "" then "none" else $sk end)"
    else
      "\($r.end) total: removed \($r.removed) worktrees, \($r.removed_kib) KiB by du (\($r.removed_kib / 1048576 | floor) GiB); free space on \($r.root) went \($r.avail_before) -> \($r.avail_after) KiB; \($fl) failed; gh calls \($r.gh_calls); skipped: \(if $sk == "" then "none" else $sk end)"
    end)'
REPORT_PY='
import json, sys
w, r = [], {}
for line in open(sys.argv[1]):
    d = json.loads(line)
    if d.get("type") == "worktree": w.append(d)
    elif d.get("type") == "run": r = d
def counts(rows, key):
    c = {}
    for x in rows: c[x[key]] = c.get(x[key], 0) + 1
    return " ".join("%s=%d" % kv for kv in sorted(c.items())) or "none"
sk = counts([x for x in w if x["outcome"] == "kept"], "reason")
fl = sum(1 for x in w if x["outcome"] in ("remove-failed", "husk"))
print("verdicts: " + counts(w, "verdict"))
print("phases: " + " ".join("%s=%sms" % kv for kv in (r.get("phases_ms") or {}).items()))
cg = r.get("memory_cgroup") or "unknown"
scope = "" if cg == "unknown" else " (cgroup %s)" % cg if cg.endswith(".service") else " (cgroup %s, not the reap service own scope)" % cg
print("memory peak: %s bytes%s" % (r.get("memory_peak", "unknown"), scope))
sw = r.get("stale_work") or []
print("stale .work: %d item(s), %d KiB" % (len(sw), sum(x["kib"] for x in sw)))
for x in sw: print("  %s KiB %s" % (x["kib"], x["path"]))
if r.get("mode") == "dry-run":
    print("%s total: would remove %s worktrees, %s KiB (%d GiB); gh calls %s; skipped: %s" % (r.get("end"), r.get("would"), r.get("would_kib"), r.get("would_kib", 0) // 1048576, r.get("gh_calls"), sk))
else:
    print("%s total: removed %s worktrees, %s KiB by du (%d GiB); free space on %s went %s -> %s KiB; %d failed; gh calls %s; skipped: %s" % (r.get("end"), r.get("removed"), r.get("removed_kib"), r.get("removed_kib", 0) // 1048576, r.get("root"), r.get("avail_before"), r.get("avail_after"), fl, r.get("gh_calls"), sk))
'
report() {
  local f="$1"
  if [[ ! -f "$f" || ! -r "$f" ]]; then
    printf '%s: no readable run file: %s\n' "$PROG" "$f"
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -rs "$REPORT_JQ" "$f"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c "$REPORT_PY" "$f"
  else
    printf '%s: report unavailable (needs jq or python3); run file %s\n' "$PROG" "$f"
  fi
}

dry_run=false
hours=""
idle_minutes=120
use_log=true
no_pr_proof=false
report_only=false
report_file=""
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
    --report)
      report_only=true
      if [[ $# -ge 2 && "$2" != -* ]]; then
        report_file="$2"
        shift
      fi
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

state_dir="$(dirname -- "$log")"
runs_dir="$state_dir/runs"
if $report_only; then
  if [[ -z "$report_file" ]]; then
    report_file="$(find "$runs_dir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null | sort | tail -n 1)"
  fi
  report "${report_file:-$runs_dir/<none>}"
  exit
fi

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

mkdir -p "$runs_dir" "$state_dir/reviews"
find "$runs_dir" "$state_dir/reviews" -maxdepth 1 -type f -name '*.jsonl' -mtime +14 -delete 2>/dev/null || true
t_now="$EPOCHREALTIME"
TZ=UTC0 printf -v run_stamp '%(%Y%m%dT%H%M%S)T' "${t_now%[.,]*}"
run_file="$runs_dir/$run_stamp.${t_now#*[.,]}Z.jsonl"
: >"$run_file"

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

removed=0 removed_kib=0 would=0 would_kib=0 failed=0 gh_calls=0

json_str() {
  local s="$1" out="" c i hex
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  if [[ "$s" == *[$'\x01'-$'\x1f']* ]]; then
    for ((i = 0; i < ${#s}; i++)); do
      c="${s:i:1}"
      if [[ "$c" == [$'\x01'-$'\x1f'] ]]; then
        printf -v hex '\\u%04x' "'$c"
        out+="$hex"
      else
        out+="$c"
      fi
    done
    s="$out"
  fi
  REPLY="\"$s\""
}

declare -A FACT=() FRAG=() DETAIL=()
set_fact() {
  local p="$1" owner="$2" key="$3" val="$4"
  FACT["$p|$key"]="$val"
  json_str "$val"
  FRAG["$p|$owner"]+="${FRAG["$p|$owner"]:+,}\"$key\":$REPLY"
}

emit_record() {
  local p="$1" line owner frag sep=""
  json_str "$p"
  line="{\"type\":\"worktree\",\"path\":$REPLY"
  json_str "$2"
  line+=",\"repo\":$REPLY"
  json_str "$3"
  line+=",\"branch\":$REPLY"
  json_str "$4"
  line+=",\"head\":$REPLY,\"verdict\":\"$5\",\"reason\":\"$6\",\"outcome\":\"$7\",\"facts\":{"
  for owner in worktree-reap landed-work worktree-include worktree-claim; do
    frag="${FRAG["$p|$owner"]:-}"
    [[ -n "$frag" ]] || continue
    line+="$sep\"$owner\":{$frag}"
    sep=","
  done
  printf '%s}}\n' "$line" >>"$run_file"
  [[ "$7" == kept ]] || return 0
  case "$6" in
    remote-not-gone | detached | under-age | fetch-failed | workspace-down | landed-work-failed) ;;
    *) printf '  skip %-16s %s%s\n' "$6" "$p" "${DETAIL[$p]:+ (${DETAIL[$p]})}" ;;
  esac
}

decide() {
  local p="$1" final="$2" risk up
  DECISION=""
  need() {
    [[ -n "${FACT["$p|$1"]+x}" ]] && return 0
    if ((final)); then DECISION="keep unknown"; else DECISION="pending"; fi
    return 1
  }
  case "${FACT["$p|repo"]:-}" in
    fetch-failed | workspace-down)
      DECISION="keep ${FACT["$p|repo"]}"
      return
      ;;
    *) ;;
  esac
  [[ "${FACT["$p|missing"]:-}" == yes ]] && {
    DECISION="keep missing"
    return
  }
  need detached || return
  [[ "${FACT["$p|detached"]}" == yes ]] && {
    DECISION="keep detached"
    return
  }
  need upstream || return
  up="${FACT["$p|upstream"]}"
  [[ "$up" == own-remote ]] && {
    DECISION="keep remote-not-gone"
    return
  }
  need age_ok || return
  [[ "${FACT["$p|age_ok"]}" == yes ]] || {
    DECISION="keep under-age"
    return
  }
  need held || return
  [[ "${FACT["$p|held"]}" == no ]] || {
    DECISION="keep process-holds"
    return
  }
  need landed_work || return
  case "${FACT["$p|landed_work"]}" in
    failed)
      DECISION="keep landed-work-failed"
      return
      ;;
    no-row)
      DECISION="keep no-landed-work-row"
      return
      ;;
    *) ;;
  esac
  risk="${FACT["$p|risk"]:-}"
  case "$risk" in
    STRANDED)
      DECISION="review stranded"
      return
      ;;
    UNKNOWN)
      DECISION="review unknown-work"
      return
      ;;
    in-progress | dirty)
      DECISION="keep dirty"
      return
      ;;
    notgit | bare | superseded)
      DECISION="keep not-landed"
      return
      ;;
    ok) [[ "$up" == gone ]] || {
      DECISION="keep not-landed"
      return
    } ;;
    landed) ;;
    *)
      DECISION="keep unknown"
      return
      ;;
  esac
  if [[ "${FACT["$p|inprogress"]:-}" != none || "${FACT["$p|changes"]:-}" != 0000 ]]; then
    DECISION="keep dirty"
    return
  fi
  need carried_rc || return
  case "${FACT["$p|carried_rc"]}" in
    0) ;;
    1)
      case "${FACT["$p|carried_status"]:-}" in
        MODIFIED | NEW) DECISION="review carried-edited" ;;
        NO-MANIFEST) DECISION="review no-manifest" ;;
        *) DECISION="keep carried-unreadable" ;;
      esac
      return
      ;;
    *)
      DECISION="keep carried-unreadable"
      return
      ;;
  esac
  need branch_ok || return
  [[ "${FACT["$p|branch_ok"]}" == yes ]] || {
    DECISION="keep branch-name"
    return
  }
  need locked || return
  if [[ "${FACT["$p|locked"]}" == yes ]]; then
    need stale_rc || return
    [[ "${FACT["$p|stale_rc"]}" == 0 ]] || {
      DECISION="keep live-lock"
      return
    }
  fi
  if [[ "${FACT["$p|carried_rc"]}" == 0 && "${FACT["$p|branch_ok"]}" == yes && "${FACT["$p|inprogress"]}" == none &&
    "${FACT["$p|changes"]}" == 0000 && ("$risk" == landed || ("$risk" == ok && "$up" == gone)) &&
    ("${FACT["$p|locked"]}" == no || "${FACT["$p|stale_rc"]:-}" == 0) ]]; then
    DECISION="remove landed"
  else
    DECISION="keep unknown"
  fi
}

keep_row() {
  decide "$1" 1
  emit_record "$1" "$2" "$3" "$4" "${DECISION%% *}" "${DECISION#* }" kept
}

repo_keep() {
  local repo="$1" why="$2" wpath whead wbranch _b wlinked _rest real
  while IFS=$'\t' read -r wpath whead wbranch _b wlinked _rest; do
    [[ "$wpath" == path || "$wlinked" != yes ]] && continue
    real="$(realpath -e -- "$wpath" 2>/dev/null)" || real="$wpath"
    path_under_any_root "$real" || continue
    set_fact "$real" worktree-reap repo "$why"
    keep_row "$real" "$repo" "${wbranch#refs/heads/}" "$whead"
  done < <(bash "$scripts/lib/worktree-facts.sh" list "$repo")
}

gh_limited=false
lw_err="$(mktemp)"
lw_stats="$(mktemp)"
trap 'rm -f "$lw_err" "$lw_stats"' EXIT
branch_ok() { [[ "$1" =~ ^[A-Za-z0-9._/-]+$ && "$1" != -* && "$1" != *..* ]]; }

declare -A PHASE_US=([fetch]=0 [landed-work]=0 [carried]=0 [stale]=0 [remove]=0)
phase_add() {
  local now_us="${EPOCHREALTIME/[.,]/}"
  PHASE_US[$1]=$((PHASE_US[$1] + now_us - $2))
}

mapfile -t repo_list < <(printf '%s\n' "${!repos[@]}" | sort)
for repo in "${repo_list[@]}"; do
  [[ -n "$repo" ]] || continue
  printf '%s repo %s\n' "$(date -Is)" "$repo"
  t0="${EPOCHREALTIME/[.,]/}"
  if $dry_run; then
    git -C "$repo" worktree prune --dry-run --verbose
  else
    git -C "$repo" worktree prune --verbose
  fi
  if ! timeout 180 git -C "$repo" fetch --prune --no-tags --quiet origin; then
    phase_add fetch "$t0"
    printf '  skip repo: fetch from origin failed or timed out; its worktrees are left alone\n'
    repo_keep "$repo" fetch-failed
    continue
  fi
  phase_add fetch "$t0"
  base=''
  for ref in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
    git -C "$repo" rev-parse -q --verify "$ref^{commit}" >/dev/null && {
      base=$ref
      break
    }
  done
  if [[ -n "$base" ]] && grep -qw down < <(git -C "$repo" show "$base:docs/conventions/workspace-environment.md" 2>/dev/null); then
    printf '  skip repo: declares a Workspace environment down command\n'
    repo_keep "$repo" workspace-down
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
  declare -A cand_branch=() cand_locked=() cand_reason=() cand_head=()
  while IFS=$'\t' read -r path head branch _bare linked locked reason _prunable; do
    [[ "$path" == path || "$linked" != yes ]] && continue
    branch="${branch#refs/heads/}"
    raw="$path"
    if [[ ! -d "$path" ]] || ! path="$(realpath -e -- "$path" 2>/dev/null)"; then
      path_under_any_root "$raw" || continue
      set_fact "$raw" worktree-reap missing yes
      keep_row "$raw" "$repo" "$branch" "$head"
      continue
    fi
    path_under_any_root "$path" || continue
    if [[ "$branch" == "(detached)" || "$branch" == "-" ]]; then
      set_fact "$path" worktree-reap detached yes
      keep_row "$path" "$repo" "$branch" "$head"
      continue
    fi
    set_fact "$path" worktree-reap detached no
    if [[ -n "${gone[$branch]+x}" ]]; then
      set_fact "$path" worktree-reap upstream gone
    elif [[ -n "${own[$branch]+x}" ]]; then
      set_fact "$path" worktree-reap upstream own-remote
    else
      set_fact "$path" worktree-reap upstream none
    fi
    age_ok=yes
    if [[ "${FACT["$path|upstream"]}" == none ]]; then
      # portability-ok: tries GNU stat -c first and falls back to BSD stat -f
      born="$(stat -c %Y -- "$path/.git" 2>/dev/null || stat -f %m -- "$path/.git" 2>/dev/null)" || born=''
      if [[ ! "$born" =~ ^[0-9]+$ ]] || (((now - born) / 3600 < hours)); then
        age_ok=no
      fi
    fi
    if [[ "$age_ok" == yes && "${FACT["$path|upstream"]}" != own-remote ]]; then
      ct="$(git -C "$repo" log -1 --format=%ct "refs/heads/$branch" 2>/dev/null)" || ct=''
      if [[ ! "$ct" =~ ^[0-9]+$ ]] || (((now - ct) / 3600 < hours)); then
        age_ok=no
      fi
    fi
    set_fact "$path" worktree-reap age_ok "$age_ok"
    if [[ -n "${held[$path]+x}" ]]; then
      set_fact "$path" worktree-reap held yes
    else
      set_fact "$path" worktree-reap held no
    fi
    decide "$path" 0
    if [[ "$DECISION" != pending ]]; then
      emit_record "$path" "$repo" "$branch" "$head" "${DECISION%% *}" "${DECISION#* }" kept
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
    unset cand_branch cand_locked cand_reason cand_head
    continue
  fi

  args=(--repo-dir "$repo" --no-peers --stats-file "$lw_stats")
  if ! $no_pr_proof && ! $gh_limited; then
    args+=(--merged-pr-proof)
  fi
  for p in "${cand[@]}"; do
    args+=(--worktree "$p")
  done
  rc=0
  : >"$lw_stats"
  t0="${EPOCHREALTIME/[.,]/}"
  record="$(bash "$scripts/landed-work.sh" "${args[@]}" 2>"$lw_err")" || rc=$?
  phase_add landed-work "$t0"
  if ((rc)); then
    printf '  skip repo: landed-work.sh failed (exit %s); %s candidates left alone\n' "$rc" "${#cand[@]}"
    sed -n '1,5s/^/    landed-work.sh: /p' "$lw_err"
    for path in "${cand[@]}"; do
      set_fact "$path" landed-work landed_work failed
      keep_row "$path" "$repo" "${cand_branch[$path]}" "${cand_head[$path]}"
    done
    unset cand_branch cand_locked cand_reason cand_head
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
    [[ "$path" == path || -z "${cand_branch[$path]+x}" ]] && continue
    set_fact "$path" landed-work landed_work row
    set_fact "$path" landed-work risk "$risk"
    set_fact "$path" landed-work inprogress "$inprog"
    set_fact "$path" landed-work changes "$staged$unstaged$conflicted$untracked"
    set_fact "$path" landed-work reason "$why"
    DETAIL["$path"]="risk=$risk inprogress=$inprog staged=$staged unstaged=$unstaged conflicted=$conflicted untracked=$untracked: $why"
  done <<<"$record"

  eligible=()
  locked_cands=()
  for path in "${cand[@]}"; do
    branch="${cand_branch[$path]}"
    [[ -n "${FACT["$path|landed_work"]+x}" ]] || set_fact "$path" landed-work landed_work no-row
    decide "$path" 0
    if [[ "$DECISION" != pending ]]; then
      emit_record "$path" "$repo" "$branch" "${cand_head[$path]}" "${DECISION%% *}" "${DECISION#* }" kept
      continue
    fi
    inc_rc=0
    t0="${EPOCHREALTIME/[.,]/}"
    inc_out="$(bash "$scripts/worktree-include.sh" diff "$path" --main-root "$repo" --worktree-only 2>/dev/null)" || inc_rc=$?
    phase_add carried "$t0"
    set_fact "$path" worktree-include carried_rc "$inc_rc"
    if ((inc_rc == 1)); then
      set_fact "$path" worktree-include carried_status "$(printf '%s\n' "$inc_out" | head -n 1 | cut -f1)"
      first_rel="$(printf '%s\n' "$inc_out" | head -n 1 | cut -f2)"
      DETAIL["$path"]="${first_rel:-carried file} differs from the main checkout"
    elif ((inc_rc != 0)); then
      DETAIL["$path"]="worktree-include diff unreadable (exit $inc_rc)"
    fi
    if branch_ok "$branch"; then
      set_fact "$path" worktree-reap branch_ok yes
    else
      set_fact "$path" worktree-reap branch_ok no
      DETAIL["$path"]="$branch"
    fi
    set_fact "$path" worktree-reap locked "${cand_locked[$path]:-no}"
    decide "$path" 0
    case "$DECISION" in
      pending) locked_cands+=("$path") ;;
      "remove landed") ;;
      *)
        emit_record "$path" "$repo" "$branch" "${cand_head[$path]}" "${DECISION%% *}" "${DECISION#* }" kept
        continue
        ;;
    esac
    eligible+=("$path")
  done

  declare -A stale_note=()
  if ((${#locked_cands[@]} > 0)); then
    batch_rc=0
    t0="${EPOCHREALTIME/[.,]/}"
    batch_out="$(printf '%s\0' "${locked_cands[@]}" |
      bash "$scripts/worktree-claim.sh" stale --batch --repo-dir "$repo" --idle-minutes "$idle_minutes" 2>/dev/null)" || batch_rc=$?
    phase_add stale "$t0"
    if ((batch_rc == 0)); then
      while IFS=$'\t' read -r s_rc s_path s_note; do
        [[ -n "$s_path" && -n "${cand_branch[$s_path]+x}" ]] || continue
        set_fact "$s_path" worktree-claim stale_rc "$s_rc"
        stale_note["$s_path"]="$s_note"
      done <<<"$batch_out"
    fi
    for path in "${locked_cands[@]}"; do
      [[ -n "${FACT["$path|stale_rc"]+x}" ]] || set_fact "$path" worktree-claim stale_rc unread
    done
  fi

  t_remove="${EPOCHREALTIME/[.,]/}"
  for path in "${eligible[@]}"; do
    branch="${cand_branch[$path]}"
    head="${cand_head[$path]}"
    decide "$path" 1
    if [[ "$DECISION" != "remove landed" ]]; then
      [[ "$DECISION" == "keep live-lock" ]] && DETAIL["$path"]="${cand_reason[$path]:-<no reason>}"
      emit_record "$path" "$repo" "$branch" "$head" "${DECISION%% *}" "${DECISION#* }" kept
      continue
    fi
    if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
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
      emit_record "$path" "$repo" "$branch" "$head" remove landed would-remove
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
      DETAIL["$path"]='no /proc entries readable'
      emit_record "$path" "$repo" "$branch" "$head" remove process-scan kept
      continue
    fi
    if ((proc_hit)); then
      DETAIL["$path"]='a process entered it during the run'
      emit_record "$path" "$repo" "$branch" "$head" remove process-entered kept
      continue
    fi

    if [[ "$(git -C "$path" rev-parse -q --verify HEAD)" != "$head" ||
    "$(git -C "$repo" rev-parse -q --verify "refs/heads/$branch")" != "$head" ]]; then
      DETAIL["$path"]="HEAD moved after the analysis of $head"
      emit_record "$path" "$repo" "$branch" "$head" remove head-moved kept
      continue
    fi

    if [[ "${cand_locked[$path]:-no}" == "yes" ]]; then
      if ! bash "$scripts/worktree-claim.sh" stale "$path" --repo-dir "$repo" --idle-minutes "$idle_minutes" >/dev/null 2>&1; then
        DETAIL["$path"]='lock went live before removal'
        emit_record "$path" "$repo" "$branch" "$head" remove lock-went-live kept
        continue
      fi
      if ! git -C "$repo" worktree unlock "$path"; then
        emit_record "$path" "$repo" "$branch" "$head" remove unlock-failed kept
        continue
      fi
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
      emit_record "$path" "$repo" "$branch" "$head" remove landed remove-failed
      continue
    fi

    outcome=removed
    if [[ -e "$path" ]]; then
      printf '  HUSK REMAINS %s (unregistered; a process may hold it)\n' "$path"
      failed=$((failed + 1))
      outcome=husk
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
    emit_record "$path" "$repo" "$branch" "$head" remove landed "$outcome"
  done
  phase_add remove "$t_remove"

  $dry_run || git -C "$repo" worktree prune
  unset cand_branch cand_locked cand_reason cand_head stale_note
done

stale_work=""
for repo in "${repo_list[@]}"; do
  [[ -d "$repo/.work" ]] || continue
  for item in "$repo"/.work/*; do
    [[ -e "$item" ]] || continue
    [[ -z "$(find "$item" -type f -mtime -30 -print -quit 2>/dev/null)" ]] || continue
    kib="$(du -sk -- "$item" 2>/dev/null | cut -f1)"
    json_str "$item"
    stale_work+="${stale_work:+,}{\"path\":$REPLY,\"kib\":${kib:-0}}"
  done
done

mem_peak=unknown mem_cgroup=unknown
cgroup="$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)"
if [[ -n "$cgroup" && -r "/sys/fs/cgroup$cgroup/memory.peak" ]]; then
  mem_peak="$(<"/sys/fs/cgroup$cgroup/memory.peak")"
  mem_cgroup="$cgroup"
fi
phases=""
for ph in fetch landed-work carried stale remove; do
  phases+="${phases:+,}\"$ph\":$((PHASE_US[$ph] / 1000))"
done

avail_after=$(df -Pk -- "${roots[0]}" | awk 'NR==2 {print $4}')
json_str "${roots[0]}"
root_json="$REPLY"
json_str "$mem_cgroup"
printf '{"type":"run","mode":"%s","end":"%s","removed":%d,"removed_kib":%d,"would":%d,"would_kib":%d,"failed":%d,"gh_calls":%d,"root":%s,"avail_before":"%s","avail_after":"%s","phases_ms":{%s},"memory_peak":"%s","memory_cgroup":%s,"stale_work":[%s]}\n' \
  "$mode" "$(date -Is)" "$removed" "$removed_kib" "$would" "$would_kib" "$failed" "$gh_calls" "$root_json" \
  "$avail_before" "$avail_after" "$phases" "$mem_peak" "$REPLY" "$stale_work" >>"$run_file"
report "$run_file"
((failed == 0))
