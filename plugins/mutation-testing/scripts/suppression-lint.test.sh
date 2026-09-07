#!/usr/bin/env bash
# Black-box contract test for suppression-lint.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# Every expected `finding_id` below was produced by running the `finding_id`
# snippet published in `skills/audit/context/suppression.md` through Python,
# not by running the script under test. A test whose expectations came from the
# implementation would pass over a wrong recipe, which is the whole class of
# defect this suite exists to catch. The constants and their constituents:
#
#   846675cd2cbd91bd  SBR  arid(kind=log-call)             src/pricing.ts
#   2b9ccfdf16a06d53  ROR  arid(kind=trivial-accessor)     src/zeta.ts + src/alpha.ts
#   bdb157ec775557fa  UOI  arid(kind=metric-emission)      src/metrics.ts at anchor/v2
#   276c895e90c283f0  the same entry derived from its anchor/v1 instead
#   b6a58c5c18aa9e26  ROR  arid(kind=generated-region)     src/B.ts before src/a.ts
#   e4b5f308c11518db  the same entry with the sites in locale order instead
#   b0cdc692ed4e8a74  LCR  arid(kind=debug-repr)           src/render.ts
#   a9bd6eb74943144f  AOR  arid(kind=hard-to-test)         src/slow.ts
#
# Two of those are negative constants. `276c895e90c283f0` is what picking the
# lowest anchor version would produce, and `e4b5f308c11518db` what a locale sort
# of the sites would produce; asserting the entry filed under the byte-sorted,
# greatest-version key reports `ok` is what makes those two rules non-vacuous.
#
# `hard-to-test` is the rejected-kind fixture because the vocabulary table names
# it as explicitly not a kind, so the case is drawn from the contract rather
# than invented.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/suppression-lint.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

last_out=""
run() {
  local expected="$1" label="$2"
  shift 2
  local actual
  last_out="$(bash "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label - expected exit $expected, got $actual: $last_out"
  fi
}

has() {
  if [[ "$last_out" == *"$1"* ]]; then
    pass "$2"
  else
    fail "$2 - output was: $last_out"
  fi
}

lacks() {
  if [[ "$last_out" != *"$1"* ]]; then
    pass "$2"
  else
    fail "$2 - output was: $last_out"
  fi
}

# --- a valid record -----------------------------------------------------------

valid="$WORK/arid.md"
cat >"$valid" <<'RECORD'
# Accepted arid-node suppressions

```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Structured-logging call; the suite asserts on no log emission."
    date: 2026-08-10
  2b9ccfdf16a06d53:
    check: mutation-testing/operator/ROR
    claim: arid(kind=trivial-accessor)
    sites:
      - surface: src/zeta.ts
        anchor/v1: "e:11111111:22222222"
      - surface: src/alpha.ts
        anchor/v1: "e:33333333:44444444"
    reason: "Getter whose body is a bare field read."
    date: 2026-08-11
```
RECORD

run 0 "a valid record passes" "$valid"
has "ok 846675cd2cbd91bd" "the single-site entry reports ok"
has "ok 2b9ccfdf16a06d53" "the two-site entry reports ok"
has "entries=2 ok=2 failed=0" "the summary counts both entries"
lacks "accepted kinds:" "a clean run does not print the vocabulary"

# The sites are written zeta-then-alpha, so an implementation that hashed them
# in file order would miss the key the contract's sorted recipe derives.
run 0 "sites hash in sorted order, not file order" "$valid"

# --- the sort is on encoded bytes, not the locale's collation ------------------

bytesort="$WORK/bytesort.md"
cat >"$bytesort" <<'RECORD'
```yaml
suppressions:
  b6a58c5c18aa9e26:
    check: mutation-testing/operator/ROR
    claim: arid(kind=generated-region)
    sites:
      - surface: src/a.ts
        anchor/v1: "e:0c0c0c0c:0d0d0d0d"
      - surface: src/B.ts
        anchor/v1: "e:0a0a0a0a:0b0b0b0b"
    reason: "Machine-generated block sharing a file with authored code."
    date: 2026-08-13
```
RECORD

run 0 "sites sort on bytes, so src/B.ts precedes src/a.ts" "$bytesort"
has "ok b6a58c5c18aa9e26" "the byte-sorted key is the one derived"
lacks "e4b5f308c11518db" "the locale-sorted key is never derived"

# --- a site carrying several anchor versions uses the greatest ----------------

