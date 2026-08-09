#!/usr/bin/env bash
# Black-box contract test for check-open-questions.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir. Fixtures
# are minimal ledgers written per case, so a change to the real checklist
# template can never quietly decide a test.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-open-questions.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Write a ledger fixture whose body is the register section, and echo its path.
# The path comes from mktemp, NOT a shell counter: every call site captures this
# function's stdout, so it runs in a subshell and a counter increment would be
# discarded — every fixture would land on one path and later cases would grade
# an earlier case's content.
mkledger() {
  local path
  path="$(mktemp "$TMP/ledger-XXXXXX.md")"
  {
    printf '# /interview Checklist\n\n## Steps\n\n- [x] Step 1\n\n## Open-question register\n\n'
    cat
    printf '\n## Decision tree\n\n- [ ] something\n'
  } >"$path"
  printf '%s' "$path"
}

# expect_exit <label> <want_code> <args...>
expect_exit() {
  local label="$1" want="$2"
  shift 2
  local got
  bash "$SUT" "$@" >/dev/null 2>&1
  got=$?
  if [[ "$got" -eq "$want" ]]; then pass "$label"; else fail "$label (want exit $want, got $got)"; fi
}

# expect_stdout <label> <substring> <args...>
expect_stdout() {
  local label="$1" want="$2"
  shift 2
  local out
  out="$(bash "$SUT" "$@" 2>/dev/null)"
  if [[ "$out" == *"$want"* ]]; then pass "$label"; else fail "$label (stdout: '$out')"; fi
}

# 1. --help exits 0.
if bash "$SUT" --help >/dev/null 2>&1; then pass "--help exits 0"; else fail "--help should exit 0"; fi

# 2. --help prints the usage header, not a truncated fragment.
expect_stdout "--help prints usage" "Usage:" --help

# 3. Missing --ledger -> ungradeable.
expect_exit "no --ledger -> 2" 2

# 4. Nonexistent ledger -> ungradeable.
expect_exit "missing ledger file -> 2" 2 --ledger "$TMP/nope.md"

# 5. Unknown argument -> ungradeable.
clean="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
EOF
)"
expect_exit "unknown arg -> 2" 2 --ledger "$clean" --bogus

# 6. All rows resolved -> clean.
expect_exit "all answered -> 0" 0 --ledger "$clean"
expect_stdout "clean verdict line" "status=clean" --ledger "$clean"

# 7. One open row -> exit 1. This is the reported failure: a question asked,
#    never answered, and the contract locked anyway.
one_open="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q2 | open | round 1 | What content format? |
EOF
)"
expect_exit "one open row -> 1" 1 --ledger "$one_open"
expect_stdout "open verdict counts the open row" "open=1" --ledger "$one_open"

# 8. Mixed terminal statuses all count as resolved.
mixed="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q2 | deferred | round 1 | Moderation? | post-V1
- Q3 | withdrawn | round 2 | Tenant isolation? | pruned by Q1
- Q4 | blocked | round 2 | Retention window? | named blocker
EOF
)"
expect_exit "answered/deferred/withdrawn/blocked -> 0" 0 --ledger "$mixed"
expect_stdout "verdict breaks down statuses" "deferred=1 blocked=1 withdrawn=1 answered=1" --ledger "$mixed"

# 9. No register section -> ungradeable, never a pass. A ledger that simply
#    omits the register must not read as "nothing open".
noreg="$TMP/noregister.md"
printf '# /interview Checklist\n\n## Steps\n\n- [x] Step 1\n' >"$noreg"
expect_exit "no register section -> 2" 2 --ledger "$noreg"
expect_stdout "no register reports ungradeable" "status=ungradeable" --ledger "$noreg"

# 10. Empty register section -> ungradeable for the same reason.
empty="$(
  mkledger <<'EOF'
_No questions asked yet._
EOF
)"
expect_exit "empty register -> 2" 2 --ledger "$empty"

# 11. Unknown status -> ungradeable. A typo'd status must not be counted as
#     resolved by falling through.
badstatus="$(
  mkledger <<'EOF'
- Q1 | pending | round 1 | Who writes? |
EOF
)"
expect_exit "unknown status -> 2" 2 --ledger "$badstatus"

# 12. Malformed row (too few fields) -> ungradeable.
malformed="$(
  mkledger <<'EOF'
- Q1 | answered |
EOF
)"
expect_exit "malformed row -> 2" 2 --ledger "$malformed"

# 13. Duplicate id -> ungradeable.
dup="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q1 | answered | round 2 | Something else | yes
EOF
)"
expect_exit "duplicate id -> 2" 2 --ledger "$dup"

# 14. Non-contiguous ids -> ungradeable. This is the anti-vacuity check: a row
#     deleted after it was written leaves a gap, and a gap must never grade as
#     a clean register.
gap="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q3 | answered | round 1 | What format? | markdown
EOF
)"
expect_exit "gap in Q numbering -> 2" 2 --ledger "$gap"

# 14b. A row that lost its first pipe must exit 2, not vanish. Skipping it
#      silently would hide Q2 from the contiguity check and grade the register
#      clean with a question missing — the failure this gate exists to refuse.
lostpipe="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q2 open | round 1 | Still open? |
EOF
)"
expect_exit "row missing its first pipe -> 2" 2 --ledger "$lostpipe"

