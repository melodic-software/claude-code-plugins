#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/babysit-readiness-gate.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

run_gate() {
  local fixture="$1"
  shift
  local out
  out=$(bash "$GATE" 123 --comments-json "$fixture" --self 'me[bot]' "$@" 2>/dev/null)
  local code=$?
  printf '%s\nEXIT:%s' "$out" "$code"
}

mkjson() {
  local f="$TEST_TMPDIR/$1.json"
  jq -n "$2" >"$f"
  printf '%s' "$f"
}

help_out=$(bash "$GATE" --help 2>&1)
assert_exit "--help exit 0" 0 "$?"
assert_contains "--help describes the gate" "$help_out" "readiness pre-gate"
assert_contains "--help documents the env-var override" "$help_out" "FETCH_COMMENTS_OWNER"
assert_contains "--help documents --repo" "$help_out" "--repo owner/repo"

bash "$GATE" 123 --bogus >/dev/null 2>&1
assert_exit "unknown flag exit 3" 3 "$?"

bash "$GATE" >/dev/null 2>&1
assert_exit "no args exit 3" 3 "$?"

bash "$GATE" 123 --repo bad --comments-json /dev/null >/dev/null 2>&1
assert_exit "bad --repo exit 3" 3 "$?"

F=$(mkjson under '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [IMPORTANT] b\n### 3. [SUGGESTION] c"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "under -> BLOCKED under-decomposed" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "under findings=3" "$r" "findings=3"
assert_contains "under classified=1" "$r" "classified=1"
assert_contains "under exit 1" "$r" "EXIT:1"

F=$(mkjson ok '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [IMPORTANT] b"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\n| 2 | b | INCORRECT | refuted |"}
]')
r=$(run_gate "$F")
assert_contains "ok -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "ok findings=2 classified=2" "$r" "findings=2 classified=2"
assert_contains "ok exit 0" "$r" "EXIT:0"

F=$(mkjson empty '[
  {author:"human", body:"LGTM, nice work"},
  {author:"me[bot]", body:"thanks"}
]')
r=$(run_gate "$F")
assert_contains "zero-findings -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "zero-findings findings=0" "$r" "findings=0"
assert_contains "zero-findings exit 0" "$r" "EXIT:0"

F=$(mkjson ckl '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
CK="$TEST_TMPDIR/checklist.md"
printf -- '- [x] done\n- [ ] not done\n' >"$CK"
r=$(run_gate "$F" --checklist "$CK")
assert_contains "checklist-incomplete -> BLOCKED" "$r" "READINESS_BLOCKED reason=checklist-incomplete"
assert_contains "checklist unticked=1" "$r" "unticked=1"
assert_contains "checklist-incomplete exit 1" "$r" "EXIT:1"

CK2="$TEST_TMPDIR/checklist-clean.md"
printf -- '- [x] done\n- [x] also done\n' >"$CK2"
r=$(run_gate "$F" --checklist "$CK2")
assert_contains "checklist-clean -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "checklist-clean state" "$r" "checklist=clean"
assert_contains "checklist-clean exit 0" "$r" "EXIT:0"

F=$(mkjson multiline '[
  {author:"claude[bot]", body:"CRITICAL: fix null check AND IMPORTANT: add validation"},
  {author:"me[bot]", body:"| 1 | null check | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "one-line-two-findings -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "one-line-two-findings findings=2" "$r" "findings=2"

F=$(mkjson nofalsepos '[
  {author:"human", body:"P0 blocker on priority:p0-critical, prior call was INVALID"},
  {author:"me[bot]", body:"acknowledged"}
]')
r=$(run_gate "$F")
assert_contains "no-false-positive findings=0" "$r" "findings=0"
assert_contains "no-false-positive -> READINESS_OK" "$r" "READINESS_OK"

F=$(mkjson codexfmt '[
  {author:"chatgpt-codex-connector[bot]", body:"![P1 Badge](https://img.shields.io/badge/P1-red?style=flat) Count findings AND ![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat) validate port"},
  {author:"me[bot]", body:"| 1 | count | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "codex P-severity -> BLOCKED (findings counted)" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "codex P-severity findings=2" "$r" "findings=2"

F=$(mkjson codexbadgeurl '[
  {author:"chatgpt-codex-connector[bot]", body:"**<sub><sub>![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)</sub></sub> Propagate failed restarts**"},
  {author:"me[bot]", body:"| 1 | propagate | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "codex-badge-with-url findings=1 (not double-counted)" "$r" "findings=1"
assert_contains "codex-badge-with-url -> READINESS_OK" "$r" "READINESS_OK"

F=$(mkjson codexp0 '[
  {author:"chatgpt-codex-connector[bot]", body:"**<sub><sub>![P0 Badge](https://img.shields.io/badge/P0-red?style=flat)</sub></sub> Critical finding**"},
  {author:"me[bot]", body:"acknowledged, investigating"}
]')
r=$(run_gate "$F")
assert_contains "codex-P0 findings=1 (counted, not dropped)" "$r" "findings=1"
assert_contains "codex-P0 unclassified -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson p0label '[
  {author:"human", body:"this is priority:p0-critical per our triage"},
  {author:"me[bot]", body:"noted"}
]')
r=$(run_gate "$F")
assert_contains "p0-label findings=0 (no false-count)" "$r" "findings=0"

F=$(mkjson selffinding '[
  {author:"me[bot]", body:"### 1. [CRITICAL] a self-authored source finding"},
  {author:"human", body:"ack"}
]')
r=$(run_gate "$F")
assert_contains "self-finding counted -> findings=1" "$r" "findings=1"
assert_contains "self-finding unclassified -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson selfclass '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "self-classification not a finding -> findings=1" "$r" "findings=1"
assert_contains "self-classification -> READINESS_OK" "$r" "READINESS_OK"

bash "$GATE" 123 --comments-json >/dev/null 2>&1
assert_exit "--comments-json missing arg exit 3" 3 "$?"

# --- Case: portable whole-word matching, no \b (BSD grep) --------------------
# BSD grep on macOS does not support the `\b` escape; the gate must use POSIX
# `-w` whole-word matching, which works on GNU + BSD.
GATE_BODY=$(cat "$GATE")
if [[ "$GATE_BODY" == *'grep -owE'* ]]; then
  pass "portability: uses POSIX grep -ow whole-word matching"
else
  fail "portability: uses POSIX grep -ow" "present" "missing"
fi

# --- Case: PYTHONUTF8=1 exported before invoking babysit_python (#597) --------
# Matches the convention the scripts/ babysit wrappers already apply
# (source-control-babysit-merge, source-control-babysit-resolve-thread): this
# gate is the third babysit_python caller and the one that parses
# fetch-all-pr-comments.sh-shaped JSON, which commonly carries non-ASCII bytes
# (bot badges, reaction emoji) that choke a Python code path relying on the
# interpreter's default I/O encoding on Windows (cp1252) instead of pinning
# encoding="utf-8" itself.
if [[ "$GATE_BODY" == *'export PYTHONUTF8=1'* ]]; then
  pass "#597: exports PYTHONUTF8=1"
else
  fail "#597: exports PYTHONUTF8=1" "present" "missing"
fi

F=$(mkjson adjacent '[
  {author:"claude[bot]", body:"CRITICAL IMPORTANT both flagged"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "adjacent words -> findings=2" "$r" "findings=2"

F=$(mkjson prose-repeat '[
  {author:"claude[bot]", body:"CRITICAL one. IMPORTANT two."},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\nThe claim is VALID because the code confirms it. VALID indeed."}
]')
r=$(run_gate "$F")
assert_contains "prose repetition -> classified=1" "$r" "classified=1"
assert_contains "prose repetition under-decomposed -> blocked" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "prose repetition -> exit 1" "$r" "EXIT:1"

F=$(mkjson self-row-severity '[
  {author:"claude[bot]", body:"CRITICAL null deref in handler"},
  {author:"me[bot]", body:"| 1 | CRITICAL: null deref | VALID | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "self classification row repeating severity -> findings=1" "$r" "findings=1"
assert_contains "self classification row repeating severity -> OK" "$r" "READINESS_OK"

F=$(mkjson lowercase-classify '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | Valid (defer) | noted |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase classification token -> classified=1" "$r" "classified=1"
assert_contains "lowercase classification token -> READINESS_OK" "$r" "READINESS_OK"

F=$(mkjson prose-valid-not-classification '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [CRITICAL] b"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\n| CI check | result is valid |"}
]')
r=$(run_gate "$F")
assert_contains "table prose is not a classification -> classified=1" "$r" "classified=1"
assert_contains "table prose is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson cell-opening-prose '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [CRITICAL] b"},
  {author:"me[bot]", body:"| 1 | comment 1 | VALID | fixed |\n| 2 | comment 2 | Valid cache entries are rejected | | | | |"}
]')
r=$(run_gate "$F")
assert_contains "cell-opening prose is not a classification -> classified=1" "$r" "classified=1"
assert_contains "cell-opening prose is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson word-continuation '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | finding | valid2 | pending |"}
]')
r=$(run_gate "$F")
assert_contains "valid2 is not a classification -> classified=0" "$r" "classified=0"
assert_contains "valid2 is not a classification -> findings=1" "$r" "findings=1"
assert_contains "valid2 is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
F=$(mkjson word-continuation-underscore '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | finding | VALID_TOKEN | pending |"}
]')
r=$(run_gate "$F")
assert_contains "VALID_TOKEN is not a classification -> classified=0" "$r" "classified=0"
assert_contains "VALID_TOKEN is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
F=$(mkjson word-continuation-leading '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | finding | 2valid | pending |"}
]')
r=$(run_gate "$F")
assert_contains "2valid is not a classification -> classified=0" "$r" "classified=0"
assert_contains "2valid is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson documented-dispositions '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [CRITICAL] b\n### 3. [CRITICAL] c"},
  {author:"me[bot]", body:"| 1 | a | VALID — fixing | x |\n| 2 | b | VALID (defer) | y |\n| 3 | c | VALID — fix now | z |"}
]')
r=$(run_gate "$F")
assert_contains "documented dispositions -> classified=3" "$r" "classified=3"
assert_contains "documented dispositions -> READINESS_OK" "$r" "READINESS_OK"

F=$(mkjson bold-classify '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | **VALID** | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "bolded disposition cell -> classified=1" "$r" "classified=1"
assert_contains "bolded disposition cell -> READINESS_OK" "$r" "READINESS_OK"

F=$(mkjson lowercase-invalid '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | invalid claim, no fix needed | noted |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase invalid does not count -> classified=0" "$r" "classified=0"
assert_contains "lowercase invalid -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson self-row-severity-lowercase '[
  {author:"claude[bot]", body:"CRITICAL null deref in handler"},
  {author:"me[bot]", body:"| 1 | CRITICAL: null deref | Valid | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase self classification row repeating severity -> findings=1" "$r" "findings=1"
assert_contains "lowercase self classification row repeating severity -> OK" "$r" "READINESS_OK"

F=$(mkjson plain-pseverity '[
  {author:"some-reviewer[bot]", body:"[P1] null deref in handler\n[P2] missing timeout"},
  {author:"me[bot]", body:"| 1 | null deref | VALID | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "plain [P-num] markers -> findings=2" "$r" "findings=2"
assert_contains "plain [P-num] under-decomposed -> blocked" "$r" "READINESS_BLOCKED reason=under-decomposed"

F=$(mkjson plain-pseverity-out-of-range '[
  {author:"some-reviewer[bot]", body:"Table [P7] shows throughput; appendix [P9] has raw data."}
]')
r=$(run_gate "$F")
assert_contains "out-of-range [P-num] -> findings=0" "$r" "findings=0"
assert_contains "out-of-range [P-num] -> OK" "$r" "READINESS_OK"

# --- Case: #465 lifetime findings in resolved/outdated threads are discounted -
# A severity marker carried in a thread GitHub reports resolved or outdated is a
# lifetime artifact of an already-addressed round, not a live finding. The shared
# Python classifier (babysit_findings.py) discounts it (open-state aware) so a
# fully-classified PR with re-review history does not false-BLOCK. The bash
# degrade cannot see thread state and counts lifetime markers, so this enriched
# behavior is asserted only when a Python 3.11+ interpreter is present -- the same
# path the gate itself prefers. Three lifetime markers, only one open: findings=1.
probe_py() {
  "$@" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)' \
    >/dev/null 2>&1
}

HAVE_PY311=0
if probe_py py -3 || probe_py python3 || probe_py python; then
  HAVE_PY311=1
fi

if ((HAVE_PY311)); then
  PYSTUB_BIN="$TEST_TMPDIR/bin-pystub"
  mkdir -p "$PYSTUB_BIN"
  PYUTF8_PROBE_FILE="$TEST_TMPDIR/pyutf8-probe.txt"
  export PYUTF8_PROBE_FILE
  cat >"$PYSTUB_BIN/py" <<'STUB'
#!/usr/bin/env bash
args=("$@")
for a in "${args[@]}"; do
  if [[ "$a" == "-c" ]]; then
    exit 0 # version probe
  fi
done
printf '%s' "${PYTHONUTF8:-unset}" >"$PYUTF8_PROBE_FILE"
printf 'findings=0 classified=0\n'
STUB
  chmod +x "$PYSTUB_BIN/py"
  F=$(mkjson pyutf8-probe-fixture '[{author:"claude[bot]", body:"no findings here"}]')
  PATH="$PYSTUB_BIN:$PATH" bash "$GATE" 123 --comments-json "$F" --self 'me[bot]' >/dev/null 2>&1
  probe_seen="$(cat "$PYUTF8_PROBE_FILE" 2>/dev/null || echo "missing")"
  assert_eq "#597: child process inherits PYTHONUTF8=1" "1" "$probe_seen"
  unset PYUTF8_PROBE_FILE
else
  pass "#597: PYTHONUTF8 child-inheritance probe skipped (no Python 3.11+)"
fi

if ((HAVE_PY311)); then
  F=$(mkjson lifetime-open '[
    {author:"codex[bot]", body:"[CRITICAL] resolved earlier", isResolved:true},
    {author:"codex[bot]", body:"[CRITICAL] outdated round", isOutdated:true},
    {author:"codex[bot]", body:"[P1] still open null deref"},
    {author:"me[bot]", body:"| 1 | null deref | VALID | fixed abc123 |"}
  ]')
  r=$(run_gate "$F")
  assert_contains "#465 lifetime discount -> findings=1 (only open)" "$r" "findings=1"
  assert_contains "#465 lifetime discount -> READINESS_OK" "$r" "READINESS_OK"
else
  pass "#465 lifetime discount skipped (no Python 3.11+; bash degrade counts lifetime)"
fi

if ((HAVE_PY311)); then
  F=$(mkjson stale-pr-classification '[
    {author:"codex[bot]", body:"[CRITICAL] fresh unclassified finding", in_review_thread:true},
    {author:"me[bot]", body:"| 1 | old resolved finding | VALID | fixed |"}
  ]')
  r=$(run_gate "$F")
  assert_contains "#642 stale PR-level row -> classified=0 (no cross-surface credit)" "$r" "findings=1 classified=0"
  assert_contains "#642 stale PR-level row -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
else
  pass "#642 per-surface credit skipped (no Python 3.11+; bash degrade is thread-blind)"
fi

if ((HAVE_PY311)); then
  F=$(mkjson reuse-inline-type '[
    {type:"inline", author:"codex[bot]", body:"[CRITICAL] inline finding"},
    {type:"review", author:"me[bot]", body:"| 1 | old | VALID | fixed |"}
  ]')
  r=$(run_gate "$F")
  assert_contains "#642 reuse-path inline tag -> classified=0" "$r" "findings=1 classified=0"
  assert_contains "#642 reuse-path inline tag -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
else
  pass "#642 reuse-path inline tag skipped (no Python 3.11+; bash degrade is thread-blind)"
fi

if ((HAVE_PY311)); then
  F=$(mkjson unsignaled-provenance '[
    {author:"codex[bot]", body:"[CRITICAL] unsignaled finding"},
    {type:"review", author:"me[bot]", body:"| 1 | x | VALID | y |"}
  ]')
  r=$(run_gate "$F")
  assert_contains "#642 unsignaled finding -> classified=0" "$r" "findings=1 classified=0"
  assert_contains "#642 unsignaled finding -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
else
  pass "#642 unsignaled-provenance isolation skipped (no Python 3.11+)"
fi

gate_counts() {
  bash "$GATE" 123 --comments-json "$1" --self 'me[bot]' 2>/dev/null |
    grep -oE 'findings=[0-9]+ classified=[0-9]+'
}
converge() {
  local py bash_only
  py="$(gate_counts "$2")"
  bash_only="$(BABYSIT_READINESS_BASH_ONLY=1 gate_counts "$2")"
  if [[ -n "$py" && "$py" == "$bash_only" ]]; then
    pass "convergence [$1]: python == bash degrade ($py)"
  else
    fail "convergence [$1]: python == bash degrade" "$py" "$bash_only"
  fi
}
F=$(mkjson conv-words '[
  {author:"claude[bot]", body:"CRITICAL a and IMPORTANT b on one line\nSUGGESTION c"},
  {author:"me[bot]", body:"| 1 | a | VALID | x |"}
]')
converge "severity-words" "$F"
F=$(mkjson conv-badge '[
  {author:"chatgpt-codex-connector[bot]", body:"![P1 Badge](https://img.shields.io/badge/P1-red?style=flat) and ![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)"},
  {author:"me[bot]", body:"| 1 | x | VALID | y |"}
]')
converge "codex-badges" "$F"
F=$(mkjson conv-plain '[
  {author:"some-reviewer[bot]", body:"[P1] null deref\n[P2] missing timeout"},
  {author:"me[bot]", body:"| 1 | null deref | VALID | fixed |"}
]')
converge "plain-p-markers" "$F"
F=$(mkjson conv-selfrow '[
  {author:"claude[bot]", body:"CRITICAL null deref in handler"},
  {author:"me[bot]", body:"| 1 | CRITICAL: null deref | VALID | fixed abc123 |"}
]')
converge "self-row-exclusion" "$F"
F=$(mkjson conv-overclassified '[
  {author:"claude[bot]", body:"CRITICAL a"},
  {author:"me[bot]", body:"| 1 | a | VALID | x |\n| 2 | spurious | INCORRECT | y |"}
]')
converge "over-classified-cap" "$F"
F=$(mkjson conv-lowercase '[
  {author:"claude[bot]", body:"CRITICAL a"},
  {author:"me[bot]", body:"| 1 | a | Valid (defer) | x |"}
]')
converge "lowercase-classify" "$F"
F=$(mkjson conv-prose-valid '[
  {author:"claude[bot]", body:"CRITICAL a\nCRITICAL b"},
  {author:"me[bot]", body:"| 1 | a | VALID | x |\n| CI check | result is valid |"}
]')
converge "prose-valid-not-classification" "$F"
F=$(mkjson conv-cell-opening-prose '[
  {author:"claude[bot]", body:"CRITICAL a\nCRITICAL b"},
  {author:"me[bot]", body:"| 1 | c1 | VALID | x |\n| 2 | c2 | Valid cache entries are rejected | | | | |"}
]')
converge "cell-opening-prose" "$F"
F=$(mkjson conv-word-continuation '[
  {author:"claude[bot]", body:"CRITICAL a"},
  {author:"me[bot]", body:"| 1 | finding | valid2 | pending |"}
]')
converge "word-continuation" "$F"
F=$(mkjson conv-documented '[
  {author:"claude[bot]", body:"CRITICAL a\nCRITICAL b"},
  {author:"me[bot]", body:"| 1 | a | VALID — fixing | x |\n| 2 | b | Valid (defer) | y |"}
]')
converge "documented-dispositions" "$F"

NOREPO_BIN="$TEST_TMPDIR/bin-norepo"
mkdir -p "$NOREPO_BIN"
cat >"$NOREPO_BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) printf '' ;;
  *) printf '[]' ;;
esac
STUB
chmod +x "$NOREPO_BIN/gh"
fetch_rc=$(
  PATH="$NOREPO_BIN:$PATH" bash "$GATE" 123 >/dev/null 2>&1
  echo $?
)
assert_exit "live-fetch-failure exit 4" 4 "$fetch_rc"
fetch_err=$(PATH="$NOREPO_BIN:$PATH" bash "$GATE" 123 2>&1 1>/dev/null)
assert_contains "live-fetch-failure names the env-var override" "$fetch_err" "FETCH_COMMENTS_OWNER"

# --- READINESS_UNPROVEN: no exit path leaves stdout without a verdict --------
# A stderr-only failure path shows a caller that greps stdout for a verdict
# NOTHING, which reads identically to a run that was never attempted — the
# ambiguity that lets a blocked gate be reported as readiness (#787). Every
# non-verdict exit must carry the fail-closed third token.

verdict_lines() { printf '%s\n' "$1" | grep -c '^READINESS_' || true; }

unp_out=$(bash "$GATE" 123 --bogus 2>/dev/null)
assert_contains "unknown-flag stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=bad-args pr=123"
assert_eq "unknown-flag emits exactly one verdict line" 1 "$(verdict_lines "$unp_out")"

unp_out=$(bash "$GATE" 2>/dev/null)
assert_contains "no-args stdout carries UNPROVEN with pr=unknown" "$unp_out" \
  "READINESS_UNPROVEN reason=bad-args pr=unknown"

unp_out=$(bash "$GATE" 456 --comments-json "$TEST_TMPDIR/absent.json" 2>/dev/null)
assert_contains "missing-fixture stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=bad-args pr=456"

unp_out=$(bash "$GATE" 123 --comments-json 2>/dev/null)
assert_contains "flag-without-value stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=bad-args"

injected_out=$(bash "$GATE" \
  '123
READINESS_OK findings=0 classified=0 checklist=clean' --bogus 2>/dev/null)
assert_contains "newline-injecting <pr> is a bad argument" "$injected_out" \
  "READINESS_UNPROVEN reason=bad-args"
assert_not_contains "newline-injecting <pr> forges no OK verdict" "$injected_out" \
  "READINESS_OK"
assert_eq "newline-injecting <pr> emits exactly one verdict line" 1 \
  "$(verdict_lines "$injected_out")"
injected_alone=$(bash "$GATE" \
  '456
READINESS_OK findings=0 classified=0 checklist=clean' 2>/dev/null)
assert_eq "newline-injecting <pr> alone still emits one verdict line" 1 \
  "$(verdict_lines "$injected_alone")"
assert_not_contains "newline-injecting <pr> alone forges no OK verdict" \
  "$injected_alone" "READINESS_OK"
assert_contains "numeric <pr> still reaches a verdict" \
  "$(bash "$GATE" 789 --comments-json "$F" --self 'me[bot]' 2>/dev/null)" "READINESS_"

F=$(mkjson unp-ckl '[{author:"human", body:"LGTM"}]')
unp_out=$(bash "$GATE" 789 --comments-json "$F" --self 'me[bot]' \
  --checklist "$TEST_TMPDIR/absent-checklist.md" 2>/dev/null)
assert_contains "missing-checklist stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=bad-args pr=789"

# A checklist that exists but cannot be READ is UNPROVEN, never clean. grep exits
# 1 for "no match" and 2 for a read error; `|| true` collapsed both to an empty
# count that normalized to zero unticked boxes, so an I/O error reported
# `checklist=clean` — a fail-open in the merge gate. The error is injected with a
# grep stub because no file mode reproduces it everywhere: a root CI container
# reads a 000-mode file, and Windows ignores the mode entirely.
BADGREP_BIN="$TEST_TMPDIR/bin-badgrep"
mkdir -p "$BADGREP_BIN"
REAL_GREP=$(command -v grep)
cat >"$BADGREP_BIN/grep" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *unreadable-checklist.md*)
    printf 'grep: unreadable-checklist.md: Input/output error\n' >&2
    exit 2
    ;;
esac
exec "$REAL_GREP" "\$@"
STUB
chmod +x "$BADGREP_BIN/grep"
CKU="$TEST_TMPDIR/unreadable-checklist.md"
printf -- '- [x] done\n' >"$CKU"
unp_out=$(PATH="$BADGREP_BIN:$PATH" bash "$GATE" 790 --comments-json "$F" --self 'me[bot]' \
  --checklist "$CKU" 2>/dev/null)
assert_contains "unreadable-checklist stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=checklist-unreadable pr=790"
assert_contains "unreadable-checklist never claims readiness" "$unp_out" "READINESS_UNPROVEN"
assert_eq "unreadable-checklist emits exactly one verdict line" 1 "$(verdict_lines "$unp_out")"
unp_rc=$(
  PATH="$BADGREP_BIN:$PATH" bash "$GATE" 790 --comments-json "$F" --self 'me[bot]' \
    --checklist "$CKU" >/dev/null 2>&1
  echo $?
)
assert_exit "unreadable-checklist exit 4" 4 "$unp_rc"
ok_out=$(PATH="$BADGREP_BIN:$PATH" bash "$GATE" 791 --comments-json "$F" --self 'me[bot]' \
  --checklist "$CK2" 2>/dev/null)
assert_contains "badgrep stub leaves a readable checklist clean" "$ok_out" "checklist=clean"

# The jq prerequisite is asserted at the source, not by nuking PATH: a PATH that
# hides jq also hides the interpreter (both live in the same bin dir on the CI
# image), so the subprocess would report its own 127 rather than the gate's
# verdict. Assert instead that the jq check routes through unproven — the same
# source-level contract style as the POSIX-matching assertion above.
assert_contains "jq prerequisite emits UNPROVEN prereq-missing" "$GATE_BODY" \
  "unproven prereq-missing 4"
bare_exits=$(grep -cE '^[[:space:]]*exit [34]$' "$GATE" || true)
assert_eq "no bare exit 3/4 survives (every failure path emits a verdict)" 0 \
  "${bare_exits//[^0-9]/}"

unp_out=$(PATH="$NOREPO_BIN:$PATH" bash "$GATE" 123 2>/dev/null)
assert_contains "live-fetch-failure stdout carries UNPROVEN" "$unp_out" \
  "READINESS_UNPROVEN reason=fetch-failed pr=123"

printf 'not-json' >"$TEST_TMPDIR/malformed.json"
bad_out=$(bash "$GATE" 321 --comments-json "$TEST_TMPDIR/malformed.json" --self 'me[bot]' 2>/dev/null)
bad_rc=$(
  bash "$GATE" 321 --comments-json "$TEST_TMPDIR/malformed.json" --self 'me[bot]' >/dev/null 2>&1
  echo $?
)
assert_contains "malformed snapshot carries UNPROVEN" "$bad_out" \
  "READINESS_UNPROVEN reason=comments-unreadable pr=321"
assert_not_contains "malformed snapshot never claims READINESS_OK" "$bad_out" "READINESS_OK"
assert_exit "malformed snapshot exit 4" 4 "$bad_rc"

for shape in '"a string"' '{"author":"x"}' '42'; do
  printf '%s' "$shape" >"$TEST_TMPDIR/shape.json"
  shape_out=$(bash "$GATE" 322 --comments-json "$TEST_TMPDIR/shape.json" --self 'me[bot]' 2>/dev/null)
  assert_contains "non-array payload ($shape) carries UNPROVEN" "$shape_out" \
    "READINESS_UNPROVEN reason=comments-unreadable"
  assert_not_contains "non-array payload ($shape) never claims READINESS_OK" \
    "$shape_out" "READINESS_OK"
done

for element in '[null]' '[{}]' '[{"author":"x"}]' '[{"body":"[P1] real"}]' \
  '[{"author":"x","body":42}]' \
  '[{"author":"x","body":"ok"},null]'; do
  printf '%s' "$element" >"$TEST_TMPDIR/element.json"
  element_out=$(bash "$GATE" 323 --comments-json "$TEST_TMPDIR/element.json" --self 'me[bot]' 2>/dev/null)
  element_rc=$(
    bash "$GATE" 323 --comments-json "$TEST_TMPDIR/element.json" --self 'me[bot]' >/dev/null 2>&1
    echo $?
  )
  assert_contains "malformed element ($element) carries UNPROVEN" "$element_out" \
    "READINESS_UNPROVEN reason=comments-unreadable"
  assert_not_contains "malformed element ($element) never claims READINESS_OK" \
    "$element_out" "READINESS_OK"
  assert_exit "malformed element ($element) exit 4" 4 "$element_rc"
done

for wellformed in '[]' '[{"author":"me[bot]","body":""}]'; do
  printf '%s' "$wellformed" >"$TEST_TMPDIR/wellformed.json"
  wellformed_out=$(bash "$GATE" 324 --comments-json "$TEST_TMPDIR/wellformed.json" --self 'me[bot]' 2>/dev/null)
  assert_contains "well-formed payload ($wellformed) still reaches a verdict" \
    "$wellformed_out" "READINESS_OK findings=0"
done

BADCAT_BIN="$TEST_TMPDIR/bin-badcat"
mkdir -p "$BADCAT_BIN"
REAL_CAT=$(command -v cat)
cat >"$BADCAT_BIN/cat" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *truncated-read.json*)
    printf '[]'
    exit 1
    ;;
esac
exec "$REAL_CAT" "\$@"
STUB
chmod +x "$BADCAT_BIN/cat"
CKT="$TEST_TMPDIR/truncated-read.json"
printf '%s' '[{"author":"claude[bot]","body":"[P1] real"}]' >"$CKT"
truncated_out=$(PATH="$BADCAT_BIN:$PATH" bash "$GATE" 327 --comments-json "$CKT" --self 'me[bot]' 2>/dev/null)
truncated_rc=$(
  PATH="$BADCAT_BIN:$PATH" bash "$GATE" 327 --comments-json "$CKT" --self 'me[bot]' >/dev/null 2>&1
  echo $?
)
assert_contains "failed snapshot read carries UNPROVEN" "$truncated_out" \
  "READINESS_UNPROVEN reason=comments-unreadable"
assert_not_contains "failed snapshot read never claims READINESS_OK" "$truncated_out" \
  "READINESS_OK"
assert_exit "failed snapshot read exit 4" 4 "$truncated_rc"
bashonly_out=$(BABYSIT_READINESS_BASH_ONLY=1 PATH="$BADCAT_BIN:$PATH" \
  bash "$GATE" 329 --comments-json "$CKT" --self 'me[bot]' 2>/dev/null)
assert_contains "failed snapshot read is UNPROVEN on the degrade path too" \
  "$bashonly_out" "READINESS_UNPROVEN reason=comments-unreadable"
assert_not_contains "failed snapshot read never reads as zero findings" \
  "$bashonly_out" "READINESS_OK findings=0"
CKR="$TEST_TMPDIR/readable-read.json"
printf '%s' '[{"author":"me[bot]","body":"no findings"}]' >"$CKR"
readable_out=$(PATH="$BADCAT_BIN:$PATH" bash "$GATE" 328 --comments-json "$CKR" --self 'me[bot]' 2>/dev/null)
assert_not_contains "badcat stub leaves a readable snapshot alone" "$readable_out" \
  "READINESS_UNPROVEN"

printf '%s' '[{"author":null,"body":"[P1] real"}]' >"$TEST_TMPDIR/null-author.json"
null_author_out=$(bash "$GATE" 325 --comments-json "$TEST_TMPDIR/null-author.json" --self 'me[bot]' 2>/dev/null)
assert_not_contains "deleted-account author is not unreadable" "$null_author_out" \
  "READINESS_UNPROVEN"
assert_contains "deleted-account comment counts as a non-self finding" \
  "$null_author_out" "findings=1"
assert_contains "deleted-account finding still gates on classification" \
  "$null_author_out" "READINESS_BLOCKED reason=under-decomposed"
printf '%s' '[{"author":"claude[bot]","body":"[P1] real"},{"author":null,"body":"| 1 | a | VALID | x |"}]' \
  >"$TEST_TMPDIR/null-author-selfrow.json"
null_self_out=$(bash "$GATE" 326 --comments-json "$TEST_TMPDIR/null-author-selfrow.json" --self 'me[bot]' 2>/dev/null)
assert_contains "null author is never credited as a self classification row" \
  "$null_self_out" "READINESS_BLOCKED reason=under-decomposed"

NOAUTH_BIN="$TEST_TMPDIR/bin-noauth"
mkdir -p "$NOAUTH_BIN"
cat >"$NOAUTH_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh: authentication required\n' >&2
exit 1
STUB
chmod +x "$NOAUTH_BIN/gh"
F=$(mkjson unp-identity '[{author:"human", body:"LGTM"}]')
ident_out=$(PATH="$NOAUTH_BIN:$PATH" bash "$GATE" 654 --comments-json "$F" 2>/dev/null)
ident_rc=$(
  PATH="$NOAUTH_BIN:$PATH" bash "$GATE" 654 --comments-json "$F" >/dev/null 2>&1
  echo $?
)
assert_contains "identity-lookup failure carries its own reason" "$ident_out" \
  "READINESS_UNPROVEN reason=identity-unresolved pr=654"
assert_not_contains "identity-lookup failure is not reported as bad-args" "$ident_out" \
  "reason=bad-args"
assert_exit "identity-lookup failure keeps exit 3" 3 "$ident_rc"

F=$(mkjson unp-ok '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
ok_out=$(bash "$GATE" 123 --comments-json "$F" --self 'me[bot]' 2>/dev/null)
assert_eq "READINESS_OK emits exactly one verdict line" 1 "$(verdict_lines "$ok_out")"
assert_not_contains "READINESS_OK never claims UNPROVEN" "$ok_out" "READINESS_UNPROVEN"

F=$(mkjson unp-blocked '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [IMPORTANT] b"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
blocked_out=$(bash "$GATE" 123 --comments-json "$F" --self 'me[bot]' 2>/dev/null)
assert_eq "READINESS_BLOCKED emits exactly one verdict line" 1 "$(verdict_lines "$blocked_out")"
assert_not_contains "READINESS_BLOCKED never claims UNPROVEN" "$blocked_out" "READINESS_UNPROVEN"

assert_contains "--help documents READINESS_UNPROVEN" "$help_out" "READINESS_UNPROVEN"

help_verdicts=$(verdict_lines "$help_out")
assert_eq "--help emits no verdict line" 0 "$help_verdicts"

assert_contains "--help still reaches the end of the header" "$help_out" \
  "reason=prereq-missing|fetch-failed|comments-unreadable"
assert_not_contains "--help never spills code past the header" "$help_out" \
  "set -uo pipefail"

[[ $FAILED -eq 0 ]] || exit 1
