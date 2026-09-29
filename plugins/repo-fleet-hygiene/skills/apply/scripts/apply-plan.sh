#!/usr/bin/env bash
# apply-plan.sh — consume a fleet action-plan JSON behind one batch confirmation.
#
# Default: dry-run / preview (refresh evidence, print the ordered plan, mutate nothing).
# --apply: after one batch-wide confirmation (or --yes), execute deletes in plan order.
#
# This verb owns batched merged-local-branch deletion. It does not widen audit-fleet.sh.
# Mutable OIDs are re-derived immediately before every delete; tip drift skips fail-closed.
#
# delete-remote-branches actions run only under --remote-branches, one prompt per branch that
# --yes never answers, after the live tip is re-read with ls-remote. Each tip is appended to a
# ledger next to the plan file before the lease-guarded push deletes the head.
#
# Exit: 0 success (including dry-run / confirmation-stop); 2 usage/plan error; 3 apply aborted
# by confirmation gate; 4 one or more mutations failed after the gate.
# shellcheck disable=SC2310 # git_probe, git_mutate and status predicates return status in if/||/!; every false path is handled
set -euo pipefail

PROG=${0##*/}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

print_field() {
  printf '%s: %s\n' "$1" "$2"
}

usage() {
  cat <<EOF
Usage: $PROG --plan-file PATH [--apply] [--yes] [--remote-branches]
       $PROG --help

Consume a machine-readable fleet action plan from a prior /repo-fleet-hygiene:audit.

Default is dry-run: re-derive branch/worktree tips, print the ordered batch, mutate nothing.
--apply requires interactive confirmation, or --yes / -y for non-interactive consent.
One confirmation gate covers the entire plan (not per repository).

Order: delete-merged-local-branches, cleanup-worktrees, then delete-remote-branches.
Every delete re-derives the tip OID and skips on drift / protected / attached / stranded.

delete-remote-branches actions are skipped unless --remote-branches is given. With it, each
branch gets its own prompt (repo, remote, branch, class, tip) and only an explicit yes deletes
it; --yes does not answer that prompt, and a non-interactive session deletes nothing. The tip
is appended to PLAN_FILE.tip-ledger before the lease-guarded push.
EOF
}

PLAN_FILE=""
DO_APPLY=0
YES=0
REMOTE_BRANCHES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --plan-file)
    [[ $# -ge 2 && -n "$2" ]] || fail "--plan-file requires a path"
    [[ -z "$PLAN_FILE" ]] || fail "--plan-file may be supplied only once"
    PLAN_FILE=$2
    shift 2
    ;;
  --apply)
    DO_APPLY=1
    shift
    ;;
  --yes | -y)
    YES=1
    shift
    ;;
  --remote-branches)
    REMOTE_BRANCHES=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    break
    ;;
  -*)
    fail "unknown flag: $1"
    ;;
  *)
    fail "unexpected argument: $1 (require --plan-file PATH)"
    ;;
  esac