# 14c. Prose in the register section that merely starts with `- Q<N>` is also a
#      malformed row, not silently ignorable: fails closed.
prose="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
- Q2 was withdrawn after the tree changed
EOF
)"
expect_exit "prose row starting with Q<N> -> 2" 2 --ledger "$prose"

# 14d. A leading-zero id is malformed, and rejecting it is what keeps the
#      contiguity check total: `[[ 08 -ne 8 ]]` evaluates in arithmetic context,
#      reads 08 as invalid octal, errors, and resolves FALSE — so a gapped
#      register would pass. Fail closed on the form instead.
leadzero="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | a | x
- Q08 | answered | round 1 | b | x
EOF
)"
expect_exit "leading-zero question id -> 2" 2 --ledger "$leadzero"

# 14e. Q0 is malformed: the counter runs from 1.
qzero="$(
  mkledger <<'EOF'
- Q0 | answered | round 1 | a | x
EOF
)"
expect_exit "Q0 -> 2" 2 --ledger "$qzero"

# 15. Case-insensitive status and id.
casey="$(
  mkledger <<'EOF'
- q1 | Answered | round 1 | Who writes? | admin
EOF
)"
expect_exit "case-insensitive id and status -> 0" 0 --ledger "$casey"

# 16. A fenced example inside the register is documentation, not data. Grading
#     it would fail a ledger for quoting its own schema.
fenced="$(
  mkledger <<'EOF'
Row shape:

```text
- Q1 | open | round 1 | <question> |
```

- Q1 | answered | round 1 | Who writes? | admin
EOF
)"
expect_exit "fenced example ignored -> 0" 0 --ledger "$fenced"

# 17. The register section stops at the next heading — a `- Q<N>` line in a
#     later section is not a register row.
bleed="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | Who writes? | admin
EOF
)"
printf -- '- Q9 | open | round 3 | leaked row |\n' >>"$bleed"
expect_exit "rows after the section do not bleed in -> 0" 0 --ledger "$bleed"

# 18. Without --brief the verdict says `unchecked`, never omits the field.
expect_stdout "brief=unchecked when not asked for" "brief=unchecked" --ledger "$clean"

# 19. --brief named but missing -> ungradeable, not a silent downgrade.
expect_exit "named-but-missing --brief -> 2" 2 --ledger "$clean" --brief "$TMP/nobrief.md"

# 20. --brief satisfied: every deferred/blocked id appears in the Brief.
brief_ok="$TMP/plan-ok.md"
cat >"$brief_ok" <<'EOF'
## Brief

### Deferred questions

- Q2 — Moderation model? — defer until post-V1; **arbiter: /planning:plan**
- Q4 — Retention window? — **arbiter: USER-RESERVED**

## Plan
EOF
expect_exit "brief carries every deferred/blocked id -> 0" 0 --ledger "$mixed" --brief "$brief_ok"
expect_stdout "brief=ok when cross-check passes" "brief=ok" --ledger "$mixed" --brief "$brief_ok"

# 21. A deferred row the Brief never records -> ungradeable. Retiring a question
#     in the ledger without landing it in the contract is the same silent hole.
brief_missing="$TMP/plan-missing.md"
cat >"$brief_missing" <<'EOF'
## Brief

### Deferred questions

- Q2 — Moderation model? — defer until post-V1; **arbiter: /planning:plan**

## Plan
EOF
expect_exit "deferred id absent from Brief -> 2" 2 --ledger "$mixed" --brief "$brief_missing"

# 22. A Brief with no deferred-questions section, while the register retires
#     questions -> ungradeable.
brief_nosection="$TMP/plan-nosection.md"
printf '## Brief\n\n### Goal\n\nship it\n' >"$brief_nosection"
expect_exit "no deferred section but rows retired -> 2" 2 --ledger "$mixed" --brief "$brief_nosection"

# 23. A Brief with no deferred-questions section is fine when the register
#     retires nothing.
expect_exit "no deferred section and nothing retired -> 0" 0 --ledger "$clean" --brief "$brief_nosection"

# 24. Q10 must not satisfy a Q1 lookup: the id match is bounded, not a substring.
ten="$(
  mkledger <<'EOF'
- Q1 | answered | round 1 | a | x
- Q2 | answered | round 1 | b | x
- Q3 | answered | round 1 | c | x
- Q4 | answered | round 1 | d | x
- Q5 | answered | round 1 | e | x
- Q6 | answered | round 1 | f | x
- Q7 | answered | round 1 | g | x
- Q8 | answered | round 1 | h | x
- Q9 | answered | round 1 | i | x
- Q10 | deferred | round 2 | j | post-V1
EOF
)"
brief_q1only="$TMP/plan-q1only.md"
cat >"$brief_q1only" <<'EOF'
## Brief

### Deferred questions

- Q1 — a different question entirely
EOF
expect_exit "Q1 in the Brief does not satisfy Q10 -> 2" 2 --ledger "$ten" --brief "$brief_q1only"

# 25. An open row still fails even when the Brief cross-check would pass: the
#     open question is the finding, and a satisfied side-check never overrides it.
open_plus="$(
  mkledger <<'EOF'
- Q1 | open | round 1 | Who writes? |
- Q2 | deferred | round 1 | Moderation? | post-V1
EOF
)"
expect_exit "open row wins over a passing brief check -> 1" 1 --ledger "$open_plus" --brief "$brief_ok"

if [[ "$fails" -ne 0 ]]; then
  printf '\n%d test(s) failed.\n' "$fails" >&2
  exit 1
fi
printf '\nAll check-open-questions.sh tests passed.\n'
