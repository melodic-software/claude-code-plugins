#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-gate-lines.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

CURRENT="$TEST_TMPDIR/current.md"
PROPOSED="$TEST_TMPDIR/proposed.md"

cat >"$CURRENT" <<'EOF'
Closes #42
Siblings: #40, #41
Hold: waiting on vendor
Draft: requested early look
Merge-Risk: max=LOW demote=false

## What changed

- Parses dates with the standard library.

## Verification

- `bats tests/` passed.
- Left out: nothing

## Follow-ups

- Pre-existing (advisory): retry the flaky upload ([thread](https://example.invalid/1))
EOF

propose() {
  local from="$1" to="$2" line
  : >"$PROPOSED"
  while IFS= read -r line; do
    if [[ "$line" == "$from" ]]; then
      [[ -n "$to" ]] && printf '%s\n' "$to" >>"$PROPOSED"
    else
      printf '%s\n' "$line" >>"$PROPOSED"
    fi
  done <"$CURRENT"
}

run() { out=$(bash "$SCRIPT" "$CURRENT" "$PROPOSED" 2>&1); code=$?; }

propose "- Parses dates with the standard library." "- Parses dates and times with the standard library."
run
assert_exit "rewriting What changed passes" 0 "$code"
propose "- Left out: nothing" "- Left out: the timezone table"
run
assert_exit "rewriting the Left out: line passes" 0 "$code"

fails() {
  local label="$1" from="$2" to="$3" want="$4"
  propose "$from" "$to"
  run
  assert_exit "$label fails" 1 "$code"
  assert_contains "$label names the line" "$out" "$want"
}

passes() {
  propose "$2" "$3"
  run
  assert_exit "$1 passes" 0 "$code"
}

passes "a removed Hold: line" "Hold: waiting on vendor" ""
passes "a hold phrase added" "- \`bats tests/\` passed." "- \`bats tests/\` passed. Do not merge until the vendor ships."
passes "a quoted hold line added" "Closes #42" $'Closes #42\n> hold: owner review'
passes "a split hold phrase added" "- \`bats tests/\` passed." $'- `bats tests/` passed. Do not\nmerge yet.'

fails "a changed closing line" "Closes #42" "Closes #43" "removed: Closes #42"
fails "a changed Draft: line" "Draft: requested early look" "Draft: ready soon" "added: Draft: ready soon"
fails "a changed Siblings: line" "Siblings: #40, #41" "Siblings: #40" "removed: Siblings: #40, #41"
fails "a changed Merge-Risk: line" "Merge-Risk: max=LOW demote=false" "Merge-Risk: max=HIGH demote=true" "added: Merge-Risk: max=HIGH demote=true"
fails "a dropped Follow-ups entry" "- Pre-existing (advisory): retry the flaky upload ([thread](https://example.invalid/1))" "" \
  "removed: - Pre-existing (advisory): retry the flaky upload"
fails "a closing line added in What changed" "- Parses dates with the standard library." "- Parses dates. Fixes #77" "added: - Parses dates. Fixes #77"
fails "a Refs: line added" "Closes #42" $'Closes #42\nRefs: #50' "added: Refs: #50"
fails "a quoted Draft: line added" "Closes #42" $'Closes #42\n> draft: owner review' "added: > draft: owner review"

URL_CLOSE="Closes https://github.com/o/r/issues/42"
fails "a URL-form closing line added" "Closes #42" $'Closes #42\n'"$URL_CLOSE" "added: $URL_CLOSE"

propose "- Parses dates with the standard library." $'- Parses dates with the standard library.\n'"$URL_CLOSE"
cp "$PROPOSED" "$CURRENT"
fails "a changed URL-form closing line" "$URL_CLOSE" "Closes https://github.com/o/r/issues/43" "removed: $URL_CLOSE"
fails "a removed URL-form closing line" "$URL_CLOSE" "" "removed: $URL_CLOSE"
propose "- Left out: nothing" "- Left out: the timezone table"
run
assert_exit "rewriting another section keeps a URL-form closing line" 0 "$code"

cp "$CURRENT" "$PROPOSED"
printf 'Draft: requested early look\n' >>"$PROPOSED"
run
assert_exit "a repeated Draft: line fails" 1 "$code"

printf 'Closes #42\r\nDraft: requested early look\r\n' >"$TEST_TMPDIR/crlf.md"
printf 'Closes #42\nDraft: requested early look\n## What changed\n- new\n' >"$PROPOSED"
out=$(bash "$SCRIPT" "$TEST_TMPDIR/crlf.md" "$PROPOSED" 2>&1)
assert_exit "CRLF line endings alone change no gate line" 0 "$?"

bash "$SCRIPT" "$CURRENT" >/dev/null 2>&1
assert_exit "one argument is a usage error" 2 "$?"
bash "$SCRIPT" "$CURRENT" "$TEST_TMPDIR/missing.md" >/dev/null 2>&1
assert_exit "a missing file is a usage error" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
