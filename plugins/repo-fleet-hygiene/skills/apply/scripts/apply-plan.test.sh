#!/usr/bin/env bash
# apply-plan.test.sh — dry-run, confirmation stop, OID drift skip, ordering.
# shellcheck disable=SC2310 # pass/fail helpers return status in if/||; every false path is handled
# shellcheck disable=SC2015 # `cond && pass || fail`: pass never fails, so fail runs only when cond is false

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/apply-plan.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/apply-plan-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fails=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  fails=1
}

assert_contains() {
  local name=$1 needle=$2 file=$3
  if grep -Fq -- "$needle" "$file"; then
    pass "$name"
  else
    fail "$name (missing: $needle)"
    printf '%s\n' '--- output ---' >&2
    cat "$file" >&2 || true
  fi
}

assert_not_contains() {
  local name=$1 needle=$2 file=$3
  if grep -Fq -- "$needle" "$file"; then
    fail "$name (unexpected: $needle)"
  else
    pass "$name"
  fi
}

# Whether a branch survived a run is the mutation evidence most cases assert on.
assert_branch_kept() {
  local name=$1 repo=$2 branch=$3
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_branch_deleted() {
  local name=$1 repo=$2 branch=$3
  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    fail "$name"
  else
    pass "$name"
  fi
}

# --- Fixture helpers --------------------------------------------------------
make_repo() {
  local path=$1
  mkdir -p "$path"
  git -C "$path" init -q -b main
  git -C "$path" config user.email "test@example.com"
  git -C "$path" config user.name "Test"
  printf 'seed\n' >"$path/README"
  git -C "$path" add README
  git -C "$path" commit -q -m seed
}

add_merged_branch() {
  # Create branch at tip OID; return OID on stdout.
  local repo=$1 branch=$2
  git -C "$repo" checkout -q -b "$branch"
  printf '%s\n' "$branch" >"$repo/feat.txt"
  git -C "$repo" add feat.txt
  git -C "$repo" commit -q -m "$branch"
  local oid
  oid="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" checkout -q main
  printf '%s\n' "$oid"
}

write_plan() {
  # Usage: write_plan PATH <<'EOF' ... JSON ... EOF
  # Copy stdin to a temp file first so the python here-doc does not consume the JSON.
  local out=$1
  local raw
  raw="$(mktemp "$TMP/plan-raw.XXXXXX")"
  cat >"$raw"
  python3 - "$out" "$raw" <<'PY'
import json, sys
out, raw = sys.argv[1], sys.argv[2]
with open(raw, encoding="utf-8") as f:
    plan = json.load(f)
with open(out, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2)
    f.write("\n")
PY
}

# Two repos with merged-local-branch candidates (ordering: branches before worktrees).
REPO_A="$TMP/repo-a"
REPO_B="$TMP/repo-b"
make_repo "$REPO_A"
make_repo "$REPO_B"
OID_A="$(add_merged_branch "$REPO_A" "feat/alpha")"
OID_B="$(add_merged_branch "$REPO_B" "feat/beta")"

# Worktree on repo-a for merged-worktree path (separate branch).
OID_WT="$(
  git -C "$REPO_A" checkout -q -b feat/wt
  printf 'wt\n' >"$REPO_A/wt.txt"
  git -C "$REPO_A" add wt.txt
  git -C "$REPO_A" commit -q -m wt
  git -C "$REPO_A" rev-parse HEAD
  git -C "$REPO_A" checkout -q main
)"
WT_PATH="$TMP/wt-feat"
git -C "$REPO_A" worktree add -q "$WT_PATH" feat/wt

PLAN="$TMP/plan.json"
write_plan "$PLAN" <<EOF
{
  "schema_version": 1,
  "mode": "read-only",
  "generated_by": "repo-fleet-hygiene/audit",
  "execution_order_rule": "delete-merged-local-branches before cleanup-worktrees; re-derive OIDs at execution time",
  "confirmation_model": "one-gate-for-entire-plan",
  "summary": {"repositories_audited": 2, "high": 3, "medium": 0, "low": 0, "unknown": 0, "acknowledged": 0, "fleet_verdict": "test"},
  "repositories": [
    {
      "discovered": "$REPO_A",
      "canonical": "$REPO_A",
      "remote": "github.com/acme/a",
      "verdict": "3 candidates",
      "kind_counts_text": "merged-local-branch=1, merged-worktree=1",
      "audited": true,
      "targets": [
        {
          "target": "$REPO_A :: feat/alpha",
          "findings": [
            {
              "kind": "merged-local-branch",
              "confidence": "HIGH",
              "evidence": "GitHub PR #1 MERGED; headRefOid $OID_A equals local tip (https://example.test/1)",
              "disposition": "Candidate",
              "handoff": "n/a"
            }
          ]
        },
        {
          "target": "$REPO_A :: feat/wt",
          "findings": [
            {
              "kind": "merged-worktree",
              "confidence": "HIGH",
              "evidence": "GitHub PR #2 MERGED; headRefOid $OID_WT equals local tip; branch is worktree-attached",
              "disposition": "Candidate",
              "handoff": "n/a"
            }
          ]
        }
      ]
    },
    {
      "discovered": "$REPO_B",
      "canonical": "$REPO_B",
      "remote": "github.com/acme/b",
      "verdict": "1 candidates",
      "kind_counts_text": "merged-local-branch=1",
      "audited": true,
      "targets": [
        {
          "target": "$REPO_B :: feat/beta",
          "findings": [
            {
              "kind": "merged-local-branch",
              "confidence": "HIGH",
              "evidence": "GitHub PR #3 MERGED; headRefOid $OID_B equals local tip (https://example.test/3)",
              "disposition": "Candidate",
              "handoff": "n/a"
            }
          ]
        }
      ]
    }
  ],
  "actions": [
    {
      "order": 1,
      "phase": 1,
      "skill": "/repo-hygiene:clean git",
      "canonical": "$REPO_A",
      "operation": "delete-merged-local-branches",
      "kinds": ["merged-local-branch"],
      "targets": ["$REPO_A :: feat/alpha"],
      "note": "Re-derive OIDs at execution time; do not trust plan tips."
    },
    {
      "order": 2,
      "phase": 1,
      "skill": "/repo-hygiene:clean git",
      "canonical": "$REPO_B",
      "operation": "delete-merged-local-branches",
      "kinds": ["merged-local-branch"],
      "targets": ["$REPO_B :: feat/beta"],
      "note": "Re-derive OIDs at execution time; do not trust plan tips."
    },
    {
      "order": 3,
      "phase": 2,
      "skill": "/source-control:worktree cleanup --dry-run",
      "canonical": "$REPO_A",
      "operation": "cleanup-worktrees",
      "kinds": ["merged-worktree"],
      "targets": ["$REPO_A :: feat/wt"],
      "note": "Re-derive OIDs at execution time; do not trust plan tips."
    }
  ]
}
EOF

