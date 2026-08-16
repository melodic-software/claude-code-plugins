#!/usr/bin/env bash
# Tests for the prerequisite-resolution setup slice wrappers.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SELF_DIR/check-prerequisite-resolution.mjs"
APPLY="$SELF_DIR/apply-prerequisite-resolution.mjs"
FIXTURES="$SELF_DIR/fixtures/prerequisite-resolution"
ENVELOPE="$SELF_DIR/check-signal-envelope.mjs"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- bare-repo check: every identity negative/unknown, no error -------------
if out="$(node "$CHECK" --repo "$FIXTURES/bare-repo/repo" --surface ci-cron 2>"$tmp/err")"; then
  node -e '
    const o = JSON.parse(process.argv[1]);
    if (o.liveness?.taxonomy_row !== "engine health-check") process.exit(2);
    for (const report of o.surfaces) {
      for (const row of report.identities) {
        if (row.verdict === "supported" || row.verdict === "conditional") process.exit(3);
      }
    }
  ' "$out"
  code=$?
  if [[ $code -eq 0 ]]; then
    ok "bare_repo_check: negative/unknown verdicts, liveness row present"
  else
    fail "bare_repo_check: assertion exit $code err=$(cat "$tmp/err")"
  fi
else
  fail "bare_repo_check: check exited non-zero: $(cat "$tmp/err")"
fi

# --- reconcile finding: declaration vs ran-negative probe -------------------
# Reuse probe-negative-caps fixture (declaration asserts tracker present; absent).
if out="$(node "$APPLY" --repo "$FIXTURES/probe-negative-caps/repo" --surface ci-cron --non-interactive 2>"$tmp/err")"; then
  node -e '
    const o = JSON.parse(process.argv[1]);
    const findings = o.reconcile_findings || [];
    const hit = findings.find((f) => f.kind === "declaration-probe-contradiction");
    if (!hit) process.exit(2);
    if (hit.verdict !== "unsupported") process.exit(3);
    if (o.security_binding_writes !== false) process.exit(4);
    if (!Array.isArray(o.assumptions) || o.assumptions.length === 0) process.exit(5);
  ' "$out"
  code=$?
  if [[ $code -eq 0 ]]; then
    ok "reconcile_finding: contradiction finding + unsupported + no security writes"
  else
    fail "reconcile_finding: assertion exit $code"
  fi
else
  fail "reconcile_finding: apply exited non-zero: $(cat "$tmp/err")"
fi

# --- ratify writes section without surfaces map; envelope check passes ------
mkdir -p "$tmp/repo/.claude/autonomy"
cat >"$tmp/repo/.claude/autonomy/binding.json" <<'EOF'
{
  "schema_version": "1.0",
  "triggers": {
    "surfaces": {
      "ci-cron": {
        "class": "temporal",
        "transport": "poll",
        "scheduler_class": "ci-cron",
        "execution_surface": "github-actions"
      }
    }
  },
  "routines": {
    "enabled": {
      "issue-triage-sweep": {
        "enabled": false,
        "source_surface": "ci-cron",
        "cadence": "daily"
      }
    }
  }
}
EOF
cat >"$tmp/proposal.json" <<'EOF'
{
  "schema_version": "1.0",
  "surface_refs": ["ci-cron"],
  "declarations": [
    {
      "surface": "ci-cron",
      "identity": "issue-triage-sweep",
      "need": "tracker",
      "state": "absent",
      "rung": "repo-local"
    }
  ]
}
EOF
if node "$APPLY" --repo "$tmp/repo" --ratify --proposal "$tmp/proposal.json" >/dev/null 2>"$tmp/err"; then
  node -e '
    const b = require(process.argv[1]);
    const s = b.prerequisite_resolution;
    if (!s) process.exit(2);
    if (s.surfaces) process.exit(3);
    if (!Array.isArray(s.surface_refs) || !s.surface_refs.includes("ci-cron")) process.exit(4);
  ' "$tmp/repo/.claude/autonomy/binding.json"
  code=$?
  if [[ $code -eq 0 ]]; then
    ok "ratify: writes prerequisite_resolution without surfaces map"
  else
    fail "ratify: binding shape exit $code"
  fi
else
  fail "ratify: apply --ratify failed: $(cat "$tmp/err")"
fi

# Envelope conformance against the fixture binding carrying the new section.
cat >"$tmp/envelope.md" <<'EOF'
<!-- autonomy:signal:v1 -->
```json
{
  "schema_version": "1.0",
  "signal.class": "temporal",
  "signal.transport": "poll",
  "signal.provenance": "system",
  "signal.identity": "autonomy:setup-test",
  "signal.raw_link": "https://example.invalid/runs/1",
  "signal.traceparent": "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01",
  "signal.source_surface": "ci-cron",
  "signal.routine": "issue-triage-sweep",
  "signal.producer_identity": "workflow://ci.yml"
}
```
EOF
# Enable the routine so the envelope can cite it; prerequisite_resolution section
# must still not introduce a surfaces map (envelope merges surfaces across sections).
node -e '
const fs = require("node:fs");
const p = process.argv[1];
const b = JSON.parse(fs.readFileSync(p, "utf8"));
b.routines.enabled["issue-triage-sweep"].enabled = true;
fs.writeFileSync(p, JSON.stringify(b, null, 2) + "\n");
' "$tmp/repo/.claude/autonomy/binding.json"
if node "$ENVELOPE" "$tmp/envelope.md" --binding "$tmp/repo/.claude/autonomy/binding.json" >/dev/null 2>"$tmp/env.err"; then
  ok "envelope: binding with prerequisite_resolution section passes"
else
  # Print for diagnosis but still allow known work_class-related failures?
  fail "envelope: $(cat "$tmp/env.err")"
fi

echo
echo "Passed: $PASS  Failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