versions="$WORK/versions.md"
cat >"$versions" <<'RECORD'
```yaml
suppressions:
  bdb157ec775557fa:
    check: mutation-testing/operator/UOI
    claim: arid(kind=metric-emission)
    sites:
      - surface: src/metrics.ts
        anchor/v1: "e:eeeeeeee:11111111"
        anchor/v2: "e:eeeeeeee:ffffffff"
    reason: "Counter increment no consumer asserts on."
    date: 2026-08-12
```
RECORD

run 0 "a multi-version site uses its greatest anchor version" "$versions"
has "ok bdb157ec775557fa" "the v2-derived key is the one compared"
lacks "276c895e90c283f0" "the v1-derived key is never derived"

# --- a wrong hash --------------------------------------------------------------

wrong="$WORK/wrong-hash.md"
cat >"$wrong" <<'RECORD'
```yaml
suppressions:
  0000000000000000:
    check: mutation-testing/operator/LCR
    claim: arid(kind=debug-repr)
    sites:
      - surface: src/render.ts
        anchor/v1: "e:cccccccc:dddddddd"
    reason: "Diagnostic rendering nothing parses."
    date: 2026-08-14
```
RECORD

run 1 "a key its constituents do not hash to fails" "$wrong"
has "mismatch 0000000000000000" "the mismatch names the stored key"
has "constituents hash to b0cdc692ed4e8a74" "the mismatch names the derived key"
has "entries=1 ok=0 failed=1" "the summary counts the failure"

# A constituent edited without re-deriving the key is the same failure, reached
# from the other side: the key is the one that was correct before the edit.
edited="$WORK/edited-constituent.md"
cat >"$edited" <<'RECORD'
```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing-v2.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Structured-logging call; the suite asserts on no log emission."
    date: 2026-08-10
```
RECORD

run 1 "a renamed surface beside a stale key fails" "$edited"
has "mismatch 846675cd2cbd91bd" "the stale key is reported, not silently accepted"

# --- an unknown node kind ------------------------------------------------------

unknown="$WORK/unknown-kind.md"
cat >"$unknown" <<'RECORD'
```yaml
suppressions:
  a9bd6eb74943144f:
    check: mutation-testing/operator/AOR
    claim: arid(kind=hard-to-test)
    sites:
      - surface: src/slow.ts
        anchor/v1: "e:aaaaaaaa:bbbbbbbb"
    reason: "The fixture for this path is awkward to build."
    date: 2026-08-15
```
RECORD

run 1 "a kind outside the vocabulary fails" "$unknown"
has "unknown-kind a9bd6eb74943144f" "the verdict names the entry"
has "kind=hard-to-test" "the verdict names the rejected kind"
has "accepted kinds:" "a kind failure lists the accepted kinds"
has "log-call" "the accepted kinds come from the real vocabulary table"
has "generated-region" "the accepted kinds include the last table row"

# The hash is correct here, so the entry fails on membership alone. An
# implementation that graded shape rather than membership would pass it.
lacks "mismatch" "the unknown-kind entry is not also reported as a mismatch"

prose="$WORK/prose-claim.md"
cat >"$prose" <<'RECORD'
```yaml
suppressions:
  a9bd6eb74943144f:
    check: mutation-testing/operator/AOR
    claim: this survivor is not worth killing
    sites:
      - surface: src/slow.ts
        anchor/v1: "e:aaaaaaaa:bbbbbbbb"
    reason: "The fixture for this path is awkward to build."
    date: 2026-08-15
```
RECORD

run 1 "free prose in claim fails" "$prose"
has "claim is not the canonical arid(kind=<node-kind>)" "prose is named as the defect"

# --- the vocabulary is read from a file, not compiled in -----------------------

kinds="$WORK/kinds.md"
cat >"$kinds" <<'TABLE'
#### The node-kind vocabulary

| `kind` | The node it names |
|---|---|
| `hard-to-test` | Not a real kind; present only to prove the table is what is read. |

### Something else
TABLE

run 0 "--kinds makes membership come from the given table" --kinds "$kinds" "$unknown"
has "ok a9bd6eb74943144f" "a kind the given table carries passes"
run 1 "a kind the given table omits fails" --kinds "$kinds" "$valid"
has "kind=log-call" "the omitted kind is named"

# --- a malformed entry ---------------------------------------------------------