# --- 1) Dry-run: preview, no mutations --------------------------------------
dry_out="$TMP/dry.txt"
bash "$SCRIPT" --plan-file "$PLAN" >"$dry_out" 2>&1
assert_contains "dry-run mode banner" "Mode: dry-run (no mutations)" "$dry_out"
assert_contains "dry-run lists mutable units" "Mutable: 3" "$dry_out"
assert_contains "dry-run names delete-branch" "[delete-branch]" "$dry_out"
assert_contains "dry-run names worktree remove" "[remove-worktree-then-branch]" "$dry_out"
# Ordering: first two are branch deletes (alpha/beta), then worktree.
python3 - "$dry_out" <<'PY' || fails=1
import sys
text = open(sys.argv[1], encoding="utf-8").read().splitlines()
actions = [ln for ln in text if ln[:1].isdigit() and ". [" in ln]
if len(actions) < 3:
    print("FAIL: ordering — fewer than 3 action lines", file=sys.stderr)
    sys.exit(1)
if "delete-branch" not in actions[0] or "delete-merged-local-branches" not in actions[0]:
    print("FAIL: ordering — first action should be branch delete", actions[0], file=sys.stderr)
    sys.exit(1)
if "delete-branch" not in actions[1]:
    print("FAIL: ordering — second action should be branch delete", actions[1], file=sys.stderr)
    sys.exit(1)
if "remove-worktree-then-branch" not in actions[2]:
    print("FAIL: ordering — third action should be worktree remove", actions[2], file=sys.stderr)
    sys.exit(1)
print("PASS: ordering branches before worktrees")
PY
# Branches still exist after dry-run.
if git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/alpha &&
  git -C "$REPO_B" show-ref --verify --quiet refs/heads/feat/beta &&
  [[ -d "$WT_PATH" ]]; then
  pass "dry-run mutated nothing"
else
  fail "dry-run mutated nothing"
fi

# --- 2) Confirmation stop: --apply without --yes on non-tty -----------------
stop_out="$TMP/stop.txt"
rc=0
bash "$SCRIPT" --plan-file "$PLAN" --apply </dev/null >"$stop_out" 2>&1 || rc=$?
if [[ "$rc" -eq 3 ]] && grep -Fq "non-interactive session without --yes" "$stop_out"; then
  pass "confirmation stop without --yes (exit 3)"
else
  fail "confirmation stop without --yes (rc=$rc)"
  cat "$stop_out" >&2
fi
assert_branch_kept "confirmation stop mutated nothing" "$REPO_A" feat/alpha

# --- 3) OID drift skip ------------------------------------------------------
# Advance feat/alpha so tip != plan OID.
git -C "$REPO_A" checkout -q feat/alpha
printf 'drift\n' >>"$REPO_A/feat.txt"
git -C "$REPO_A" add feat.txt
git -C "$REPO_A" commit -q -m drift
git -C "$REPO_A" checkout -q main

drift_out="$TMP/drift.txt"
bash "$SCRIPT" --plan-file "$PLAN" --apply --yes >"$drift_out" 2>&1
assert_contains "OID drift skipped" "OID drift" "$drift_out"
assert_branch_kept "drifted branch retained" "$REPO_A" feat/alpha
# Non-drifted branch and worktree should still apply.
assert_branch_deleted "non-drifted branch deleted" "$REPO_B" feat/beta
if [[ ! -d "$WT_PATH" ]] && ! git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/wt; then
  pass "matching worktree removed and branch deleted"
else
  fail "matching worktree removed and branch deleted"
  printf 'wt exists=%s branch=%s\n' "$([[ -d $WT_PATH ]] && echo yes || echo no)" \
    "$(git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/wt && echo yes || echo no)" >&2
fi

# --- 4) Confirmation stop on a fresh plan; --yes positive control ------------
# Rebuild a small plan with one remaining branch (feat/alpha still present, drifted —
# use a fresh matching branch).
OID_C="$(add_merged_branch "$REPO_B" "feat/gamma")"
PLAN2="$TMP/plan2.json"
write_plan "$PLAN2" <<EOF
{
  "schema_version": 1,
  "mode": "read-only",
  "generated_by": "repo-fleet-hygiene/audit",
  "execution_order_rule": "delete-merged-local-branches before cleanup-worktrees",
  "confirmation_model": "one-gate-for-entire-plan",
  "summary": {},
  "repositories": [
    {
      "discovered": "$REPO_B",
      "canonical": "$REPO_B",
      "remote": "github.com/acme/b",
      "verdict": "1 candidates",
      "kind_counts_text": "merged-local-branch=1",
      "audited": true,
      "targets": [
        {
          "target": "$REPO_B :: feat/gamma",
          "findings": [
            {
              "kind": "merged-local-branch",
              "confidence": "HIGH",
              "evidence": "GitHub PR #9 MERGED; headRefOid $OID_C equals local tip (https://example.test/9)",
              "disposition": "Candidate",
              "handoff": "n/a"
            }
          ]
        }
      ]
    }
  ],
  "actions": [
    {
      "order": 1,
      "phase": 1,
      "skill": "/repo-hygiene:clean git",
      "canonical": "$REPO_B",
      "operation": "delete-merged-local-branches",
      "kinds": ["merged-local-branch"],
      "targets": ["$REPO_B :: feat/gamma"],
      "note": "re-derive"
    }
  ]
}
EOF

# An interactive "n" decline needs a pty (the script checks -t 0, so piped stdin
# hits the non-interactive stop instead). Re-assert that stop on this fresh plan,
# then a --yes apply as the positive control that the same plan would mutate.

decline_rc=0
bash "$SCRIPT" --plan-file "$PLAN2" --apply </dev/null >/dev/null 2>&1 || decline_rc=$?
[[ "$decline_rc" -eq 3 ]] || fail "plan2 confirmation stop rc=$decline_rc"
assert_branch_kept "confirmation-stop retained feat/gamma" "$REPO_B" feat/gamma

yes_out="$TMP/yes.txt"
bash "$SCRIPT" --plan-file "$PLAN2" --apply --yes >"$yes_out" 2>&1
assert_contains "yes apply deleted gamma" "APPLIED: deleted branch feat/gamma" "$yes_out"
assert_branch_deleted "--yes applied matching branch delete" "$REPO_B" feat/gamma

# --- 5) Usage / schema ------------------------------------------------------
rc=0
bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "missing --plan-file exits 2"
else
  fail "missing --plan-file exits 2"
fi

