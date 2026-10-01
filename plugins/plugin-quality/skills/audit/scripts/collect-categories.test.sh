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
has "finding-without-research section=Errors title=bare" "the missing research line is named"

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
research: open-question

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

SAVED_A="$WORK/skills-page.md"
SAVED_B="$WORK/changelog.md"
SAVED_C="$WORK/blog.md"
printf 'Skills load on demand.\nThe default is 1 per session.\n' >"$SAVED_A"
printf 'Changelog: the default is 1 per session.\n' >"$SAVED_B"
printf 'Practitioners report a default of 1.\r\n' >"$SAVED_C"
: >"$WORK/empty-page.md"
SPAN='default is 1 per session'
SRC_A="https://code.claude.com/docs/en/skills saved=$SAVED_A span=$SPAN"
SRC_B="https://code.claude.com/docs/en/changelog saved=$SAVED_B span=$SPAN"
SRC_C="https://example.invalid/blog saved=$SAVED_C span=\"a default of 1.\""

# tier_ledger <primary> [corroborator...] - an Improvements finding at tier-1.
tier_ledger() {
  local name="$1" primary="$2" c
  shift 2
  {
    printf '## Errors\nnone\n\n## Improvements\n### cite the page\nevidence: the skill asserts a default\n'
    printf 'remediation: restate the default\nresearch: tier-1\nprimary: %s\n' "$primary"
    for c in "$@"; do printf 'corroborator: %s\n' "$c"; done
    printf '\n## Quality of life\nnone\n\n## Standards alignment\nnone\n\n## Emitted findings\nnot-applicable\n'
  } >"$WORK/$name"
  printf '%s' "$WORK/$name"
}

run 0 "a tier-1 record whose spans are in the saved files completes" --notes "$(tier_ledger t-ok.md "$SRC_A" "$SRC_B" "$SRC_C")"
has "status: complete" "a checked tier record completes"

run 1 "a primary whose saved file is missing is rejected" --notes "$(tier_ledger t-nofile.md "https://x.invalid/p saved=$WORK/absent.md span=$SPAN" "$SRC_B" "$SRC_C")"
has "research-primary-file-missing" "the missing saved file is named"

run 1 "a primary whose saved file is empty is rejected" --notes "$(tier_ledger t-empty.md "https://x.invalid/p saved=$WORK/empty-page.md span=$SPAN" "$SRC_B" "$SRC_C")"
has "research-primary-file-empty" "the empty saved file is named"

run 1 "a primary whose span is not in its file is rejected" --notes "$(tier_ledger t-span.md "https://x.invalid/p saved=$SAVED_A span=recalled wording" "$SRC_B" "$SRC_C")"
has "research-primary-span-not-in-file" "the unmatched span is named"

run 1 "a corroborator whose span is not in its file is rejected" --notes "$(tier_ledger t-cspan.md "$SRC_A" "$SRC_B" "https://x.invalid/c saved=$SAVED_C span=invented")"
has "research-corroborator-span-not-in-file" "the unmatched corroborator span is named"

OUTSIDE="$(mktemp -d)"
printf 'The default is 1 per session.\n' >"$OUTSIDE/page.md"
run 1 "a primary saved outside the ledger directory is rejected" --notes "$(tier_ledger t-out.md "https://x.invalid/p saved=$OUTSIDE/page.md span=$SPAN" "$SRC_B" "$SRC_C")"
has "research-primary-path-outside-packet" "the outside path is named"
run 1 "a primary saved through a dot-dot escape is rejected" --notes "$(tier_ledger t-dots.md "https://x.invalid/p saved=$WORK/../$(basename "$OUTSIDE")/page.md span=$SPAN" "$SRC_B" "$SRC_C")"
has "research-primary-path-outside-packet" "the escaping path is named"
rm -rf "$OUTSIDE"

run 1 "a primary that is not url, saved and span is rejected" --notes "$(tier_ledger t-shape.md "https://code.claude.com/docs/en/skills" "$SRC_B" "$SRC_C")"
has "research-primary-shape" "the self-attested primary is named"

run 1 "a corroborator repeating the primary url does not count" --notes "$(tier_ledger t-dup.md "$SRC_A" "$SRC_B" "https://code.claude.com/docs/en/skills saved=$SAVED_B span=$SPAN")"
has "research-corroborators" "the duplicate corroborator is not counted"

run 1 "an empty quoted span is rejected" --notes "$(tier_ledger t-emptyspan.md "https://x.invalid/p saved=$SAVED_A span=\"\"" "$SRC_B" "$SRC_C")"
has "research-primary-empty-span" "the empty span is named"

run 1 "a corroborator that is a fragment or query variant of the primary does not count" --notes "$(tier_ledger t-variant.md "$SRC_A" "https://code.claude.com/docs/en/skills/?x=1#top saved=$SAVED_B span=$SPAN" "$SRC_C")"
has "research-corroborators" "the url variant is not counted"

run 1 "one corroborator does not meet the bar" --notes "$(tier_ledger t-one.md "$SRC_A" "$SRC_B")"
has "research-corroborators" "the short corroborator count is named"

CLAIM_ONLY="$(
  notes claim-only.md <<'EOF'
## Errors
### the skill asserts a default
evidence: packet reproduction

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
run 1 "a claim with no remediation still needs a research line" --notes "$CLAIM_ONLY"
has "finding-without-research section=Errors title=the skill asserts a default" "the unresearched claim is named"

TIER="$(
  notes tier.md <<'EOF'
## Errors
none

## Improvements
### cite the page
evidence: the skill asserts a default
remediation: restate the default from the skills page
research: open-question

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
run 0 "a false emitted sample with a basis completes" --notes "$TIER"
has "status: complete" "tier ledger completes"

DISC="$(
  notes discipline.md <<'EOF'
## Errors
none

## Improvements
none

## Quality of life
none

## Standards alignment
### copies the source instead of pointing
evidence: the body restates the table
convention: discipline:point-dont-copy
component: plugins/example/skills/run/SKILL.md:12

### standards policy disagrees
evidence: the hook pins a version the policy forbids
convention: components/example/policy.json:4
component: plugins/example/hooks/hooks.json:9

## Emitted findings
not-applicable
EOF
)"
run 0 "a discipline and a standards-path citation are accepted" --notes "$DISC"
has "status: complete" "cited standards ledger completes"

UNCITED="$WORK/uncited.md"
sed '/^component:/d' "$DISC" >"$UNCITED"
run 1 "a standards finding without its component line is rejected" --notes "$UNCITED"
has "standards-finding-uncited" "the uncited finding is named"

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
