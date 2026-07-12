#!/usr/bin/env bash
# Black-box contract test for check-skill.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repo with fixture
# skills, runs the checker, and asserts on exit code + output. Mutates only its
# own mktemp dir. markdownlint (check 6) is skipped via the documented test seam
# so the suite needs no Node/npx.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-skill.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fresh repo, isolated from any ambient git-hook env that would leak into it.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX 2>/dev/null || true
git -C "$TMP" init -q
git -C "$TMP" config user.email test@example.com
git -C "$TMP" config user.name test

SKILLS="$TMP/.claude/skills"

make_skill() {
  local name="$1" body="$2"
  mkdir -p "$SKILLS/$name"
  printf '%s' "$body" >"$SKILLS/$name/SKILL.md"
}

good_body='---
name: good-skill
description: "Do a thing. Use when: you need a thing done."
---

## Purpose

A minimal well-formed skill fixture.

## Gotchas

None known.
'

make_skill good-skill "$good_body"
make_skill bad-skill '# no frontmatter here
just a heading
'

run() {
  # Run from inside the fixture repo so `git rev-parse` resolves to it.
  (cd "$TMP" \
    && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" "$@")
}

# 1. --help exits 0.
if run --help >/dev/null 2>&1; then
  pass "--help exits 0"
else
  fail "--help should exit 0"
fi

# 2. Well-formed skill passes.
out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS' <<<"$out"; then
  pass "well-formed skill passes"
else
  fail "well-formed skill should pass (rc=$rc): $out"
fi

# 3. Skill without frontmatter fails.
out="$(run bad-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL' <<<"$out"; then
  pass "frontmatter-less skill fails"
else
  fail "frontmatter-less skill should fail (rc=$rc): $out"
fi

# 4. Missing skill errors with exit 1.
run does-not-exist >/dev/null 2>&1
rc=$?
if [[ $rc -eq 1 ]]; then
  pass "missing skill exits 1"
else
  fail "missing skill should exit 1 (rc=$rc)"
fi

# 5. Dropping a committed single-quoted trigger phrase fails (check 3, the
#    regression-critical path — exercises the git-backed SKILL_REL resolution).
trig_head='---
name: trig-skill
description: "Trigger fixture. Use when: '"'"'alpha trigger'"'"', '"'"'beta trigger'"'"'."
---

## Purpose

Committed baseline carrying two single-quoted trigger phrases.
'
make_skill trig-skill "$trig_head"
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add trig-skill'
# Rewrite the working tree dropping the 'beta trigger' phrase.
make_skill trig-skill '---
name: trig-skill
description: "Trigger fixture. Use when: '"'"'alpha trigger'"'"'."
---

## Purpose

Working-tree version with one trigger phrase dropped.
'
out="$(run trig-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'dropped trigger keyword' <<<"$out"; then
  pass "dropped committed trigger phrase fails"
else
  fail "dropped trigger phrase should fail with a trigger-drop message (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