bad="$TMP/bad.json"
printf '{ "schema_version": 99, "actions": [] }\n' >"$bad"
rc=0
bash "$SCRIPT" --plan-file "$bad" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then
  pass "bad schema exits 2"
else
  fail "bad schema exits 2"
fi

# --- 6) Reject non-audit / unbound action plans (P1 safety) -----------------
fake="$TMP/fake-plan.json"
write_plan "$fake" <<EOF
{
  "schema_version": 1,
  "mode": "read-only",
  "actions": [
    {
      "order": 1,
      "phase": 1,
      "skill": "/repo-hygiene:clean git",
      "canonical": "$REPO_A",
      "operation": "delete-merged-local-branches",
      "kinds": ["merged-local-branch"],
      "targets": ["$REPO_A :: feat/alpha"]
    }
  ]
}
EOF
rc=0
fake_out="$TMP/fake-out.txt"
bash "$SCRIPT" --plan-file "$fake" --apply --yes >"$fake_out" 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -Fq "generated_by" "$fake_out"; then
  pass "rejects plan without generated_by"
else
  fail "rejects plan without generated_by (rc=$rc)"
  cat "$fake_out" >&2
fi

unbound="$TMP/unbound-plan.json"
# Fresh matching tip so a naive apply would otherwise delete.
add_merged_branch "$REPO_A" "feat/unbound" >/dev/null
write_plan "$unbound" <<EOF
{
  "schema_version": 1,
  "mode": "read-only",
  "generated_by": "repo-fleet-hygiene/audit",
  "repositories": [
    {
      "discovered": "$REPO_A",
      "canonical": "$REPO_A",
      "remote": "github.com/acme/a",
      "verdict": "clean",
      "kind_counts_text": "",
      "audited": true,
      "targets": []
    }
  ],
  "actions": [
    {
      "order": 1,
      "phase": 1,
      "skill": "/repo-hygiene:clean git",
      "canonical": "$REPO_A",
      "operation": "delete-merged-local-branches",
      "kinds": ["merged-local-branch"],
      "targets": ["$REPO_A :: feat/unbound"]
    }
  ]
}
EOF
rc=0
unbound_out="$TMP/unbound-out.txt"
bash "$SCRIPT" --plan-file "$unbound" --apply --yes >"$unbound_out" 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -Fq "no matching actionable audit finding" "$unbound_out"; then
  pass "rejects action target without audit finding"
else
  fail "rejects action target without audit finding (rc=$rc)"
  cat "$unbound_out" >&2
fi
assert_branch_kept "unbound plan mutated nothing" "$REPO_A" feat/unbound

# --- 7) Empty TSV fields for prune-only worktree kinds (P2) -----------------
# Register a missing worktree path so prune is meaningful, then plan a
# prunable-worktree action whose ref_name and expected_oid are intentionally empty.
PRUNE_REPO="$TMP/repo-prune"
make_repo "$PRUNE_REPO"
# Create and remove a linked worktree so porcelain may still list stale entries
# after a forced path removal; apply's prune path only needs the kind decode.
WT_STALE="$TMP/wt-stale"
git -C "$PRUNE_REPO" worktree add -q "$WT_STALE" -b feat/stale
rm -rf "$WT_STALE"
PLAN_PRUNE="$TMP/plan-prune.json"
write_plan "$PLAN_PRUNE" <<EOF
{
  "schema_version": 1,
  "mode": "read-only",
  "generated_by": "repo-fleet-hygiene/audit",
  "repositories": [
    {
      "discovered": "$PRUNE_REPO",
      "canonical": "$PRUNE_REPO",
      "remote": "github.com/acme/prune",
      "verdict": "1 candidates",
      "kind_counts_text": "prunable-worktree=1",
      "audited": true,
      "targets": [
        {
          "target": "$WT_STALE",
          "findings": [
            {
              "kind": "prunable-worktree",
              "confidence": "HIGH",
              "evidence": "worktree path missing on disk; registration still present",
              "disposition": "Candidate",
              "handoff": "n/a"
            }
          ]
        }
      ]
    }
  ],
  "actions": [
    {
      "order": 1,
      "phase": 2,
      "skill": "/source-control:worktree cleanup --dry-run",
      "canonical": "$PRUNE_REPO",
      "operation": "cleanup-worktrees",
      "kinds": ["prunable-worktree"],
      "targets": ["$WT_STALE"],
      "note": "ref and oid intentionally empty"
    }
  ]
}
EOF
prune_out="$TMP/prune-out.txt"
bash "$SCRIPT" --plan-file "$PLAN_PRUNE" >"$prune_out" 2>&1
assert_contains "prunable empty fields decode to prune" "[prune-worktrees]" "$prune_out"
assert_contains "prunable kind preserved" "kind: prunable-worktree" "$prune_out"
assert_not_contains "prunable not misread as merged-worktree skip" "target has no branch name" "$prune_out"

# --- 8) delete-remote-branches: gated by --remote-branches, per branch --------
# Fixtures use a local bare repository as the remote; nothing here reaches GitHub. The per-branch
# prompt reads a terminal, so the interactive cases run under a pty driver; without one they SKIP.
HAVE_PTY=0
python3 -c 'import pty' >/dev/null 2>&1 && HAVE_PTY=1
PTY_DRIVER="$TMP/pty-run.py"
cat >"$PTY_DRIVER" <<'PY'
import os, pty, sys

args = sys.argv[1:]
sep = args.index("--")
answers, cmd = args[:sep], args[sep + 1 :]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
out, answered = b"", 0
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
    while out.count(b"[y/N]") > answered:
        reply = answers[answered] if answered < len(answers) else ""
        os.write(fd, reply.encode() + b"\n")
        answered += 1
sys.stdout.buffer.write(out)
_, status = os.waitpid(pid, 0)
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PY

# run_pty OUT ANSWER... -- COMMAND...: answers each "[y/N]" prompt in order, returns the exit code.
run_pty() {
  local out=$1
  shift
  python3 "$PTY_DRIVER" "$@" >"$out" 2>&1
}

skip_no_pty() {
  printf 'SKIP: %s (no pty module)\n' "$1"
}

make_remote_repo() {
  REMOTE_BARE="$TMP/$1-origin.git"
  REMOTE_REPO="$TMP/$1"
  git init -q --bare -b main "$REMOTE_BARE"
  make_repo "$REMOTE_REPO"
  git -C "$REMOTE_REPO" remote add origin "$REMOTE_BARE"
  git -C "$REMOTE_REPO" push -q origin main
}

# Pushes a new branch and drops the local copy, so only the remote head remains. Prints the tip.
add_remote_branch() {
  local repo=$1 branch=$2 oid
  git -C "$repo" checkout -q -b "$branch"
  printf '%s\n' "$branch" >"$repo/remote.txt"
  git -C "$repo" add remote.txt
  git -C "$repo" commit -q -m "$branch"
  oid="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" push -q origin "$branch"
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q -D "$branch"
  printf '%s\n' "$oid"
}

