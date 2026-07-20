#!/usr/bin/env bash
# Regression tests for babysit-readiness-gate.sh.
# Black-box: feed fixture comment JSON via --comments-json, control self authors
# via --self (no network). Asserts the decomposition + checklist verdicts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/babysit-readiness-gate.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test-helpers.sh"

# run_gate <fixture-json> [extra args...] — emits stdout then "EXIT:<code>".
run_gate() {
  local fixture="$1"
  shift
  local out
  out=$(bash "$GATE" 123 --comments-json "$fixture" --self 'me[bot]' "$@" 2>/dev/null)
  local code=$?
  printf '%s\nEXIT:%s' "$out" "$code"
}

mkjson() { # mkjson <name> <jq-array-expr>
  local f="$TEST_TMPDIR/$1.json"
  jq -n "$2" >"$f"
  printf '%s' "$f"
}

# --- Case: --help ---
help_out=$(bash "$GATE" --help 2>&1)
assert_exit "--help exit 0" 0 "$?"
assert_contains "--help describes the gate" "$help_out" "readiness pre-gate"

# --- Case: unknown flag ---
bash "$GATE" 123 --bogus >/dev/null 2>&1
assert_exit "unknown flag exit 3" 3 "$?"

# --- Case: no pr + no comments-json ---
bash "$GATE" >/dev/null 2>&1
assert_exit "no args exit 3" 3 "$?"

