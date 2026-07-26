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
# --help must surface the owner/repo override so a worker whose cwd is not the
# target repo can fix the fetch-failure exit 4 without trial-and-error.
assert_contains "--help documents the env-var override" "$help_out" "FETCH_COMMENTS_OWNER"

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

# --- Case: PYTHONUTF8=1 exported before invoking babysit_python (#597) --------
# Matches the convention the bin/ babysit wrappers already apply
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

# --- Case: lowercase / natural-language classification token counts (#619) ---
# A worker's classification-table reply that writes a natural-language
# disposition like "Valid (defer)" instead of the mandated all-caps VALID must
# still count as a classification, or the gate reports a false BLOCKED even
# though the finding genuinely was classified.
F=$(mkjson lowercase-classify '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | Valid (defer) | noted |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase classification token -> classified=1" "$r" "classified=1"
assert_contains "lowercase classification token -> READINESS_OK" "$r" "READINESS_OK"

# --- Case: table PROSE containing "valid" is NOT a classification (#619) -----
# The discriminating case for anchoring case-folding to the disposition cell:
# two findings, ONE real disposition row, and an unrelated self-authored table
# row whose prose happens to contain the word "valid". Folding case across the
# whole line would credit that prose row, report classified=2, and let the
# second, genuinely unclassified finding past the under-decomposition gate —
# codex on #1347. The cell anchor must score it classified=1 and BLOCK.
F=$(mkjson prose-valid-not-classification '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a\n### 2. [CRITICAL] b"},
  {author:"me[bot]", body:"| 1 | a | VALID | fixed |\n| CI check | result is valid |"}
]')
r=$(run_gate "$F")
assert_contains "table prose is not a classification -> classified=1" "$r" "classified=1"
assert_contains "table prose is not a classification -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

# --- Case: a decorated disposition cell still counts (#619) -----------------
# The cell anchor permits leading non-letter decoration, so a bolded
# `| **VALID** |` cell — countable before this change under the
# anywhere-in-the-row match — must not silently stop counting.
F=$(mkjson bold-classify '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | **VALID** | fixed |"}
]')
r=$(run_gate "$F")
assert_contains "bolded disposition cell -> classified=1" "$r" "classified=1"
assert_contains "bolded disposition cell -> READINESS_OK" "$r" "READINESS_OK"

# --- Case: lowercase "invalid" in a self row still does NOT count as valid ---
# Case-insensitive matching must stay whole-word: "invalid" must not false-match
# "valid" merely because casing is no longer significant.
F=$(mkjson lowercase-invalid '[
  {author:"claude[bot]", body:"### 1. [CRITICAL] a"},
  {author:"me[bot]", body:"| 1 | a | invalid claim, no fix needed | noted |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase invalid does not count -> classified=0" "$r" "classified=0"
assert_contains "lowercase invalid -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"

# --- Case: lowercase self classification row repeating severity is NOT a finding
# Mirrors the self-row-severity case above but with a natural-language lowercase
# token -- the exclusion regex must also match case-insensitively, or the row
# leaks into the finding corpus and re-counts its own embedded CRITICAL.
F=$(mkjson self-row-severity-lowercase '[
  {author:"claude[bot]", body:"CRITICAL null deref in handler"},
  {author:"me[bot]", body:"| 1 | CRITICAL: null deref | Valid | fixed abc123 |"}
]')
r=$(run_gate "$F")
assert_contains "lowercase self classification row repeating severity -> findings=1" "$r" "findings=1"
assert_contains "lowercase self classification row repeating severity -> OK" "$r" "READINESS_OK"

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

# --- Case: PYTHONUTF8=1 actually reaches the Python child process (#597) ------
# A stubbed `py -3` records the PYTHONUTF8 value it inherited when
# babysit_python execs it, proving the export reaches the child process (not
# just present as dead source text in the static check above).
if probe_py py -3 || probe_py python3 || probe_py python; then
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

# --- Case: #642 reuse path — fetch-all-pr-comments.sh `type` tags are surface-aware
# On `--comments-json` fed fetch-all-pr-comments.sh output, an inline finding is
# tagged `type:"inline"` and a detached PR-level classification `type:"review"`.
# The Python counter buckets by that tag, so the stale review-surface row cannot
# cross-credit the inline finding -> classified=0 < findings=1 -> BLOCKED.
# Thread-aware (tag-driven), so Python-gated; the bash degrade greps all bodies
# and false-passes here, the accepted degrade coarseness.
if probe_py py -3 || probe_py python3 || probe_py python; then
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

# --- Case: #642 fail-closed on unsignalled provenance ------------------------
# A finding bearing neither an `in_review_thread` stamp nor a `type` tag is
# isolated in the unknown bucket, where a PR-level (`type:"review"`)
# classification row cannot offset it -> classified=0 < findings=1 -> BLOCKED.
# Defensive (production paths always signal); Python-gated like the cases above.
if probe_py py -3 || probe_py python3 || probe_py python; then
  F=$(mkjson unsignalled-provenance '[
    {author:"codex[bot]", body:"[CRITICAL] unsignalled finding"},
    {type:"review", author:"me[bot]", body:"| 1 | x | VALID | y |"}
  ]')
  r=$(run_gate "$F")
  assert_contains "#642 unsignalled finding -> classified=0" "$r" "findings=1 classified=0"
  assert_contains "#642 unsignalled finding -> BLOCKED" "$r" "READINESS_BLOCKED reason=under-decomposed"
else
  pass "#642 unsignalled-provenance isolation skipped (no Python 3.11+)"
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
# Lowercase/natural-language classification token (#619): the bash grep -i and
# the Python CLASSIFY_TOKEN_RE/CLASSIFY_ROW_RE re.IGNORECASE must count it
# identically, or the safe-tier degrade and the engine-backed tier disagree on
# readiness for a reply that never uses the mandated all-caps token.
F=$(mkjson conv-lowercase '[
  {author:"claude[bot]", body:"CRITICAL a"},
  {author:"me[bot]", body:"| 1 | a | Valid (defer) | x |"}
]')
converge "lowercase-classify" "$F"
# Table prose carrying "valid" (#619): case-folding is anchored to the
# disposition cell in both paths, so neither may credit a prose row as a
# classification — a divergence here would let the safe-tier degrade pass a PR
# the engine-backed tier blocks (or the reverse).
F=$(mkjson conv-prose-valid '[
  {author:"claude[bot]", body:"CRITICAL a\nCRITICAL b"},
  {author:"me[bot]", body:"| 1 | a | VALID | x |\n| CI check | result is valid |"}
]')
converge "prose-valid-not-classification" "$F"

# --- Case: live fetch failure emits an actionable owner/repo diagnostic ------
# Run WITHOUT --comments-json from a cwd `gh repo view` cannot resolve: the gate's
# fetch shell-out fails, and the gate must exit 4 with stderr naming the
# FETCH_COMMENTS_OWNER/FETCH_COMMENTS_REPO override — not a bare failure line that
# leaves a worker guessing (the exit-4-without-context report this gate fixes).
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

[[ $FAILED -eq 0 ]] || exit 1
