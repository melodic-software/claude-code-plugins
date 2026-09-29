#!/usr/bin/env bash
# Fixture tests for check-skill-description-voice.sh.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-skill-description-voice.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <expected-exit> <name> <description>: check one SKILL.md carrying it.
run() {
  local expected="$1" name="$2" status
  printf -- '---\nname: demo\ndescription: "%s"\n---\n\nBody with you and your.\n' "$3" >"$TMP/SKILL.md"
  LAST_OUTPUT="$(bash "$SCRIPT" --paths "$TMP/SKILL.md" 2>&1)"
  status=$?
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
  else
    bad "$name" "expected exit $expected, got $status; output: $LAST_OUTPUT"
  fi
}

run 0 "a third-person description passes" \
  "Audit the widgets and report drift. Use when: the widgets drift."
run 1 "a bare 'you' fails" \
  "Tells you which widgets drift. Use when: the widgets drift."
assert_output_contains "the failure names the word" "(you)"
run 1 "'your' in the lead fails" \
  "Writes the file from your answers. Use when: setting up."
run 1 "'Yourself' in any case fails" \
  "Lets the reader check Yourself. Use when: checking."
run 0 "second person inside single-quoted trigger phrases passes" \
  "Checks claims. Use when: 'do your research', 'are you sure about this', 'wait, stop'."
run 0 "an apostrophe inside a trigger phrase does not end it" \
  "Checks claims. Use when: 'you're guessing', 'that's what you said', 'stop'."
run 0 "an escaped double-quoted trigger phrase passes" \
  "Checks claims. Use when: \\\"you're steamrolling\\\", 'stop'."
run 0 "a hyphenated name is one word" \
  "Pairs with do-your-research-deep and the You-I-We technique."
run 1 "a pronoun after the last trigger phrase still fails" \
  "Checks claims. Use when: 'stop', or when you ask for it."
run 0 "the SKILL.md body is not judged" \
  "Audit the widgets."

printf -- '---\nname: demo\ndescription: >-\n  Audit the widgets.\n\n  Tells you which drift.\n---\n' >"$TMP/SKILL.md"
if bash "$SCRIPT" --paths "$TMP/SKILL.md" 2>/dev/null; then
  fail "a folded block-scalar description is checked"
else
  ok "a folded block-scalar description is checked"
fi

if bash "$SCRIPT" 2>/dev/null; then
  fail "no argument should be a usage error"
else
  ok "no argument is a usage error"
fi

test_harness::report
