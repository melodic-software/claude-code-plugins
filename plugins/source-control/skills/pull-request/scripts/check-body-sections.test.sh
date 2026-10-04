#!/usr/bin/env bash
# Regression test for the create-path required-sections gate (reference/create.md
# §2.4.2.2). Runs the bash block exactly as create.md prints it, and the shared
# hook checker (hooks/pr-linkage-validator.sh linkage::problems), over the same
# bodies, and asserts both return the verdict the pinned ci-workflows
# pr-contract analyzer returned for that body. Those verdicts were recorded by
# running the analyzer itself over these bodies; they are the expected values
# here, not anything either implementation computed.

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CREATE_MD="$SKILL_DIR/reference/create.md"
VALIDATOR="$SKILL_DIR/../../hooks/pr-linkage-validator.sh"

PASS=0
FAIL=0

# The first ```bash block after the §2.4.2.2 heading, with <skill-dir> resolved.
GATE=$(awk '
  /^#### 2\.4\.2\.2 / { in_sec = 1; next }
  in_sec && /^```bash$/ { in_block = 1; next }
  in_block && /^```$/ { exit }
  in_block { print }
' "$CREATE_MD")
GATE="${GATE//<skill-dir>/$SKILL_DIR}"
if [[ -z "$GATE" ]]; then
  echo "FAIL: no bash block found under §2.4.2.2 in $CREATE_MD" >&2
  exit 1
fi

skill_verdict() {
  # shellcheck disable=SC2034  # read by the evaluated create.md block
  (
    BODY="$1"
    shift
    REQUIRED_SECTIONS=("$@")
    REQUIRED_SECTIONS_SOURCE="test fixture"
    eval "$GATE"
  ) >/dev/null 2>&1 && echo PASS || echo FAIL
}

hook_verdict() {
  (
    # shellcheck source=../../../hooks/pr-linkage-validator.sh
    source "$VALIDATOR"
    linkage::problems "$1"
  ) >/dev/null 2>&1 && echo PASS || echo FAIL
}

tail_ok=$'## Fix\nfix\n\n## Verification\nran it\n\n## Related\nN/A'
mk() { printf 'Closes #1\n\n## Summary\n%s\n\n%s' "$1" "$tail_ok"; }

check() {
  local name="$1" want="$2" body="$3" skill hook
  skill=$(skill_verdict "$body" Summary Fix Verification Related)
  hook=$(hook_verdict "$body")
  if [[ "$skill" == "$want" && "$hook" == "$want" ]]; then
    echo "PASS: $name ($want)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name: want $want, create.md gate $skill, shared checker $hook"
    FAIL=$((FAIL + 1))
  fi
}

check "Summary is only a backtick fence" FAIL "$(mk $'```\nonly code\n```')"
check "Summary is only a tilde fence" FAIL "$(mk $'~~~\nonly code\n~~~')"
check "Summary is only indented code" FAIL "$(mk '    only indented code')"
# shellcheck disable=SC2016  # a literal backtick span is the case under test
check "Summary is only an inline code span" FAIL "$(mk '`only inline`')"
check "Summary holds an h1 and nothing else" FAIL "$(mk '# Not prose, an h1')"
check "Summary holds prose" PASS "$(mk 'Real prose.')"
check "lowercase ## summary heading" PASS "$(printf 'Closes #1\n\n## summary\nReal prose.\n\n%s' "$tail_ok")"
check "heading with a trailing space" PASS "$(printf 'Closes #1\n\n## Summary \nReal prose.\n\n%s' "$tail_ok")"

# The create path checks the headings config resolved, not the hook's fixed four.
check_configured() {
  local name="$1" want="$2" body="$3" got
  shift 3
  got=$(skill_verdict "$body" "$@")
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $name ($want)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name: want $want, create.md gate $got"
    FAIL=$((FAIL + 1))
  fi
}
check_configured "configured heading present" PASS $'## Notes\nwritten' Notes
check_configured "configured heading only in a fence" FAIL $'```\n## Notes\nwritten\n```' Notes
check_configured "resolved none checks nothing" PASS ""

echo "check-body-sections: $PASS passed, $FAIL failed"
((FAIL == 0))