malformed="$WORK/malformed.md"
cat >"$malformed" <<'RECORD'
```yaml
suppressions:
  1111111111111111:
    sites:
      - surface: src/partial.ts
        anchor/v1: "e:12341234:56785678"
    reason: "Carries sites, reason and date but neither check nor claim."
    date: 2026-08-16
```
RECORD

run 1 "an entry missing check and claim is malformed" "$malformed"
has "malformed 1111111111111111" "the verdict names the entry"
has "missing required key(s): check, claim" "both missing keys are named"
lacks "constituents hash to" "an unhashable entry claims no derived key"

nosites="$WORK/no-sites.md"
cat >"$nosites" <<'RECORD'
```yaml
suppressions:
  2222222222222222:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    reason: "No sites at all."
    date: 2026-08-17
```
RECORD

run 1 "an entry with no sites is malformed" "$nosites"
has "missing required key(s): sites" "the absent sites key is named"

noreason="$WORK/no-reason.md"
cat >"$noreason" <<'RECORD'
```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    date: 2026-08-10
```
RECORD

run 1 "an entry whose hash is right but whose reason is absent still fails" "$noreason"
has "missing required key(s): reason" "the absent reason is named"

noanchor="$WORK/no-anchor.md"
cat >"$noanchor" <<'RECORD'
```yaml
suppressions:
  3333333333333333:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
    reason: "The site carries no anchor."
    date: 2026-08-10
```
RECORD

baddate="$WORK/bad-date.md"
cat >"$baddate" <<'RECORD'
```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Structured-logging call; the suite asserts on no log emission."
    date: yesterday
```
RECORD

run 1 "a nonempty non-ISO date is malformed" "$baddate"
has "malformed 846675cd2cbd91bd" "a non-ISO date names the entry"
has "date is not ISO-8601 (YYYY-MM-DD): yesterday" "the non-ISO value is named"
lacks "ok 846675cd2cbd91bd" "a non-ISO date is not reported ok"

outofrange="$WORK/out-of-range-date.md"
cat >"$outofrange" <<'RECORD'
```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Structured-logging call; the suite asserts on no log emission."
    date: 2026-13-45
```
RECORD

run 1 "an ISO-shaped date outside the calendar ranges is malformed" "$outofrange"
has "malformed 846675cd2cbd91bd" "an out-of-range date names the entry"
has "date is not ISO-8601 (YYYY-MM-DD): 2026-13-45" "the out-of-range value is named"
lacks "ok 846675cd2cbd91bd" "an out-of-range date is not reported ok"

feb31="$WORK/feb-31-date.md"
cat >"$feb31" <<'RECORD'
```yaml
suppressions:
  846675cd2cbd91bd:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:9f1c2a3b:4d5e6f70"
    reason: "Structured-logging call; the suite asserts on no log emission."
    date: 2026-02-31
```
RECORD

run 1 "an ISO-shaped date that is not a real day is malformed" "$feb31"
has "malformed 846675cd2cbd91bd" "a February 31st names the entry"
has "date is not ISO-8601 (YYYY-MM-DD): 2026-02-31" "the impossible day is named"
lacks "ok 846675cd2cbd91bd" "a February 31st is not reported ok"

# --- the rest of the calendar rule ---------------------------------------------
# Month length and the leap rule, the two parts field ranges alone cannot see.
# 1900 and 2000 pin the century clause: a year divisible by 100 is a leap year
# only when it is also divisible by 400.

calendar_case() { # <expected-exit> <date> <label>
  local record="$WORK/calendar-$2.md"
  printf 'suppressions:\n  846675cd2cbd91bd:\n    check: mutation-testing/operator/SBR\n    claim: arid(kind=log-call)\n    sites:\n      - surface: src/pricing.ts\n        anchor/v1: "e:9f1c2a3b:4d5e6f70"\n    reason: "Structured-logging call; the suite asserts on no log emission."\n    date: %s\n' "$2" >"$record"
  run "$1" "$3" "$record"
  if [[ "$1" -eq 0 ]]; then
    has "ok 846675cd2cbd91bd" "$2 is reported ok"
    lacks "date is not ISO-8601" "$2 is not named as a date defect"
  else
    has "date is not ISO-8601 (YYYY-MM-DD): $2" "$2 is named as the date defect"
    lacks "ok 846675cd2cbd91bd" "$2 is not reported ok"
  fi
}