# Advances a remote head from a second clone, the way a concurrent pusher would. Prints the new tip.
move_remote_branch() {
  local bare=$1 branch=$2 clone
  clone="$(mktemp -d "$TMP/mover.XXXXXX")"
  git clone -q "$bare" "$clone"
  git -C "$clone" checkout -q "$branch"
  printf 'moved\n' >>"$clone/remote.txt"
  git -C "$clone" add remote.txt
  git -C "$clone" -c user.email=t@example.com -c user.name=T commit -q -m moved
  git -C "$clone" push -q origin "$branch"
  git -C "$clone" rev-parse HEAD
}

remote_head() {
  git ls-remote --heads "$1" "refs/heads/$2" | cut -f1
}

assert_remote_head() {
  local name=$1 bare=$2 branch=$3 want=$4 got
  got="$(remote_head "$bare" "$branch")"
  if [[ "$got" == "$want" ]]; then
    pass "$name"
  else
    fail "$name (want '${want:-absent}', got '${got:-absent}')"
  fi
}

# write_remote_plan OUT CANONICAL KIND ROW...: one delete-remote-branches action, each ROW being
# branch|class|expected_oid[|evidence_oid[|evidence_class]]. LOCAL_ROW=branch|oid adds a merged-local-branch action.
write_remote_plan() {
  local out=$1 canonical=$2 kind=$3
  shift 3
  python3 - "$out" "$canonical" "$kind" "$@" <<'PY'
import json, os, subprocess, sys

out, canonical, kind, *rows = sys.argv[1:]
remote_key = os.environ.get("REMOTE_KEY") or subprocess.run(
    ["git", "-C", canonical, "remote", "get-url", "origin"],
    check=True, capture_output=True, text=True).stdout.strip()
github_repo = os.environ.get("GITHUB_REPO", "acme/r")
targets, findings, remote_rows = [], [], []
for row in rows:
    parts = row.split("|")
    branch, cls, oid = parts[:3]
    evidence_oid = parts[3] if len(parts) > 3 else oid
    evidence_class = parts[4] if len(parts) > 4 else cls
    target = f"{canonical} :: origin/{branch}"
    targets.append(target)
    findings.append({
        "target": target,
        "findings": [{
            "kind": kind,
            "confidence": "HIGH",
            "evidence": f"class {evidence_class}: no PR; ls-remote confirmed refs/heads/{branch} at {evidence_oid}",
            "disposition": "Candidate",
            "handoff": "n/a",
        }],
    })
    remote_rows.append({
        "target": target, "canonical": canonical, "remote": "origin", "branch": branch,
        "remote_key": remote_key, "github_repo": github_repo,
        "class": cls, "expected_oid": oid, "pr_number": None, "pr_url": None,
    })
actions = []
local = os.environ.get("LOCAL_ROW")
if local:
    branch, oid = local.split("|")
    target = f"{canonical} :: {branch}"
    findings.append({
        "target": target,
        "findings": [{
            "kind": "merged-local-branch", "confidence": "HIGH",
            "evidence": f"GitHub PR #1 MERGED; headRefOid {oid} equals local tip",
            "disposition": "Candidate", "handoff": "n/a",
        }],
    })
    actions.append({
        "order": 1, "phase": 1, "skill": "/repo-hygiene:clean git", "canonical": canonical,
        "operation": "delete-merged-local-branches", "kinds": ["merged-local-branch"],
        "targets": [target], "note": "re-derive",
    })
actions.append({
    "order": 2, "phase": 3, "skill": "/repo-fleet-hygiene:apply --remote-branches",
    "canonical": canonical, "operation": "delete-remote-branches", "kinds": [kind],
    "targets": targets, "remote_branches": remote_rows, "note": "re-derive",
})
plan = {
    "schema_version": 1, "mode": "read-only", "generated_by": "repo-fleet-hygiene/audit",
    "summary": {},
    "repositories": [{
        "discovered": canonical, "canonical": canonical, "remote": "github.com/acme/r",
        "verdict": "candidates", "kind_counts_text": "", "audited": True, "targets": findings,
    }],
    "actions": actions,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(plan, f, indent=2)
PY
}

# gh stand-in for the apply-time PR recheck. It logs "<repo> <head>" per call and answers with the
# rows in $GH_STUB_DIR/<branch with / as _> (tab-separated state and headRefOid), or exits 1 when
# $GH_STUB_DIR/fail exists.
export GH_STUB_DIR="$TMP/gh-stub" GH_STUB_LOG="$TMP/gh-stub.log"
mkdir -p "$GH_STUB_DIR" "$TMP/bin"
: >"$GH_STUB_LOG"
cat >"$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
repo="" head=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --head) head=$2; shift ;;
  --repo) repo=$2; shift ;;
  esac
  shift
done
printf '%s %s\n' "$repo" "$head" >>"$GH_STUB_LOG"
[[ ! -e "$GH_STUB_DIR/fail" ]] || exit 1
name="$GH_STUB_DIR/${head//\//_}"
if [[ -f "$name.after" && "$(grep -cxF "$repo $head" "$GH_STUB_LOG")" -ge 2 ]]; then name="$name.after"; fi
[[ ! -f "$name" ]] || cat "$name"
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

