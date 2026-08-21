#!/usr/bin/env bash
# apply-plan.test.sh — dry-run, confirmation stop, OID drift skip, ordering.
# shellcheck disable=SC2310 # pass/fail helpers return status in if/||; every false path is handled

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
bash "$SCRIPT" --plan-file "$PLAN" --apply < /dev/null >"$stop_out" 2>&1 || rc=$?
if [[ "$rc" -eq 3 ]] && grep -Fq "non-interactive session without --yes" "$stop_out"; then
  pass "confirmation stop without --yes (exit 3)"
else
  fail "confirmation stop without --yes (rc=$rc)"
  cat "$stop_out" >&2
fi
if git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/alpha; then
  pass "confirmation stop mutated nothing"
else
  fail "confirmation stop mutated nothing"
fi

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
if git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/alpha; then
  pass "drifted branch retained"
else
  fail "drifted branch retained"
fi
# Non-drifted branch and worktree should still apply.
if ! git -C "$REPO_B" show-ref --verify --quiet refs/heads/feat/beta; then
  pass "non-drifted branch deleted"
else
  fail "non-drifted branch deleted"
fi
if [[ ! -d "$WT_PATH" ]] && ! git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/wt; then
  pass "matching worktree removed and branch deleted"
else
  fail "matching worktree removed and branch deleted"
  printf 'wt exists=%s branch=%s\n' "$([[ -d $WT_PATH ]] && echo yes || echo no)" \
    "$(git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/wt && echo yes || echo no)" >&2
fi

# --- 4) Interactive decline via stdin ---------------------------------------
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

# Simulate a tty confirmation decline is hard without a pty; the non-tty path
# already covered the gate. Exercise explicit "n" by forcing the tty path only when
# possible — otherwise skip with a note. Use a FIFO trick: the script checks -t 0,
# so plain printf 'n' still hits the non-interactive stop. Assert branch survives
# a declined path by invoking with --apply and empty stdin (already tested) plus
# a successful --yes apply on a copy for positive control later.

decline_rc=0
bash "$SCRIPT" --plan-file "$PLAN2" --apply </dev/null >/dev/null 2>&1 || decline_rc=$?
[[ "$decline_rc" -eq 3 ]] || fail "plan2 confirmation stop rc=$decline_rc"
if git -C "$REPO_B" show-ref --verify --quiet refs/heads/feat/gamma; then
  pass "confirmation-stop retained feat/gamma"
else
  fail "confirmation-stop retained feat/gamma"
fi

yes_out="$TMP/yes.txt"
bash "$SCRIPT" --plan-file "$PLAN2" --apply --yes >"$yes_out" 2>&1
assert_contains "yes apply deleted gamma" "APPLIED: deleted branch feat/gamma" "$yes_out"
if ! git -C "$REPO_B" show-ref --verify --quiet refs/heads/feat/gamma; then
  pass "--yes applied matching branch delete"
else
  fail "--yes applied matching branch delete"
fi

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
if git -C "$REPO_A" show-ref --verify --quiet refs/heads/feat/unbound; then
  pass "unbound plan mutated nothing"
else
  fail "unbound plan mutated nothing"
fi

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

if [[ "$fails" -ne 0 ]]; then
  printf 'apply-plan tests failed.\n' >&2
  exit 1
fi
printf 'All apply-plan tests passed.\n'