done
[[ $# -eq 0 ]] || fail "unexpected argument: $1"
[[ -n "$PLAN_FILE" ]] || fail "--plan-file is required"
[[ -f "$PLAN_FILE" ]] || fail "plan file not found: $PLAN_FILE"

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required to read an action plan"
fi
if ! command -v git >/dev/null 2>&1; then
  fail "git is required"
fi

# Parse plan → ordered units on stdout. Fields are ASCII Unit Separator (U+001F)
# delimited so empty ref_name / expected_oid stay intact under Bash 3.2 `read`
# (tab is IFS whitespace and collapses consecutive delimiters).
# Columns: phase, operation, canonical, ref_name, expected_oid, kind, target, remote, class
# ref_name is the local branch (or empty for prune-only worktree ops). remote and class are set
# only for delete-remote-branches, whose branch, tip and class come from the action's
# remote_branches[] row once it is bound to its audit finding.
# expected_oid may be empty when the plan evidence lacked a headRefOid (fail-closed later).
PLAN_TSV="$(
  PLAN_FILE_PATH="$PLAN_FILE" python3 - <<'PY'
import json, os, re, subprocess, sys

path = os.environ["PLAN_FILE_PATH"]
try:
    with open(path, encoding="utf-8") as f:
        plan = json.load(f)
except (OSError, json.JSONDecodeError) as e:
    print(f"Error: invalid action plan JSON: {e}", file=sys.stderr)
    sys.exit(2)
if not isinstance(plan, dict) or plan.get("schema_version") != 1:
    print("Error: action plan schema_version must be 1", file=sys.stderr)
    sys.exit(2)
# Accept only audit-produced plan artifacts (not hand-built action lists).
if plan.get("generated_by") != "repo-fleet-hygiene/audit":
    print(
        "Error: action plan must set generated_by to repo-fleet-hygiene/audit",
        file=sys.stderr,
    )
    sys.exit(2)
if plan.get("mode") != "read-only":
    print("Error: action plan mode must be read-only", file=sys.stderr)
    sys.exit(2)
actions = plan.get("actions")
if not isinstance(actions, list):
    print("Error: action plan missing actions list", file=sys.stderr)
    sys.exit(2)

BRANCH_KINDS = {"merged-local-branch"}
WORKTREE_KINDS = {
    "merged-worktree",
    "prunable-worktree",
    "missing-worktree",
    "reclaimable-worktree",
}
REMOTE_KINDS = {"unmerged-remote-branch"}
# merged-remote-branch is indexed so a forged delete-remote-branches action naming one is
# rejected on kind; no operation allows it.
INDEXED_KINDS = BRANCH_KINDS | WORKTREE_KINDS | REMOTE_KINDS | {"merged-remote-branch"}
CLASSES = {"never-pr", "closed-unmerged"}
full_oid_re = re.compile(r"[0-9a-f]{40}([0-9a-f]{24})?")
remote_name_re = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
oid_re = re.compile(r"headRefOid[ \t]+([0-9a-fA-F]{7,40})")
# Map (canonical, target) -> first actionable finding kind, oid and evidence.
finding_index = {}
audited_canonicals = set()
for repo in plan.get("repositories") or []:
    if not isinstance(repo, dict):
        continue
    canonical = str(repo.get("canonical") or "")
    if repo.get("audited") is True and canonical:
        audited_canonicals.add(canonical)
    for block in repo.get("targets") or []:
        if not isinstance(block, dict):
            continue
        target = str(block.get("target") or "")
        for finding in block.get("findings") or []:
            if not isinstance(finding, dict):
                continue
            kind = str(finding.get("kind") or "")
            if kind not in INDEXED_KINDS:
                continue
            evidence = str(finding.get("evidence") or "")
            m = oid_re.search(evidence)
            oid = m.group(1).lower() if m else ""
            key = (canonical, target)
            if key not in finding_index:
                finding_index[key] = (kind, oid, evidence)
            elif not finding_index[key][1] and oid:
                finding_index[key] = (kind, oid, evidence)

def phase(op: str) -> int:
    if op == "delete-merged-local-branches":
        return 1
    if op == "cleanup-worktrees":
        return 2
    if op == "delete-remote-branches":
        return 3
    return 9

def split_target(target: str) -> str:
    # Targets are "canonical :: branch" or a worktree path. Prefer the branch form.
    sep = " :: "
    if sep in target:
        return target.split(sep, 1)[1].strip()
    return ""

def clean(s: str) -> str:
    # Keep Unit Separator out of fields; flatten other control whitespace.
    return (
        s.replace("\x1f", " ")
        .replace("\t", " ")
        .replace("\n", " ")
        .replace("\r", "")
    )

FS = "\x1f"
ordered = sorted(
    enumerate(actions),
    key=lambda it: (
        phase(str(it[1].get("operation", "")) if isinstance(it[1], dict) else ""),
        str(it[1].get("canonical", "")) if isinstance(it[1], dict) else "",
        it[0],
    ),
)

for _idx, action in ordered:
    if not isinstance(action, dict):
        continue
    op = str(action.get("operation") or "")
    canonical = str(action.get("canonical") or "")
    if not canonical or canonical not in audited_canonicals:
        print(
            f"Error: action canonical is not an audited repository in the plan: {canonical or '(empty)'}",
            file=sys.stderr,
        )
        sys.exit(2)
    if op == "delete-merged-local-branches":
        allowed_kinds = BRANCH_KINDS
    elif op == "cleanup-worktrees":
        allowed_kinds = WORKTREE_KINDS
    elif op == "delete-remote-branches":
        allowed_kinds = REMOTE_KINDS
    else:
        print(f"Error: unsupported action operation: {op or '(empty)'}", file=sys.stderr)
        sys.exit(2)
    targets = action.get("targets") or []
    if not isinstance(targets, list) or not targets:
        print("Error: action missing targets list", file=sys.stderr)
        sys.exit(2)
    remote_rows = {}
    for rb in action.get("remote_branches") or []:
        if isinstance(rb, dict):
            remote_rows.setdefault(str(rb.get("target") or ""), []).append(rb)
    for target in targets:
        target_s = str(target)
        key = (canonical, target_s)
        if key not in finding_index:
            print(
                "Error: action target has no matching actionable audit finding: "
                f"{target_s}",
                file=sys.stderr,
            )
            sys.exit(2)
        kind, oid, evidence = finding_index[key]
        if kind not in allowed_kinds:
            print(
                f"Error: finding kind {kind} is not valid for operation {op}",
                file=sys.stderr,
            )
            sys.exit(2)
        remote, rclass = "", ""
        if op == "delete-remote-branches":
            rows = remote_rows.get(target_s, [])
            if len(rows) != 1:
                print(
                    "Error: remote branch target needs exactly one remote_branches row: "
                    f"{target_s}",
                    file=sys.stderr,
                )
                sys.exit(2)
            rb = rows[0]
            ref_name = str(rb.get("branch") or "")
            remote = str(rb.get("remote") or "")
            rclass = str(rb.get("class") or "")
            oid = str(rb.get("expected_oid") or "")
            problem = ""
            if str(rb.get("canonical") or "") != canonical:
                problem = "canonical does not match its action"
            elif not remote_name_re.fullmatch(remote):
                problem = "remote is not a plain remote name"
            elif not ref_name or target_s != f"{canonical} :: {remote}/{ref_name}":
                problem = "target is not canonical :: remote/branch"
            elif (
                subprocess.run(
                    ["git", "check-ref-format", f"refs/heads/{ref_name}"],
                    capture_output=True,
                ).returncode
                != 0
            ):
                problem = "branch is not a valid ref name"
            elif rclass not in CLASSES:
                problem = "class is not never-pr or closed-unmerged"
            elif not full_oid_re.fullmatch(oid):
                problem = "expected_oid is not a full lowercase object id"
            elif f"refs/heads/{ref_name} at {oid}" not in evidence:
                problem = "expected_oid does not match the audit finding evidence"
            if problem:
                print(
                    f"Error: remote branch row for {target_s} rejected: {problem}",
                    file=sys.stderr,
                )
                sys.exit(2)
        else:
            ref_name = split_target(target_s)
        print(
            FS.join(
                [
                    str(phase(op)),
                    clean(op),
                    clean(canonical),
                    clean(ref_name),
                    clean(oid),
                    clean(kind),
                    clean(target_s),
                    clean(remote),
                    clean(rclass),
                ]
            )
        )
PY
)" || exit 2

# Bash 3.2-compatible collection (no mapfile).
UNITS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  UNITS+=("$line")
done <<<"$PLAN_TSV"

is_tty_stdin() {
  [[ -t 0 ]]
}

git_probe() {
  # Read-only git with lazy-fetch and optional locks disabled.
  GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 \
    git -c protocol.file.allow=always "$@"
}

git_mutate() {
  # The mutating counterpart to git_probe. It shares the prompt and optional-lock
  # suppression but deliberately not the probe's GIT_NO_LAZY_FETCH or
  # protocol.file.allow: those exist to keep a read-only probe from reaching the
  # network or a file remote, and a local delete/prune has no business doing either. The
  # remote-branch push and its tip fetch do reach the remote; they run only under
  # --remote-branches and add nothing to what the operator's own git config allows.
  GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 git "$@"
}

default_branch_of() {
  local canonical=$1
  local sym
  sym="$(git_probe -C "$canonical" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ "$sym" == refs/remotes/origin/* ]]; then
    printf '%s\n' "${sym#refs/remotes/origin/}"
    return 0
  fi
  if git_probe -C "$canonical" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    printf 'main\n'
    return 0
  fi
  if git_probe -C "$canonical" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    printf 'master\n'
    return 0
  fi
  printf '\n'
}

current_branch_of() {
  local canonical=$1
  git_probe -C "$canonical" branch --show-current 2>/dev/null || true
}

branch_tip() {
  local canonical=$1 branch=$2
  git_probe -C "$canonical" rev-parse --verify "refs/heads/${branch}" 2>/dev/null || true
}

worktree_path_for_branch() {
  local canonical=$1 branch=$2
  local line path="" cur_path=""
  while IFS= read -r line; do
    case "$line" in
    worktree\ *)
      cur_path="${line#worktree }"
      ;;
    branch\ refs/heads/*)
      if [[ "${line#branch refs/heads/}" == "$branch" ]]; then
        path=$cur_path
      fi
      ;;
    "")
      cur_path=""
      ;;
    *) ;;
    esac
  done < <(git_probe -C "$canonical" worktree list --porcelain 2>/dev/null || true)
  printf '%s\n' "$path"
}

worktree_locked() {
  local canonical=$1 wt_path=$2
  local line cur_path="" locked=0
  while IFS= read -r line; do
    case "$line" in
    worktree\ *)
      cur_path="${line#worktree }"
      locked=0
      ;;
    locked*)
      if [[ "$cur_path" == "$wt_path" ]]; then
        locked=1
      fi
      ;;
    "")
      if [[ "$cur_path" == "$wt_path" && "$locked" -eq 1 ]]; then
        return 0
      fi
      cur_path=""
      locked=0
      ;;
    *) ;;
    esac
  done < <(git_probe -C "$canonical" worktree list --porcelain 2>/dev/null || true)
  # Final record may lack trailing blank line.
  [[ "$cur_path" == "$wt_path" && "$locked" -eq 1 ]]
}

worktree_head() {
  local wt_path=$1
  git_probe -C "$wt_path" rev-parse HEAD 2>/dev/null || true
}

worktree_is_unsafe_to_remove() {
  # Fail-closed local probe without a sibling-plugin dependency.
  # Dirty or unreadable porcelain always blocks removal.
  # Unpushed commits (HEAD --not --remotes) also block when remotes exist.
  # When the repository has no remotes at all, --not --remotes would treat every
  # commit as unpushed and false-positive; in that case OID match against the
  # plan's merged headRefOid is the refresh proof and porcelain is the gate.
  local wt_path=$1
  local dirty unpushed remotes
  dirty="$(git_probe -C "$wt_path" status --porcelain 2>/dev/null || echo FAILED)"
  [[ -z "$dirty" ]] || return 0
  remotes="$(git_probe -C "$wt_path" remote 2>/dev/null || true)"
  if [[ -n "$remotes" ]]; then
    unpushed="$(git_probe -C "$wt_path" log --oneline HEAD --not --remotes 2>/dev/null | head -n 1 || echo FAILED)"
    [[ -z "$unpushed" ]] || return 0
  fi
  return 1
}

oids_match() {
  local a=$1 b=$2
  [[ -n "$a" && -n "$b" ]] || return 1
  # Case-insensitive equality, or prefix match when one side is an abbreviated OID.
  # tr (not ${var,,}) keeps this Bash 3.2-safe on stock macOS.
  local al=${#a} bl=${#b}
  a="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
  b="$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')"
  if [[ "$a" == "$b" ]]; then
    return 0
  fi
  if [[ "$al" -lt "$bl" && "$b" == "$a"* ]]; then
    return 0
  fi
  if [[ "$bl" -lt "$al" && "$a" == "$b"* ]]; then
    return 0
  fi
  return 1
}

# Decision records (parallel arrays) filled by refresh pass.
D_PHASE=()
D_OP=()
D_CANONICAL=()
D_REF=()
D_KIND=()
D_TARGET=()
D_EXPECTED=()
D_ACTUAL=()
D_ACTION=() # delete-branch | remove-worktree-then-branch | prune-worktrees | delete-remote-branch | skip
D_REASON=()
D_WT_PATH=()
D_REMOTE=()
D_CLASS=()

append_decision() {
  D_REMOTE+=("${12:-}")
  D_CLASS+=("${13:-}")
  D_PHASE+=("$1")
  D_OP+=("$2")
  D_CANONICAL+=("$3")
  D_REF+=("$4")
  D_KIND+=("$5")
  D_TARGET+=("$6")
  D_EXPECTED+=("$7")
  D_ACTUAL+=("$8")
  D_ACTION+=("$9")
  D_REASON+=("${10}")
  D_WT_PATH+=("${11}")
}

refresh_branch_delete() {
  local phase=$1 op=$2 canonical=$3 ref=$4 expected=$5 kind=$6 target=$7
  local tip default current wt_path

  if [[ ! -d "$canonical" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "canonical path missing" ""
    return 0
  fi
  if ! git_probe -C "$canonical" rev-parse --git-dir >/dev/null 2>&1; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "not a git repository" ""
    return 0
  fi
  if [[ -z "$ref" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "target has no branch name" ""
    return 0
  fi
  if [[ -z "$expected" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "" "" \
      skip "plan evidence missing headRefOid (fail-closed)" ""
    return 0
  fi

  tip="$(branch_tip "$canonical" "$ref")"
  if [[ -z "$tip" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "branch already absent" ""
    return 0
  fi
  if ! oids_match "$expected" "$tip"; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
      skip "OID drift (plan tip != current tip)" ""
    return 0
  fi

  default="$(default_branch_of "$canonical")"
  current="$(current_branch_of "$canonical")"
  if [[ -n "$default" && "$ref" == "$default" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
      skip "protected default branch" ""
    return 0
  fi
  if [[ -n "$current" && "$ref" == "$current" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
      skip "current branch" ""
    return 0
  fi

  wt_path="$(worktree_path_for_branch "$canonical" "$ref")"
  if [[ -n "$wt_path" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
      skip "worktree-attached (use cleanup-worktrees phase)" "$wt_path"
    return 0
  fi

  append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
    delete-branch "merged local branch tip still matches plan OID" ""
}

refresh_worktree_cleanup() {
  local phase=$1 op=$2 canonical=$3 ref=$4 expected=$5 kind=$6 target=$7
  local tip wt_path head

  if [[ ! -d "$canonical" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "canonical path missing" ""
    return 0
  fi
  if ! git_probe -C "$canonical" rev-parse --git-dir >/dev/null 2>&1; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "not a git repository" ""
    return 0
  fi

  case "$kind" in
  prunable-worktree | missing-worktree)
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      prune-worktrees "prune stale/missing worktree registrations" ""
    return 0
    ;;
  reclaimable-worktree)
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "reclaimable-worktree retired; delegate to source-control:worktree status" ""
    return 0
    ;;
  *) ;;
  esac

  # Default / merged-worktree path.
  if [[ -z "$ref" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "target has no branch name" ""
    return 0
  fi
  if [[ -z "$expected" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "" "" \
      skip "plan evidence missing headRefOid (fail-closed)" ""
    return 0
  fi

  tip="$(branch_tip "$canonical" "$ref")"
  wt_path="$(worktree_path_for_branch "$canonical" "$ref")"
  if [[ -z "$wt_path" ]]; then
    # Worktree already gone; still may need branch delete if tip matches.
    if [[ -n "$tip" ]] && oids_match "$expected" "$tip"; then
      append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
        delete-branch "worktree already gone; branch tip still matches plan OID" ""
    else
      append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
        skip "worktree already absent; branch tip missing or drifted" ""
    fi
    return 0
  fi

  head="$(worktree_head "$wt_path")"
  if [[ -z "$head" ]]; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "worktree HEAD unreadable" "$wt_path"
    return 0
  fi
  if ! oids_match "$expected" "$head"; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$head" \
      skip "OID drift (plan tip != worktree HEAD)" "$wt_path"
    return 0
  fi
  if [[ -n "$tip" ]] && ! oids_match "$expected" "$tip"; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$tip" \
      skip "OID drift (plan tip != branch tip)" "$wt_path"
    return 0
  fi
  if worktree_locked "$canonical" "$wt_path"; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$head" \
      skip "worktree locked" "$wt_path"
    return 0
  fi
  if worktree_is_unsafe_to_remove "$wt_path"; then
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$head" \
      skip "dirty or unpushed worktree (fail-closed)" "$wt_path"
    return 0
  fi

  append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$head" \
    remove-worktree-then-branch "merged worktree HEAD still matches plan OID; tree clean" "$wt_path"
}

# Remote-branch deletion. The gated path runs exactly the argv the plan listing prints.
remote_delete_argv() {
  local canonical=$1 remote=$2 ref=$3 tip=$4
  RD_ARGV=(-C "$canonical" push "$remote" --delete "refs/heads/${ref}"
    "--force-with-lease=refs/heads/${ref}:${tip}")
}

remote_delete_cmdline() {
  remote_delete_argv "$@"
  printf 'git'
  printf ' %q' "${RD_ARGV[@]}"
  printf '\n'
}

refresh_remote_delete() {
  local phase=$1 op=$2 canonical=$3 ref=$4 expected=$5 kind=$6 target=$7 remote=$8 class=$9
  local action=skip reason live="" out sym default="" l_oid l_ref

  if [[ "$REMOTE_BRANCHES" -eq 0 ]]; then
    reason="remote deletion requires --remote-branches"
  elif [[ ! -d "$canonical" ]]; then
    reason="canonical path missing"
  elif ! git_probe -C "$canonical" rev-parse --git-dir >/dev/null 2>&1; then
    reason="not a git repository"
  elif ! git_probe -C "$canonical" remote get-url "$remote" >/dev/null 2>&1; then
    reason="remote not configured"
  elif ! out="$(git_probe -C "$canonical" ls-remote --heads "$remote" "refs/heads/${ref}" 2>/dev/null)"; then
    reason="ls-remote failed (fail-closed)"
  else
    while IFS=$'\t' read -r l_oid l_ref; do
      if [[ "$l_ref" == "refs/heads/${ref}" ]]; then live=$l_oid; fi
    done <<<"$out"
    sym="$(git_probe -C "$canonical" ls-remote --symref "$remote" HEAD 2>/dev/null || true)"
    while IFS=$'\t' read -r l_oid l_ref; do
      if [[ "$l_oid" == "ref: refs/heads/"* && "$l_ref" == "HEAD" ]]; then
        default=${l_oid#ref: refs/heads/}
      fi
    done <<<"$sym"
    if [[ -z "$live" ]]; then
      reason="remote head already gone"
    elif [[ -z "$default" ]]; then
      reason="remote default branch unknown (fail-closed)"
    elif [[ "$ref" == "$default" ]]; then
      reason="protected default branch"
    elif [[ "$live" != "$expected" ]]; then
      reason="OID drift (plan tip != live remote tip)"
    else
      action=delete-remote-branch
      reason="remote head still at plan OID"
    fi
  fi
  append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "$live" \
    "$action" "$reason" "" "$remote" "$class"
}

# Appends one ledger line before a push and leaves it in LEDGER_LINE. A failed write aborts the
# branch: no restore record, no delete.
record_tip() {
  local canonical=$1 remote=$2 ref=$3 class=$4 tip=$5 restore
  restore="$(printf 'git -C %q push %q %q' "$canonical" "$remote" "${tip}:refs/heads/${ref}")"
  LEDGER_LINE="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$canonical" "$remote" "$ref" "$class" "$tip" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$restore")"
  printf '%s\n' "$LEDGER_LINE" >>"$LEDGER"
}

# --- Evidence refresh -------------------------------------------------------
# Unit Separator (not tab): empty ref/expected fields must survive read.
for line in "${UNITS[@]:-}"; do
  [[ -n "$line" ]] || continue
  IFS=$'\037' read -r phase op canonical ref expected kind target remote rclass _ <<<"$line"
  case "$op" in
  delete-remote-branches)
    refresh_remote_delete "$phase" "$op" "$canonical" "$ref" "$expected" "$kind" "$target" \
      "$remote" "$rclass"
    ;;
  delete-merged-local-branches)
    refresh_branch_delete "$phase" "$op" "$canonical" "$ref" "$expected" "$kind" "$target"
    ;;
  cleanup-worktrees)
    refresh_worktree_cleanup "$phase" "$op" "$canonical" "$ref" "$expected" "$kind" "$target"
    ;;
  *)
    append_decision "$phase" "$op" "$canonical" "$ref" "$kind" "$target" "$expected" "" \
      skip "unknown operation" ""
    ;;
  esac
done

mutable=0
remote_mutable=0
skipped=0
for ((i = 0; i < ${#D_ACTION[@]}; i++)); do
  case "${D_ACTION[$i]}" in
  delete-branch | remove-worktree-then-branch | prune-worktrees) mutable=$((mutable + 1)) ;;
  delete-remote-branch) remote_mutable=$((remote_mutable + 1)) ;;
  *) skipped=$((skipped + 1)) ;;
  esac
done
LEDGER="${PLAN_FILE}.tip-ledger"

printf 'Repo Fleet Hygiene — apply-plan\n'
if [[ "$DO_APPLY" -eq 1 ]]; then
  printf 'Mode: apply (mutations gated)\n'
else
  printf 'Mode: dry-run (no mutations)\n'
fi
printf 'Confirmation model: ONE gate for the local plan (not per repository)\n'
if [[ "$REMOTE_BRANCHES" -eq 1 ]]; then
  printf 'Remote branches: one prompt per branch; --yes never answers it; tips recorded in %s\n' "$LEDGER"
else
  printf 'Remote branches: delete-remote-branches actions are skipped without --remote-branches\n'
fi
printf 'Order rule: delete-merged-local-branches, cleanup-worktrees, delete-remote-branches; re-derive OIDs at execution\n'
print_field Plan "$PLAN_FILE"
print_field Units "${#D_ACTION[@]}"
print_field Mutable "$mutable"
print_field 'Remote deletions (per-branch gate)' "$remote_mutable"
print_field Skipped "$skipped"
printf '\n'

if [[ ${#D_ACTION[@]} -eq 0 ]]; then
  printf 'Actions: none\n'
else
  printf 'Actions: %s\n' "${#D_ACTION[@]}"
  for ((i = 0; i < ${#D_ACTION[@]}; i++)); do
    step=$((i + 1))
    printf '%s. [%s] %s\n' "$step" "${D_ACTION[$i]}" "${D_OP[$i]}"
    printf '   repository: %s\n' "${D_CANONICAL[$i]}"
    printf '   target: %s\n' "${D_TARGET[$i]}"
    [[ -n "${D_REF[$i]}" ]] && printf '   branch: %s\n' "${D_REF[$i]}"
    [[ -n "${D_KIND[$i]}" ]] && printf '   kind: %s\n' "${D_KIND[$i]}"
    [[ -n "${D_EXPECTED[$i]}" ]] && printf '   plan_oid: %s\n' "${D_EXPECTED[$i]}"
    [[ -n "${D_ACTUAL[$i]}" ]] && printf '   live_oid: %s\n' "${D_ACTUAL[$i]}"
    [[ -n "${D_WT_PATH[$i]}" ]] && printf '   worktree: %s\n' "${D_WT_PATH[$i]}"
    [[ -n "${D_REMOTE[$i]}" ]] && printf '   remote: %s\n' "${D_REMOTE[$i]}"
    [[ -n "${D_CLASS[$i]}" ]] && printf '   class: %s\n' "${D_CLASS[$i]}"
    if [[ "${D_ACTION[$i]}" == "delete-remote-branch" ]]; then
      printf '   command: %s\n' "$(remote_delete_cmdline "${D_CANONICAL[$i]}" "${D_REMOTE[$i]}" "${D_REF[$i]}" "${D_ACTUAL[$i]}")"
    fi
    printf '   reason: %s\n' "${D_REASON[$i]}"
  done
fi

if [[ "$DO_APPLY" -eq 0 ]]; then
  printf '\nDry-run complete. Re-run with --apply (interactive) or --apply --yes (non-interactive) to mutate.\n'
  exit 0
fi

if [[ "$mutable" -eq 0 && "$remote_mutable" -eq 0 ]]; then
  printf '\nNothing mutable after evidence refresh; no confirmation required.\n'
  exit 0
fi

# The per-branch prompt cannot be answered without a terminal, and --yes never answers it, so a
# non-interactive run with remote rows deletes nothing at all (local rows included).
if [[ "$remote_mutable" -gt 0 ]] && ! is_tty_stdin; then
  printf '\nRemote branch deletion needs an interactive per-branch confirmation; --yes does not answer it.\n' >&2
  printf 'Non-interactive session: mutate nothing. Rows above are the branches that would be prompted.\n' >&2
  exit 3
fi

# --- One batch-wide confirmation gate (local actions) ------------------------
if [[ "$mutable" -eq 0 ]]; then
  :
elif [[ "$YES" -eq 0 ]]; then
  if ! is_tty_stdin; then
    printf '\nConfirmation required: non-interactive session without --yes; mutate nothing.\n' >&2
    printf 'Re-run with --apply --yes after reviewing the dry-run plan.\n' >&2
    exit 3
  fi
  printf '\nApply %s mutable action(s) across this fleet plan? [y/N] ' "$mutable" >&2
  confirm=""
  IFS= read -r confirm || true
  case "$confirm" in
  y | Y | yes | YES) ;;
  *)
    printf 'Aborted: confirmation declined; mutate nothing.\n'
    exit 3
    ;;
  esac
else
  printf '\nConfirmation: --yes supplied; proceeding with %s mutable action(s).\n' "$mutable"
fi

# --- Execute in decision order (already plan-ordered) -----------------------
failures=0
applied=0
for ((i = 0; i < ${#D_ACTION[@]}; i++)); do
  action="${D_ACTION[$i]}"
  canonical="${D_CANONICAL[$i]}"
  ref="${D_REF[$i]}"
  expected="${D_EXPECTED[$i]}"
  wt_path="${D_WT_PATH[$i]}"
  case "$action" in
  skip)
    printf 'SKIP: %s (%s)\n' "${D_TARGET[$i]}" "${D_REASON[$i]}"
    ;;
  prune-worktrees)
    # Re-check nothing OID-sensitive; prune is metadata-only.
    if git_mutate -C "$canonical" worktree prune; then
      printf 'APPLIED: worktree prune in %s\n' "$canonical"
      applied=$((applied + 1))
    else
      printf 'FAIL: worktree prune in %s\n' "$canonical" >&2
      failures=$((failures + 1))
    fi
    ;;
  delete-branch)
    tip="$(branch_tip "$canonical" "$ref")"
    if [[ -z "$tip" ]]; then
      printf 'SKIP: %s (branch disappeared before delete)\n' "$ref"
      continue
    fi
    if ! oids_match "$expected" "$tip"; then
      printf 'SKIP: %s (OID drift at execution)\n' "$ref"
      continue
    fi
    wt_now="$(worktree_path_for_branch "$canonical" "$ref")"
    if [[ -n "$wt_now" ]]; then
      printf 'SKIP: %s (became worktree-attached before delete)\n' "$ref"
      continue
    fi
    if git_mutate -C "$canonical" branch -D "$ref"; then
      printf 'APPLIED: deleted branch %s in %s (was %s)\n' "$ref" "$canonical" "$tip"
      applied=$((applied + 1))
    else
      printf 'FAIL: delete branch %s in %s\n' "$ref" "$canonical" >&2
      failures=$((failures + 1))
    fi
    ;;
  remove-worktree-then-branch)
    if [[ -z "$wt_path" || ! -d "$wt_path" ]]; then
      # Fall back to branch-only if worktree vanished but tip still matches.
      tip="$(branch_tip "$canonical" "$ref")"
      if [[ -n "$tip" ]] && oids_match "$expected" "$tip"; then
        if git_mutate -C "$canonical" branch -D "$ref"; then
          printf 'APPLIED: deleted branch %s in %s (worktree already gone)\n' "$ref" "$canonical"
          applied=$((applied + 1))
        else
          printf 'FAIL: delete branch %s in %s\n' "$ref" "$canonical" >&2
          failures=$((failures + 1))
        fi
      else
        printf 'SKIP: %s (worktree gone; branch tip missing or drifted)\n' "$ref"
      fi
      continue
    fi
    head="$(worktree_head "$wt_path")"
    if ! oids_match "$expected" "$head"; then
      printf 'SKIP: %s (worktree HEAD drifted at execution)\n' "$ref"
      continue
    fi
    if worktree_locked "$canonical" "$wt_path"; then
      printf 'SKIP: %s (locked at execution)\n' "$ref"
      continue
    fi
    if worktree_is_unsafe_to_remove "$wt_path"; then
      printf 'SKIP: %s (dirty or unpushed at execution)\n' "$ref"
      continue
    fi
    if ! git_mutate -C "$canonical" worktree remove "$wt_path"; then
      printf 'FAIL: worktree remove %s\n' "$wt_path" >&2
      failures=$((failures + 1))
      continue
    fi
    printf 'APPLIED: removed worktree %s\n' "$wt_path"
    tip="$(branch_tip "$canonical" "$ref")"
    if [[ -n "$tip" ]]; then
      if oids_match "$expected" "$tip"; then
        if git_mutate -C "$canonical" branch -D "$ref"; then
          printf 'APPLIED: deleted branch %s in %s after worktree remove\n' "$ref" "$canonical"
          applied=$((applied + 1))
        else
          printf 'FAIL: delete branch %s after worktree remove in %s\n' "$ref" "$canonical" >&2
          failures=$((failures + 1))
        fi
      else
        printf 'SKIP: %s (branch tip drifted after worktree remove)\n' "$ref"
      fi
    else
      applied=$((applied + 1))
    fi
    ;;
  delete-remote-branch)
    remote="${D_REMOTE[$i]}"
    class="${D_CLASS[$i]}"
    tip="${D_ACTUAL[$i]}"
    remote_delete_argv "$canonical" "$remote" "$ref" "$tip"
    # Per-branch gate: --yes is not consulted; anything but an explicit yes skips the branch.
    printf '\nDelete remote branch?\n  repo:   %s\n  remote: %s\n  branch: %s\n  class:  %s\n  tip:    %s\n  command: %s\n[y/N] ' \
      "$canonical" "$remote" "$ref" "$class" "$tip" "$(remote_delete_cmdline "$canonical" "$remote" "$ref" "$tip")" >&2
    confirm=""
    IFS= read -r confirm || true
    case "$confirm" in
    y | Y | yes | YES) ;;
    *)
      printf 'SKIP: %s/%s in %s (remote deletion not confirmed)\n' "$remote" "$ref" "$canonical"
      continue
      ;;
    esac
    # The restore command pushes the tip by SHA, so the object must exist locally.
    if ! git_probe -C "$canonical" cat-file -e "${tip}^{commit}" 2>/dev/null; then
      git_mutate -C "$canonical" fetch --quiet --no-tags "$remote" "refs/heads/${ref}" 2>/dev/null || true
    fi
    if ! git_probe -C "$canonical" cat-file -e "${tip}^{commit}" 2>/dev/null; then
      printf 'SKIP: %s/%s in %s (tip %s not available locally; the restore command would not work)\n' \
        "$remote" "$ref" "$canonical" "$tip"
      continue
    fi
    if ! record_tip "$canonical" "$remote" "$ref" "$class" "$tip"; then
      printf 'FAIL: cannot append to tip ledger %s; %s/%s not deleted\n' "$LEDGER" "$remote" "$ref" >&2
      failures=$((failures + 1))
      continue
    fi
    printf 'LEDGER: %s\n' "$LEDGER_LINE"
    if git_mutate "${RD_ARGV[@]}"; then
      printf 'APPLIED: deleted remote branch %s/%s in %s (was %s)\n' "$remote" "$ref" "$canonical" "$tip"
      applied=$((applied + 1))
    else
      printf 'FAIL: remote delete %s/%s in %s (lease or push rejected; ledger line kept)\n' \
        "$remote" "$ref" "$canonical" >&2
      failures=$((failures + 1))
    fi
    ;;
  *)
    printf 'SKIP: unknown action %s\n' "$action"
    ;;
  esac
done

printf '\nApply summary: applied=%s failed=%s skipped_or_unchanged=%s\n' \
  "$applied" "$failures" "$((${#D_ACTION[@]} - applied - failures))"

if [[ "$failures" -gt 0 ]]; then
  exit 4
fi
exit 0