# set_pr_rows BRANCH [STATE OID]...: what the stubbed GitHub reports for the branch's PRs.
set_pr_rows() {
  local branch=$1 f
  shift
  f="$GH_STUB_DIR/${branch//\//_}"
  : >"$f"
  while [[ $# -ge 2 ]]; do
    printf '%s\t%s\n' "$1" "$2" >>"$f"
    shift 2
  done
}

NP=unmerged-remote-branch

# (a) No --remote-branches: local deletion proceeds, the remote head stays, no push runs.
make_remote_repo ra
RA_NP="$(add_remote_branch "$REMOTE_REPO" feat/np)"
RA_LOCAL="$(add_merged_branch "$REMOTE_REPO" feat/local)"
RA_PLAN="$TMP/ra-plan.json"
LOCAL_ROW="feat/local|$RA_LOCAL" write_remote_plan "$RA_PLAN" "$REMOTE_REPO" "$NP" "feat/np|never-pr|$RA_NP"
ra_out="$TMP/ra.txt"
ra_rc=0
GIT_TRACE="$TMP/ra.trace" bash "$SCRIPT" --plan-file "$RA_PLAN" --apply --yes </dev/null >"$ra_out" 2>&1 || ra_rc=$?
[[ "$ra_rc" -eq 0 ]] && pass "without --remote-branches apply exits 0" || fail "without --remote-branches apply exits 0 (rc=$ra_rc)"
assert_contains "remote row skipped with the opt-in reason" "remote deletion requires --remote-branches" "$ra_out"
assert_branch_deleted "local branch still deleted without --remote-branches" "$REMOTE_REPO" feat/local
assert_remote_head "remote head survives apply without --remote-branches" "$REMOTE_BARE" feat/np "$RA_NP"
[[ -s "$TMP/ra.trace" ]] && pass "git trace captured the run" || fail "git trace captured the run"
assert_not_contains "no git push ran without --remote-branches" "built-in: git push" "$TMP/ra.trace"
[[ ! -e "$RA_PLAN.tip-ledger" ]] && pass "no ledger without --remote-branches" || fail "no ledger without --remote-branches"

# (b) A scripted 'n' (and a blank line) skips both branches, and --yes does not bypass the gate.
make_remote_repo rb
RB_NP="$(add_remote_branch "$REMOTE_REPO" feat/np)"
RB_CL="$(add_remote_branch "$REMOTE_REPO" feat/closed)"
RB_BARE="$REMOTE_BARE"
RB_REPO="$REMOTE_REPO"
set_pr_rows feat/closed CLOSED "$RB_CL"
RB_PLAN="$TMP/rb-plan.json"
write_remote_plan "$RB_PLAN" "$RB_REPO" "$NP" "feat/np|never-pr|$RB_NP" "feat/closed|closed-unmerged|$RB_CL"
if [[ "$HAVE_PTY" -eq 1 ]]; then
  rb_out="$TMP/rb.txt"
  rb_rc=0
  run_pty "$rb_out" n "" -- bash "$SCRIPT" --plan-file "$RB_PLAN" --apply --yes --remote-branches || rb_rc=$?
  [[ "$rb_rc" -eq 0 ]] && pass "declined prompts exit 0" || fail "declined prompts exit 0 (rc=$rb_rc)"
  assert_remote_head "declined never-pr head survives --yes" "$RB_BARE" feat/np "$RB_NP"
  assert_remote_head "declined closed-unmerged head survives" "$RB_BARE" feat/closed "$RB_CL"
  assert_contains "prompt names the repo" "repo:   $RB_REPO" "$rb_out"
  assert_contains "prompt names the remote" "remote: origin" "$rb_out"
  assert_contains "prompt names the branch" "branch: feat/np" "$rb_out"
  assert_contains "prompt names the class" "class:  closed-unmerged" "$rb_out"
  assert_contains "prompt names the tip SHA" "tip:    $RB_NP" "$rb_out"
  assert_contains "declined branch reports a skip" "remote deletion not confirmed" "$rb_out"
  [[ ! -e "$RB_PLAN.tip-ledger" ]] && pass "declined run writes no ledger" || fail "declined run writes no ledger"

  # (c) 'y' for the first branch only: it is deleted, recorded first, and restorable.
  rc_out="$TMP/rc.txt"
  rc_rc=0
  run_pty "$rc_out" y n -- bash "$SCRIPT" --plan-file "$RB_PLAN" --apply --yes --remote-branches || rc_rc=$?
  [[ "$rc_rc" -eq 0 ]] && pass "confirmed delete exits 0" || fail "confirmed delete exits 0 (rc=$rc_rc)"
  assert_remote_head "confirmed head is deleted" "$RB_BARE" feat/np ""
  assert_remote_head "unconfirmed sibling survives" "$RB_BARE" feat/closed "$RB_CL"
  assert_contains "ledger line is printed" "LEDGER: $RB_REPO" "$rc_out"
  ledger="$RB_PLAN.tip-ledger"
  if [[ "$(wc -l <"$ledger")" -eq 1 ]] &&
    [[ "$(awk -F'\t' '{print $1 "|" $2 "|" $3 "|" $4 "|" $5}' "$ledger")" == "$RB_REPO|origin|feat/np|never-pr|$RB_NP" ]] &&
    [[ "$(awk -F'\t' '{print $6}' "$ledger")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]; then
    pass "ledger holds repo, remote, branch, class, tip and UTC time"
  else
    fail "ledger holds repo, remote, branch, class, tip and UTC time"
    cat "$ledger" >&2 || true
  fi
  restore_cmd="$(awk -F'\t' '{print $7}' "$ledger")"
  [[ "$restore_cmd" == "git -C $RB_REPO push origin $RB_NP:refs/heads/feat/np" ]] &&
    pass "ledger restore command has the documented form" ||
    fail "ledger restore command has the documented form ($restore_cmd)"
  bash -c "$restore_cmd" >/dev/null 2>&1
  assert_remote_head "restore command brings the head back at the recorded tip" "$RB_BARE" feat/np "$RB_NP"

  # (c2) The tip object is absent locally: it is fetched so the restore command can work.
  make_remote_repo rc2
  RC2_TIP="$(add_remote_branch "$REMOTE_REPO" feat/other)"
  RC2_TIP="$(move_remote_branch "$REMOTE_BARE" feat/other)"
  if git -C "$REMOTE_REPO" cat-file -e "${RC2_TIP}^{commit}" 2>/dev/null; then
    fail "fixture: tip object must be absent from the canonical repo"
  fi
  RC2_PLAN="$TMP/rc2-plan.json"
  write_remote_plan "$RC2_PLAN" "$REMOTE_REPO" "$NP" "feat/other|never-pr|$RC2_TIP"
  rc2_rc=0
  run_pty "$TMP/rc2.txt" y -- bash "$SCRIPT" --plan-file "$RC2_PLAN" --apply --remote-branches || rc2_rc=$?
  [[ "$rc2_rc" -eq 0 ]] && pass "delete with a fetched tip exits 0" || fail "delete with a fetched tip exits 0 (rc=$rc2_rc)"
  assert_remote_head "head with a non-local tip is deleted" "$REMOTE_BARE" feat/other ""
  bash -c "$(awk -F'\t' '{print $7}' "$RC2_PLAN.tip-ledger")" >/dev/null 2>&1
  assert_remote_head "restore works for a fetched tip" "$REMOTE_BARE" feat/other "$RC2_TIP"
else
  skip_no_pty "(b)/(c) per-branch prompt, ledger and restore cases"
fi

# (d) The remote tip moved after the audit: skipped before any prompt, with an OID-drift reason.
make_remote_repo rd
RD_OLD="$(add_remote_branch "$REMOTE_REPO" feat/moved)"
RD_NEW="$(move_remote_branch "$REMOTE_BARE" feat/moved)"
RD_PLAN="$TMP/rd-plan.json"
write_remote_plan "$RD_PLAN" "$REMOTE_REPO" "$NP" "feat/moved|never-pr|$RD_OLD"
rd_out="$TMP/rd.txt"
rd_rc=0
bash "$SCRIPT" --plan-file "$RD_PLAN" --apply --yes --remote-branches </dev/null >"$rd_out" 2>&1 || rd_rc=$?
[[ "$rd_rc" -eq 0 ]] && pass "drift-only plan exits 0 (nothing to prompt)" || fail "drift-only plan exits 0 (rc=$rd_rc)"
assert_contains "moved remote tip is skipped with an OID-drift reason" "OID drift (plan tip != live remote tip)" "$rd_out"
assert_contains "drift row shows the live tip" "live_oid: $RD_NEW" "$rd_out"
assert_remote_head "drifted remote head is untouched" "$REMOTE_BARE" feat/moved "$RD_NEW"

# The default branch and an already-gone head are skipped as well.
make_remote_repo rd2
RD2_MAIN="$(git -C "$REMOTE_REPO" rev-parse HEAD)"
RD2_PLAN="$TMP/rd2-plan.json"
write_remote_plan "$RD2_PLAN" "$REMOTE_REPO" "$NP" "main|never-pr|$RD2_MAIN" "feat/gone|never-pr|$RD2_MAIN"
rd2_out="$TMP/rd2.txt"
bash "$SCRIPT" --plan-file "$RD2_PLAN" --remote-branches >"$rd2_out" 2>&1
assert_contains "default branch is protected" "protected default branch" "$rd2_out"
assert_contains "gone head is skipped" "remote head already gone" "$rd2_out"
assert_not_contains "no command is printed for skipped rows" "command: git" "$rd2_out"

# (e) Non-interactive --remote-branches --yes prints the rows and deletes nothing, local rows included.
make_remote_repo re
RE_NP="$(add_remote_branch "$REMOTE_REPO" feat/np)"
RE_LOCAL="$(add_merged_branch "$REMOTE_REPO" feat/local)"
RE_PLAN="$TMP/re-plan.json"
LOCAL_ROW="feat/local|$RE_LOCAL" write_remote_plan "$RE_PLAN" "$REMOTE_REPO" "$NP" "feat/np|never-pr|$RE_NP"
re_out="$TMP/re.txt"
re_rc=0
bash "$SCRIPT" --plan-file "$RE_PLAN" --apply --yes --remote-branches </dev/null >"$re_out" 2>&1 || re_rc=$?
[[ "$re_rc" -eq 3 ]] && pass "non-interactive --remote-branches --yes exits 3" || fail "non-interactive --remote-branches --yes exits 3 (rc=$re_rc)"
assert_contains "non-interactive run still prints the remote row" "[delete-remote-branch]" "$re_out"
assert_contains "non-interactive run says nothing was mutated" "mutate nothing" "$re_out"
assert_remote_head "non-interactive run deletes no remote head" "$REMOTE_BARE" feat/np "$RE_NP"
assert_branch_kept "non-interactive run deletes no local branch" "$REMOTE_REPO" feat/local

# (f) Dry-run rows are the commands the gated path runs.
make_remote_repo rf
RF_A="$(add_remote_branch "$REMOTE_REPO" feat/a)"
RF_B="$(add_remote_branch "$REMOTE_REPO" feat/b)"
RF_REPO="$REMOTE_REPO"
set_pr_rows feat/b CLOSED "$RF_B"
RF_PLAN="$TMP/rf-plan.json"
write_remote_plan "$RF_PLAN" "$RF_REPO" "$NP" "feat/a|never-pr|$RF_A" "feat/b|closed-unmerged|$RF_B"
rf_dry="$TMP/rf-dry.txt"
bash "$SCRIPT" --plan-file "$RF_PLAN" --remote-branches >"$rf_dry" 2>&1
grep -F '   command: git ' "$rf_dry" | sed "s|^   command: git -C $RF_REPO ||" | sort >"$TMP/rf-dry.cmds"
assert_contains "dry-run prints the lease-guarded delete command" \
  "command: git -C $RF_REPO push origin --delete refs/heads/feat/a --force-with-lease=refs/heads/feat/a:$RF_A" "$rf_dry"
assert_remote_head "dry-run deletes nothing" "$REMOTE_BARE" feat/a "$RF_A"
if [[ "$HAVE_PTY" -eq 1 ]]; then
  GIT_TRACE="$TMP/rf.trace" run_pty "$TMP/rf-apply.txt" y y -- bash "$SCRIPT" --plan-file "$RF_PLAN" --apply --remote-branches ||
    fail "gated run for parity exits 0"
  sed -n 's/.*built-in: git push /push /p' "$TMP/rf.trace" | sort >"$TMP/rf-run.cmds"
  if [[ -s "$TMP/rf-run.cmds" ]] && diff -u "$TMP/rf-dry.cmds" "$TMP/rf-run.cmds" >&2; then
    pass "dry-run commands equal the pushes the gated path ran"
  else
    fail "dry-run commands equal the pushes the gated path ran"
  fi
  assert_remote_head "gated parity run deleted the first head" "$REMOTE_BARE" feat/a ""
  assert_remote_head "gated parity run deleted the second head" "$REMOTE_BARE" feat/b ""
else
  skip_no_pty "(f) gated half of the dry-run parity case"
fi

# The printed command carries a literal full-width lease, the shape the guardrails hook allows.
HOOK="$SCRIPT_DIR/../../../../guardrails/hooks/block-dangerous-git.sh"
if [[ -f "$HOOK" ]] && command -v jq >/dev/null 2>&1; then
  hook_rc() {
    local cmd=$1 rc=0
    python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))' \
      "$cmd" "$RF_REPO" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
    printf '%s\n' "$rc"
  }
  rf_cmd="git -C $RF_REPO push origin --delete refs/heads/feat/a --force-with-lease=refs/heads/feat/a:$RF_A"
  [[ "$(hook_rc "$rf_cmd")" -eq 0 ]] && pass "block-dangerous-git allows the lease-guarded delete" ||
    fail "block-dangerous-git allows the lease-guarded delete"
  [[ "$(hook_rc "git -C $RF_REPO push origin --delete refs/heads/feat/a --force-with-lease=refs/heads/feat/a:${RF_A:0:12}")" -eq 2 ]] &&
    pass "block-dangerous-git still blocks an abbreviated lease (fixture discriminates)" ||
    fail "block-dangerous-git still blocks an abbreviated lease (fixture discriminates)"
else
  printf 'SKIP: guardrails hook or jq unavailable; lease-guarded delete not checked against block-dangerous-git\n'
fi

# The lease refuses a head that moved after the dry-run listed its command.
make_remote_repo ri
RI_OLD="$(add_remote_branch "$REMOTE_REPO" feat/lease)"
RI_PLAN="$TMP/ri-plan.json"
write_remote_plan "$RI_PLAN" "$REMOTE_REPO" "$NP" "feat/lease|never-pr|$RI_OLD"
ri_cmd="$(bash "$SCRIPT" --plan-file "$RI_PLAN" --remote-branches | sed -n 's/^   command: //p')"
RI_NEW="$(move_remote_branch "$REMOTE_BARE" feat/lease)"
ri_rc=0
bash -c "$ri_cmd" >/dev/null 2>&1 || ri_rc=$?
[[ "$ri_rc" -ne 0 ]] && pass "stale lease rejects the delete" || fail "stale lease rejects the delete"
assert_remote_head "concurrent push survives the stale-lease delete" "$REMOTE_BARE" feat/lease "$RI_NEW"

# (g) A merged-class action forged into delete-remote-branches is rejected by kind validation.
make_remote_repo rg
RG_OID="$(add_remote_branch "$REMOTE_REPO" feat/merged)"
for forged in merged-remote-branch merged-local-branch; do
  RG_PLAN="$TMP/rg-$forged.json"
  write_remote_plan "$RG_PLAN" "$REMOTE_REPO" "$forged" "feat/merged|never-pr|$RG_OID"
  rg_out="$TMP/rg-$forged.txt"
  rg_rc=0
  bash "$SCRIPT" --plan-file "$RG_PLAN" --apply --yes --remote-branches </dev/null >"$rg_out" 2>&1 || rg_rc=$?
  if [[ "$rg_rc" -eq 2 ]] && grep -Fq "finding kind $forged is not valid for operation delete-remote-branches" "$rg_out"; then
    pass "forged $forged action is rejected by kind validation"
  else
    fail "forged $forged action is rejected by kind validation (rc=$rg_rc)"
    cat "$rg_out" >&2
  fi
done
assert_remote_head "forged plans deleted nothing" "$REMOTE_BARE" feat/merged "$RG_OID"

# A tip that is not the audit finding's tip, or is abbreviated, is a bad plan (exit 2).
RG_BAD="$TMP/rg-bad.json"
write_remote_plan "$RG_BAD" "$REMOTE_REPO" "$NP" "feat/merged|never-pr|${RG_OID:0:7}|${RG_OID:0:7}"
rg_rc=0
bash "$SCRIPT" --plan-file "$RG_BAD" --remote-branches >"$TMP/rg-bad.txt" 2>&1 || rg_rc=$?
[[ "$rg_rc" -eq 2 ]] && grep -Fq "not a full lowercase object id" "$TMP/rg-bad.txt" &&
  pass "abbreviated expected_oid is rejected" || fail "abbreviated expected_oid is rejected (rc=$rg_rc)"
write_remote_plan "$RG_BAD" "$REMOTE_REPO" "$NP" "feat/merged|never-pr|$RG_OID|$(printf 'f%.0s' {1..40})"
rg_rc=0
bash "$SCRIPT" --plan-file "$RG_BAD" --remote-branches >"$TMP/rg-bad.txt" 2>&1 || rg_rc=$?
[[ "$rg_rc" -eq 2 ]] && grep -Fq "does not match the audit finding evidence" "$TMP/rg-bad.txt" &&
  pass "expected_oid that disagrees with the finding evidence is rejected" ||
  fail "expected_oid that disagrees with the finding evidence is rejected (rc=$rg_rc)"
write_remote_plan "$RG_BAD" "$REMOTE_REPO" "$NP" "feat/merged|closed-unmerged|$RG_OID|$RG_OID|never-pr"
rg_rc=0
bash "$SCRIPT" --plan-file "$RG_BAD" --remote-branches >"$TMP/rg-bad.txt" 2>&1 || rg_rc=$?
[[ "$rg_rc" -eq 2 ]] && grep -Fq "class does not match the audit finding evidence" "$TMP/rg-bad.txt" &&
  pass "class that disagrees with the finding evidence is rejected" ||
  fail "class that disagrees with the finding evidence is rejected (rc=$rg_rc)"
write_remote_plan "$RG_BAD" "$REMOTE_REPO" "$NP" "feat/../x|never-pr|$RG_OID"
rg_rc=0
bash "$SCRIPT" --plan-file "$RG_BAD" --remote-branches >"$TMP/rg-bad.txt" 2>&1 || rg_rc=$?
[[ "$rg_rc" -eq 2 ]] && grep -Fq "branch is not a valid ref name" "$TMP/rg-bad.txt" &&
  pass "invalid branch ref name is rejected" || fail "invalid branch ref name is rejected (rc=$rg_rc)"

# (h) A remote retargeted after the audit no longer names the audited repository: skipped, no push.
make_remote_repo rj
RJ_OID="$(add_remote_branch "$REMOTE_REPO" feat/np)"
RJ_REPO="$REMOTE_REPO"
RJ_BARE="$REMOTE_BARE"
RJ_OTHER="$TMP/rj-other.git"
git clone -q --bare "$RJ_BARE" "$RJ_OTHER"
RJ_PLAN="$TMP/rj-plan.json"
write_remote_plan "$RJ_PLAN" "$RJ_REPO" "$NP" "feat/np|never-pr|$RJ_OID"
rj_run() {
  local label=$1 out="$TMP/rj-$1.txt" rc=0
  bash "$SCRIPT" --plan-file "$RJ_PLAN" --apply --yes --remote-branches </dev/null >"$out" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] && pass "$label: run exits 0 with nothing to prompt" || fail "$label: run exits 0 with nothing to prompt (rc=$rc)"
  assert_contains "$label: skipped as no longer the audited repository" \
    "remote no longer names the audited repository" "$out"
  assert_remote_head "$label: audited remote head survives" "$RJ_BARE" feat/np "$RJ_OID"
  assert_remote_head "$label: retargeted remote head survives" "$RJ_OTHER" feat/np "$RJ_OID"
}
git -C "$RJ_REPO" remote set-url origin "$RJ_OTHER"
rj_run "set-url retarget"
git -C "$RJ_REPO" remote set-url origin "$RJ_BARE"
git -C "$RJ_REPO" config remote.origin.pushurl "$RJ_OTHER"
rj_run "pushurl retarget"
git -C "$RJ_REPO" config --unset remote.origin.pushurl
git -C "$RJ_REPO" config "url.$RJ_OTHER.insteadOf" "$RJ_BARE"
rj_run "insteadOf retarget"
git -C "$RJ_REPO" config --unset "url.$RJ_OTHER.insteadOf"
rj_ok="$TMP/rj-ok.txt"
bash "$SCRIPT" --plan-file "$RJ_PLAN" --remote-branches >"$rj_ok" 2>&1
assert_contains "restored remote passes the identity check" "[delete-remote-branch]" "$rj_ok"
GITHUB_URL_KEY=github.com/acme/r
git -C "$RJ_REPO" remote set-url origin "git@github.com:Acme/R.git"
REMOTE_KEY="$GITHUB_URL_KEY" write_remote_plan "$RJ_PLAN" "$RJ_REPO" "$NP" "feat/np|never-pr|$RJ_OID"
[[ "$(bash "$SCRIPT" --plan-file "$RJ_PLAN" --remote-branches 2>&1 | grep -c 'remote no longer names')" -eq 0 ]] &&
  pass "a GitHub URL in another spelling keeps the same identity" ||
  fail "a GitHub URL in another spelling keeps the same identity"
git -C "$RJ_REPO" remote set-url origin "https://github.com/acme/other.git"
rj_run_gh="$TMP/rj-gh.txt"
bash "$SCRIPT" --plan-file "$RJ_PLAN" --remote-branches >"$rj_run_gh" 2>&1
assert_contains "a different GitHub repository is refused" "remote no longer names the audited repository" "$rj_run_gh"

# (i) PR state is re-read before a row becomes deletable; anything but the audited class skips it.
make_remote_repo rk
RK_REPO="$REMOTE_REPO"
RK_OPEN="$(add_remote_branch "$RK_REPO" feat/open)"
RK_MERGED="$(add_remote_branch "$RK_REPO" feat/merged)"
RK_REOPENED="$(add_remote_branch "$RK_REPO" feat/reopened)"
RK_STALE="$(add_remote_branch "$RK_REPO" feat/stale)"
RK_OK="$(add_remote_branch "$RK_REPO" feat/ok)"
set_pr_rows feat/open OPEN "$RK_OPEN"
set_pr_rows feat/merged MERGED "$RK_MERGED"
set_pr_rows feat/reopened CLOSED "$RK_REOPENED"
set_pr_rows feat/stale CLOSED "$(printf 'f%.0s' {1..40})"
set_pr_rows feat/ok CLOSED "$RK_OK"
RK_PLAN="$TMP/rk-plan.json"
write_remote_plan "$RK_PLAN" "$RK_REPO" "$NP" "feat/open|never-pr|$RK_OPEN" \
  "feat/merged|closed-unmerged|$RK_MERGED" "feat/reopened|never-pr|$RK_REOPENED" \
  "feat/stale|closed-unmerged|$RK_STALE" "feat/ok|closed-unmerged|$RK_OK"
: >"$GH_STUB_LOG"
rk_out="$TMP/rk.txt"
bash "$SCRIPT" --plan-file "$RK_PLAN" --remote-branches >"$rk_out" 2>&1
assert_contains "an OPEN PR blocks deletion" "a PR with this head is now OPEN" "$rk_out"
assert_contains "a MERGED PR blocks deletion" "a PR with this head is now MERGED" "$rk_out"
assert_contains "a PR on a never-pr row blocks deletion" "class changed: a PR now exists for this head" "$rk_out"
assert_contains "a CLOSED PR at another tip blocks a closed-unmerged row" "class changed: no CLOSED PR at the plan tip" "$rk_out"
assert_contains "a matching CLOSED PR keeps a closed-unmerged row deletable" \
  "GitHub PR state matches class closed-unmerged" "$rk_out"
[[ "$(grep -cF '[delete-remote-branch]' "$rk_out")" -eq 1 ]] &&
  pass "only the row whose PR state matches stays deletable" ||
  fail "only the row whose PR state matches stays deletable"
assert_contains "the audited GitHub repository was queried for the branch" "github.com/acme/r feat/open" "$GH_STUB_LOG"
touch "$GH_STUB_DIR/fail"
rk_fail="$TMP/rk-fail.txt"
bash "$SCRIPT" --plan-file "$RK_PLAN" --remote-branches >"$rk_fail" 2>&1
assert_contains "an unreadable PR state fails closed" "GitHub PR state could not be verified (fail-closed)" "$rk_fail"
assert_not_contains "no row is deletable while PR state is unreadable" "[delete-remote-branch]" "$rk_fail"
rm -f "$GH_STUB_DIR/fail"

# (j) A PR that appears while the prompt is open stops the delete after the yes, before any ledger.
if [[ "$HAVE_PTY" -eq 1 ]]; then
  make_remote_repo rl
  RL_OID="$(add_remote_branch "$REMOTE_REPO" feat/late)"
  set_pr_rows feat/late
  printf 'OPEN\t%s\n' "$RL_OID" >"$GH_STUB_DIR/feat_late.after"
  RL_PLAN="$TMP/rl-plan.json"
  write_remote_plan "$RL_PLAN" "$REMOTE_REPO" "$NP" "feat/late|never-pr|$RL_OID"
  rl_out="$TMP/rl.txt"
  rl_rc=0
  run_pty "$rl_out" y -- bash "$SCRIPT" --plan-file "$RL_PLAN" --apply --remote-branches || rl_rc=$?
  [[ "$rl_rc" -eq 0 ]] && pass "late PR: skipped branch exits 0" || fail "late PR: skipped branch exits 0 (rc=$rl_rc)"
  assert_contains "late PR: the confirmed row is re-checked and skipped" "a PR with this head is now OPEN" "$rl_out"
  assert_remote_head "late PR: head survives a yes given after the PR opened" "$REMOTE_BARE" feat/late "$RL_OID"
  [[ ! -e "$RL_PLAN.tip-ledger" ]] && pass "late PR: no ledger line written" || fail "late PR: no ledger line written"
else
  skip_no_pty "late PR case"
fi

# A ledger that cannot be written aborts that branch before the push.
if [[ "$HAVE_PTY" -eq 1 ]]; then
  make_remote_repo rh
  RH_OID="$(add_remote_branch "$REMOTE_REPO" feat/np)"
  RH_PLAN="$TMP/rh-plan.json"
  write_remote_plan "$RH_PLAN" "$REMOTE_REPO" "$NP" "feat/np|never-pr|$RH_OID"
  mkdir "$RH_PLAN.tip-ledger"
  rh_out="$TMP/rh.txt"
  rh_rc=0
  run_pty "$rh_out" y -- bash "$SCRIPT" --plan-file "$RH_PLAN" --apply --remote-branches || rh_rc=$?
  [[ "$rh_rc" -eq 4 ]] && pass "ledger write failure exits 4" || fail "ledger write failure exits 4 (rc=$rh_rc)"
  assert_contains "ledger write failure names the branch" "not deleted" "$rh_out"
  assert_remote_head "head survives a failed ledger write" "$REMOTE_BARE" feat/np "$RH_OID"
else
  skip_no_pty "ledger write failure case"
fi

if [[ "$fails" -ne 0 ]]; then
  printf 'apply-plan tests failed.\n' >&2
  exit 1
fi
printf 'All apply-plan tests passed.\n'