calendar_case 1 2026-04-31 "the 31st of a 30-day month is malformed"
calendar_case 1 2023-02-29 "February 29th of a common year is malformed"
calendar_case 0 2024-02-29 "February 29th of a leap year is a real day"
calendar_case 1 1900-02-29 "February 29th of a century common year is malformed"
calendar_case 0 2000-02-29 "February 29th of a 400-year leap year is a real day"
calendar_case 0 2026-08-10 "an ordinary calendar date is still accepted"
calendar_case 0 2026-08-09 "a day written with a leading zero is not read as octal"

run 1 "a site with no anchor is malformed" "$noanchor"
has "carries no anchor/v<N>" "the anchorless site is named"

twofailures="$WORK/two-failures.md"
cat >"$twofailures" <<'RECORD'
```yaml
suppressions:
  4444444444444444:
    check: mutation-testing/operator/AOR
    claim: arid(kind=hard-to-test)
    sites:
      - surface: src/slow.ts
        anchor/v1: "e:aaaaaaaa:bbbbbbbb"
    reason: "Both the key and the kind are wrong."
    date: 2026-08-15
```
RECORD

run 1 "an entry failing two checks reports both on one line" "$twofailures"
has "mismatch 4444444444444444" "the first failure in order is the verdict"
has "constituents hash to a9bd6eb74943144f" "the hash failure is reported"
has "kind=hard-to-test, not in the vocabulary" "the kind failure is not hidden behind it"

# --- an empty record -----------------------------------------------------------

emptymap="$WORK/empty-mapping.md"
cat >"$emptymap" <<'RECORD'
# Accepted arid-node suppressions

Nothing has been accepted yet.

```yaml
suppressions:
```
RECORD

run 0 "an empty suppressions mapping is a clean pass" "$emptymap"
has "entries=0 ok=0 failed=0" "an empty mapping counts zero entries"

bracemap="$WORK/brace-mapping.md"
printf 'suppressions: {}\n' >"$bracemap"
run 0 "an explicitly empty mapping is a clean pass" "$bracemap"
has "entries=0 ok=0 failed=0" "the brace form counts zero entries"

zerobyte="$WORK/zero-byte.md"
: >"$zerobyte"
run 2 "a zero-byte file is not gradeable" "$zerobyte"
has "no top-level suppressions: mapping" "the empty file is named as ungradeable"

norecord="$WORK/no-mapping.md"
printf '# Notes\n\nNo mapping here.\n' >"$norecord"
run 2 "a file with no suppressions mapping fails closed" "$norecord"

# --- an absent record is a valid state ----------------------------------------

run 0 "an absent record is a valid state" "$WORK/does-not-exist.md"
has "absent " "the absent record is reported"
has "entries=0 ok=0 failed=0" "an absent record counts zero entries"

# --- several records in one invocation ----------------------------------------

run 1 "several records are graded in one run" "$valid" "$wrong"
has "record $valid" "the first record is named"
has "record $wrong" "the second record is named"
has "entries=3 ok=2 failed=1" "the summary spans every record"

# --- a proposed entry graded from stdin ---------------------------------------

# The audit skill's Phase 4 grades a PROPOSED entry, which is in no record yet,
# and that skill writes nothing outside its opt-in persist phase. Stdin is how
# the two reconcile.
run_stdin() {
  local expected="$1" label="$2" input="$3"
  local actual
  last_out="$(bash "$SUT" - <"$input" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label - expected exit $expected, got $actual: $last_out"
  fi
}

run_stdin 0 "a record on stdin is graded" "$valid"
has "ok 846675cd2cbd91bd" "the stdin record's entries are graded"

run_stdin 1 "a failing record on stdin exits 1" "$unknown"
has "unknown-kind a9bd6eb74943144f" "the stdin failure names the entry"

# --- usage --------------------------------------------------------------------

run 2 "no record is a usage error"
run 2 "an unknown argument is refused" --nope "$valid"
run 2 "--kinds with no file is a usage error" --kinds
run 2 "an unreadable vocabulary table fails closed" --kinds "$WORK/no-such-table.md" "$valid"
run 2 "a vocabulary table with no kinds fails closed" --kinds "$norecord" "$valid"
run 0 "--help exits clean" --help
has "suppression-lint.sh <record>" "--help prints the usage block"
has "reports as clean." "--help prints the header through its closing FAIL CLOSED sentence"

echo
if [[ $fails -eq 0 ]]; then
  echo "all suppression-lint.sh contract tests passed"
  exit 0
fi
echo "$fails suppression-lint.sh contract test(s) failed" >&2
exit 1
