#!/usr/bin/env bash
# Black-box contract test for probe-invocation.py.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/probe-invocation.py"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

if ! command -v python3 >/dev/null 2>&1; then
  printf 'Error: python3 is required\n' >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() { python3 "$SUT" "$@"; }

out="$(run --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'labeled auto-invocation queries' <<<"$out"; then
  pass "--help exits 0 and names the probe suite"
else
  fail "--help should describe the suite (rc=$rc): $out"
fi

out="$(run "$TMP/missing.json" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'does not exist' <<<"$out"; then
  pass "a missing probe file exits 2"
else
  fail "missing probe should exit 2 (rc=$rc): $out"
fi

ROOT="$TMP/plugin/skills"
mkdir -p "$ROOT/alpha" "$ROOT/beta"
cat >"$ROOT/alpha/SKILL.md" <<'EOF'
---
description: "Lint a skill's frontmatter and description. Use when: 'check this skill', 'lint my skill'."
disable-model-invocation: false
---

## Purpose

Fixture target.
EOF
cat >"$ROOT/beta/SKILL.md" <<'EOF'
---
description: "Configure the skills_root option. Use when: 'set up skill-quality', 'configure skills_root'."
disable-model-invocation: true
---

## Purpose

Fixture competitor.
EOF

PROBE="$TMP/probes/alpha.json"
mkdir -p "$TMP/probes"
cat >"$PROBE" <<EOF
{
  "skill": "alpha",
  "skill_md": "$ROOT/alpha/SKILL.md",
  "competitors": ["$ROOT/beta/SKILL.md"],
  "queries": [
    {"id": "train-pos-01", "split": "train", "expect": "trigger", "request": "check this skill"},
    {"id": "train-neg-01", "split": "train", "expect": "hold", "request": "configure skills_root"},
    {"id": "val-pos-01", "split": "val", "expect": "trigger", "request": "lint my skill"},
    {"id": "val-neg-01", "split": "val", "expect": "hold", "request": "merge this pull request"}
  ]
}
EOF

REPORT="$TMP/report.json"
out="$(run "$PROBE" --json "$REPORT" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'skill: alpha' <<<"$out" &&
  grep -q 'train: trigger_rate=100.00%' <<<"$out" &&
  grep -q 'mode: listing-coverage' <<<"$out"; then
  pass "fixture probe reports listing-coverage rates"
else
  fail "fixture probe should pass (rc=$rc): $out"
fi

if python3 - "$REPORT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["query_count"] == 4, r
assert r["train"]["trigger"]["passed"] == 1
assert r["train"]["hold"]["passed"] == 1
assert r["val"]["trigger"]["passed"] == 1
assert r["val"]["hold"]["passed"] == 1
assert r["mode"] == "listing-coverage"
PY
then
  pass "JSON report carries train/val trigger and hold counts"
else
  fail "JSON report shape"
fi

BASE="$TMP/baseline.json"
cp "$REPORT" "$BASE"
out="$(run "$PROBE" --compare "$BASE" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'train.trigger: 100.00% -> 100.00% (+0.00%)' <<<"$out"; then
  pass "--compare prints a zero delta against an identical baseline"
else
  fail "--compare should print a zero delta (rc=$rc): $out"
fi

BUNDLED="$SCRIPT_DIR/../skills/check/probes/check.json"
if [[ -f "$BUNDLED" ]]; then
  bout="$(run "$BUNDLED" 2>&1)"
  brc=$?
  if [[ $brc -eq 0 ]] && grep -q 'skill: skill-quality:check' <<<"$bout" &&
    grep -q 'queries: 20' <<<"$bout"; then
    pass "bundled check.json grades 20 labeled queries"
  else
    fail "bundled probe should grade 20 queries (rc=$brc): $bout"
  fi
else
  fail "bundled check.json is missing"
fi

if [[ $fails -gt 0 ]]; then
  printf '%s fixture failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'All probe-invocation tests passed\n'
exit 0