# --- Case: under-decomposed (three findings, one classification) ---
F=$(mkjson under '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [IMPORTANT] b\n### 3. [SUGGESTION] c"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "under -> BLOCKED under-decomposed" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "under findings=3" "$r" "findings=3"
assert_contains "under classified=1" "$r" "classified=1"
assert_contains "under exit 1" "$r" "EXIT:1"

# --- Case: fully decomposed (2 findings, 2 classifications) ---
F=$(mkjson ok '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [IMPORTANT] b"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\n| 2 | b | INCORRECT | refuted |"}
]')
r=$(run_gate "$F")
assert_contains "ok -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "ok findings=2 classified=2" "$r" "findings=2 classified=2"
assert_contains "ok exit 0" "$r" "EXIT:0"

# --- Case: zero findings (nothing to decompose) ---
F=$(mkjson empty '[
  {author:"human", body:"LGTM, nice work"},
  {author:"me[bot]", body:"thanks"}
]')
r=$(run_gate "$F")
assert_contains "zero-findings -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "zero-findings findings=0" "$r" "findings=0"
assert_contains "zero-findings exit 0" "$r" "EXIT:0"

# --- Case: checklist incomplete (decomposed, but unticked box) ---
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

# --- Case: checklist clean ---
CK2="$TEST_TMPDIR/checklist-clean.md"
printf -- '- [x] done\n- [x] also done\n' >"$CK2"
r=$(run_gate "$F" --checklist "$CK2")
assert_contains "checklist-clean -> READINESS_OK" "$r" "READINESS_OK"
assert_contains "checklist-clean state" "$r" "checklist=clean"
assert_contains "checklist-clean exit 0" "$r" "EXIT:0"

# --- Case: two findings on ONE line count as 2, not 1 (occurrence counting) --
# Old `grep -cE` counted the line once (findings=1) and false-passed; occurrence
# counting reports findings=2, correctly BLOCKING when only 1 is classified.
F=$(mkjson multiline '[
  {author:"claude[bot]", body:"CRITICAL: fix null check AND IMPORTANT: add validation"},
  {author:"me[bot]", body:"| 1 | null check | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "one-line-two-findings -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "one-line-two-findings findings=2" "$r" "findings=2"

# --- Case: priority labels / lowercase / INVALID are NOT counted ---
# "P0" (dropped from SEVERITY_RE), "p0-critical" (lowercase, RE is case-sensitive)
# and "INVALID" (word-boundary) must all count as zero — old regex false-counted.
F=$(mkjson nofalsepos '[
  {author:"human", body:"P0 blocker on priority:p0-critical, prior call was INVALID"},
  {author:"me[bot]", body:"acknowledged"}
]')
r=$(run_gate "$F")
assert_contains "no-false-positive findings=0" "$r" "findings=0"
assert_contains "no-false-positive -> READINESS_OK" "$r" "READINESS_OK"

# --- Case: codex P-severity findings ARE counted ---------------------------
# Codex marks findings with P1/P2/P3 shields.io badges, not CRITICAL/IMPORTANT/
# SUGGESTION. Dropping P[0-3] entirely blinded the gate to codex-only findings
# (findings=0 -> false READINESS_OK). Keying on the shield-URL `/badge/PN-`
# counts each once without re-matching lowercase priority:p0-critical labels.
# Two real badges (with URLs) -> 2. Uses the production badge markdown.
F=$(mkjson codexfmt '[
  {author:"chatgpt-codex-connector[bot]", body:"![P1 Badge](https://img.shields.io/badge/P1-red?style=flat) Count findings AND ![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat) validate port"},
  {author:"me[bot]", body:"| 1 | count | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "codex P-severity -> BLOCKED (findings counted)" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "codex P-severity findings=2" "$r" "findings=2"

# --- Case: ONE codex badge counts ONCE ---------------------------------------
# Real codex badge markdown carries the severity token twice: alt-text
# `![P2 Badge]` AND shield URL `/badge/P2-yellow`. A bare `P[1-3]` regex counted
# both -> findings=2 for ONE finding -> gate stayed BLOCKED after the single
# finding was classified. Keying on the shield-URL `/badge/PN-` counts it once.
F=$(mkjson codexbadgeurl '[
  {author:"chatgpt-codex-connector[bot]", body:"**<sub><sub>![P2 Badge](https://img.shields.io/badge/P2-yellow?style=flat)</sub></sub> Propagate failed restarts**"},
  {author:"me[bot]", body:"| 1 | propagate | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "codex-badge-with-url findings=1 (not double-counted)" "$r" "findings=1"
assert_contains "codex-badge-with-url -> READINESS_OK" "$r" "READINESS_OK"

# --- Case: codex P0 badge IS counted -----------------------------------------
# P0 was excluded under the old bare-P[1-3] / alt-text approach to avoid matching
# lowercase priority:p0-critical labels. The shield-URL form `/badge/P0-` is
# unambiguous, so a codex P0 finding must count — else an unclassified P0
# false-passes the gate.
F=$(mkjson codexp0 '[
  {author:"chatgpt-codex-connector[bot]", body:"**<sub><sub>![P0 Badge](https://img.shields.io/badge/P0-red?style=flat)</sub></sub> Critical finding**"},
  {author:"me[bot]", body:"acknowledged, investigating"}
]')
r=$(run_gate "$F")
assert_contains "codex-P0 findings=1 (counted, not dropped)" "$r" "findings=1"
assert_contains "codex-P0 unclassified -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

# --- Case: lowercase priority:p0-critical still does NOT false-count ----------
# The URL form `/badge/P0-` must not match a lowercase priority label.
F=$(mkjson p0label '[
  {author:"human", body:"this is priority:p0-critical per our triage"},
  {author:"me[bot]", body:"noted"}
]')
r=$(run_gate "$F")
assert_contains "p0-label findings=0 (no false-count)" "$r" "findings=0"

# --- Case: self-authored SOURCE finding IS counted ---------------------------
# In interactive runs SELF includes the gh user; a self-authored FINDING (a
# severity, not a classification reply) must still count — else it false-passes
# the gate. me[bot] is in SELF, so under the old non-self-only count this CRITICAL
# was dropped (findings=0 -> READINESS_OK); counting over ALL bodies catches it.
F=$(mkjson selffinding '[
  {author:"me[bot]", body:"### 1. [CRITICAL] a self-authored source finding"},
  {author:"human", body:"ack"}
]')
r=$(run_gate "$F")
assert_contains "self-finding counted -> findings=1" "$r" "findings=1"
assert_contains "self-finding unclassified -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

# --- Case: self CLASSIFICATION reply does NOT inflate findings ----------------
# A self classification reply carries VALID/INCORRECT/UNCERTAIN, not a severity,
# so counting findings over ALL bodies must not turn it into a finding.
F=$(mkjson selfclass '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "self-classification not a finding -> findings=1" "$r" "findings=1"
assert_contains "self-classification -> READINESS_OK" "$r" "READINESS_OK"

# --- Case: --comments-json without an argument -> exit 3 ---------------------
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

# --- Case: adjacent severity words BOTH count (whole-word, no shared-boundary loss) -
# `grep -ow` matches each word even when adjacent; an alternation-boundary regex
# (^|[^w])WORD([^w]|$) would consume the shared space and undercount.
F=$(mkjson adjacent '[
  {author:"claude[bot]", body:"CRITICAL IMPORTANT both flagged"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "adjacent words -> findings=2" "$r" "findings=2"

# --- Case: prose classification repetition must NOT inflate the count --------
# A single self reply that repeats a token in prose ("VALID — ... is valid ...
# VALID") is NOT per-finding table rows; only `|`-prefixed table lines count,
# one per line (codex r3564093178). Two findings + one table row + prose
# repetition => classified=1, BLOCKED.
F=$(mkjson prose-repeat '[
  {author:"claude[bot]", body:"CRITICAL one. IMPORTANT two."},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\nThe claim is VALID because the code confirms it. VALID indeed."}
]')
r=$(run_gate "$F")
assert_contains "prose repetition -> classified=1" "$r" "classified=1"
assert_contains "prose repetition under-decomposed -> blocked" "$r" "READINESS_BLOCKED reason=under-decomposed"
assert_contains "prose repetition -> exit 1" "$r" "EXIT:1"

# --- Case: self classification row repeating the severity word is NOT a finding
# `| 1 | CRITICAL: null deref | VALID | ... |` must not mint a phantom source
# finding (would yield findings=2 classified=1 -> permanently blocked) —
# codex r3564159124. One source finding + one classification row => OK.
F=$(mkjson self-row-severity '[
  {author:"claude[bot]", body:"CRITICAL null deref in handler"},
  {author:"me[bot]", body:"| 1 | CRITICAL: null deref | VALID | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "self classification row repeating severity -> findings=1" "$r" "findings=1"
assert_contains "self classification row repeating severity -> OK" "$r" "READINESS_OK"

# --- Case: plain bracketed [P1]/[P2] severity markers count as findings ------
# Reviewers that emit neither a severity word nor a shields badge use bare
# `[P1]` markers — the gate must not report findings=0 for them
# (codex r3564558962). Two plain markers, one classification row => BLOCKED.
F=$(mkjson plain-pseverity '[
  {author:"some-reviewer[bot]", body:"[P1] null deref in handler\n[P2] missing timeout"},
  {author:"me[bot]", body:"| 1 | null deref | VALID | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "plain [P-num] markers -> findings=2" "$r" "findings=2"
assert_contains "plain [P-num] under-decomposed -> blocked" "$r" "READINESS_BLOCKED reason=under-decomposed"

# --- Case: [P4]+ outside the documented P0-P3 range never counts -------------
# Incidental bracketed tokens like a "[P7]" section label are not severity
# markers from any documented reviewer; counting them would false-BLOCK an
# otherwise clean PR.
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
# fully-classified PR with re-review history no longer false-BLOCKs. The bash
# degrade cannot see thread state and counts lifetime markers, so this enriched
# behavior is asserted only when a Python 3.11+ interpreter is present -- the same
# path the gate itself prefers. Three lifetime markers, only one open: findings=1.
probe_py() {
  "$@" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)' \
    >/dev/null 2>&1
}
if probe_py py -3 || probe_py python3 || probe_py python; then
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

# --- Case: #642 stale PR-level classification does NOT cover an open-thread finding
# A classification pipe-row in a PR-level (non-thread) comment can never be
# thread-resolved, so it must not offset a finding raised fresh in an OPEN review
# thread. The Python counter credits classifications per surface, confining the
# stale row to the (empty) PR-level finding bucket -> classified=0 < findings=1
# -> BLOCKED. Thread-aware, so asserted only under Python; the bash degrade is
# reply-thread-blind and false-passes here (the accepted degrade coarseness, same
# as the #465 discount above).
if probe_py py -3 || probe_py python3 || probe_py python; then
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

# --- Convergence: Python counter and bash degrade agree on thread-state-free input
# The gate prefers the shared Python counter but keeps the bash grep counting as
# the Python-free safe-tier degrade. The two must not drift: a severity marker is
# a finding under both, or the safe tier and the engine-backed tier disagree on
# readiness. BABYSIT_READINESS_BASH_ONLY=1 forces the degrade so both counts are
# observable in one run; every representative fixture must yield identical
# `findings=/classified=`. (On a host without Python both runs already take the
# bash path and agree trivially; the assertion still holds.)
gate_counts() { # gate_counts <fixture> -> "findings=N classified=N"
  bash "$GATE" 123 --comments-json "$1" --self 'me[bot]' 2>/dev/null |
    grep -oE 'findings=[0-9]+ classified=[0-9]+'
}
converge() { # converge <name> <fixture>
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
# Over-classified, thread-state-free: the Python per-surface credit collapses to
# min(classified, findings) and the bash degrade's own cap does the same, so both
# report classified=1 for one finding + two rows (#642 cap convergence).
F=$(mkjson conv-overclassified '[
  {author:"claude[bot]", body:"CRITICAL a"},
  {author:"me[bot]", body:"| 1 | a | VALID | x |\n| 2 | spurious | INCORRECT | y |"}
]')
converge "over-classified-cap" "$F"

[[ $FAILED -eq 0 ]] || exit 1
