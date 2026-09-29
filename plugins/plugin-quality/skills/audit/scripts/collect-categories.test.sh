#!/usr/bin/env bash
# Black-box contract for collect-categories.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/collect-categories.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"
test_helpers::contract_lane

notes() {
  local name="$1"
  cat >"$WORK/$name"
  printf '%s' "$WORK/$name"
}

COMPLETE="$(
  notes complete.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"

run 0 "a ledger with every section closed is complete" --notes "$COMPLETE"
has "status: complete" "complete ledger says so"

MISSING="$(
  notes missing.md <<'EOF'
## Errors
none

## Improvements
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "a missing quality-of-life section is incomplete" --notes "$MISSING"
has "missing-section name=Quality of life" "the skipped category is named"

EMPTY="$(
  notes empty.md <<'EOF'
## Errors

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "a heading with no body is an empty section" --notes "$EMPTY"
has "section-empty section=Errors" "an empty errors section is named"

NO_EVIDENCE="$(
  notes no-evidence.md <<'EOF'
## Errors
### bare
remediation: do the thing
research: open-question

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "a finding without evidence is incomplete" --notes "$NO_EVIDENCE"
has "finding-missing-evidence" "missing evidence is named"

NO_RESEARCH="$(
  notes no-research.md <<'EOF'
## Errors
### bare
evidence: packet
remediation: do the thing

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "a remediation without research is not a recommendation" --notes "$NO_RESEARCH"
has "remediation-without-research" "the missing research line is named"

OPENQ="$(
  notes openq.md <<'EOF'
## Errors
### bare
evidence: packet
remediation: do the thing
research: open-question

## Improvements
### nicer report
evidence: the report omitted detail

## Quality of life
none

## Standards alignment
unresolved
fallback: convention home unresolved

## Emitted findings
not-applicable
EOF
)"
run 0 "an open question and an unresolved home are complete" --notes "$OPENQ"
has "status: complete" "open-question ledger completes"

TIER="$(
  notes tier.md <<'EOF'
## Errors
none

## Improvements
### cite the page
evidence: the skill asserts a default
remediation: restate the default from the skills page
research: tier-1
primary: https://code.claude.com/docs/en/skills
corroborators: 2

## Quality of life
none

## Standards alignment
none

## Emitted findings
### sample
plugin-said: count was 1
verdict: false
basis: https://example.invalid/source
EOF
)"
run 0 "tier-1 with two corroborators and a false sample with a basis completes" --notes "$TIER"
has "status: complete" "tier ledger completes"

THIN="$(
  notes thin.md <<'EOF'
## Errors
none

## Improvements
### cite the page
evidence: the skill asserts a default
remediation: restate the default
research: tier-1
primary: https://code.claude.com/docs/en/skills
corroborators: 1

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "one corroborator does not meet the bar" --notes "$THIN"
has "research-corroborators" "the short corroborator count is named"

FALSE_BARE="$(
  notes false-bare.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
### sample
plugin-said: count was 1
verdict: false
EOF
)"
run 1 "a false emitted finding without a basis is incomplete" --notes "$FALSE_BARE"
has "emitted-false-without-basis" "the missing basis is named"

CONFIRMED_BARE="$(
  notes confirmed-bare.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
### sample
plugin-said: count was 1
verdict: confirmed
EOF
)"
run 1 "a confirmed emitted finding without a basis is incomplete" --notes "$CONFIRMED_BARE"
has "emitted-confirmed-without-basis" "the missing basis is named"

EMPTY_FIELDS="$(
  notes empty-fields.md <<'EOF'
## Errors
### hollow
evidence:
remediation:
research: tier-0
primary: x
corroborators: 2

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable
EOF
)"
run 1 "empty evidence and remediation values do not satisfy the grader" --notes "$EMPTY_FIELDS"
has "finding-missing-evidence section=Errors title=hollow" "an empty evidence field is named"
has "remediation-empty section=Errors title=hollow" "an empty remediation field is named"

EXTRAS="$(
  notes extras.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable

## Blindspots
### adjacent hooks share the failure mode
The sibling hook was not exercised.

## Doc-worthy gotchas
none

## Unverified claims
### the page was truncated
No channel produced the bytes.
EOF
)"
run 0 "blindspots, gotchas and unverified claims ride in the ledger" --notes "$EXTRAS"
has "status: complete" "the ungraded headings do not make the ledger malformed"

STRAY="$(
  notes stray.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
none

## Emitted findings
not-applicable

## Notes
anything
EOF
)"
run 1 "a heading outside the closed set is malformed" --notes "$STRAY"
has "unknown-section name=Notes" "the stray heading is named"

# CRLF notes parse the same headings.
CRLF="$WORK/crlf.md"
printf '## Errors\r\nnone\r\n\r\n## Improvements\r\nnone\r\n\r\n## Quality of life\r\nnone\r\n\r\n## Standards alignment\r\nnone\r\n\r\n## Emitted findings\r\nnot-applicable\r\n' >"$CRLF"
run 0 "CRLF notes still grade" --notes "$CRLF"
has "status: complete" "CRLF ledger completes"

run 2 "missing --notes is usage"
has "ERROR: --notes is required" "usage names the missing flag"

contract_report collect-categories
