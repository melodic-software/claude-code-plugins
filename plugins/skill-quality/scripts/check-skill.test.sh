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
description: "Do a thing. Use when: '"'"'a thing'"'"' is needed."
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

# 6. A relative skills root resolves against CLAUDE_PROJECT_DIR, not the cwd,
#    even when invoked from a subdirectory.
mkdir -p "$TMP/subdir"
out="$(cd "$TMP/subdir" \
  && CLAUDE_PROJECT_DIR="$TMP" CHECK_SKILL_SKILLS_ROOT=".claude/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS' <<<"$out"; then
  pass "relative skills root resolves via CLAUDE_PROJECT_DIR from a subdir"
else
  fail "relative skills root should resolve via CLAUDE_PROJECT_DIR (rc=$rc): $out"
fi

# 7. Content before the opening `---` fence is not frontmatter (check 1 fails).
make_skill preamble-skill 'Stray preamble before the fence.
---
name: preamble-skill
description: "Thing. Use when: '"'"'x trigger'"'"'."
---

## Purpose

Frontmatter does not open on line 1.
'
out="$(run preamble-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'no YAML frontmatter' <<<"$out"; then
  pass "content before the --- fence is not treated as frontmatter"
else
  fail "preamble before fence should fail check 1 (rc=$rc): $out"
fi

# 8. A block-scalar `description: |` is unfolded, so a trigger phrase dropped
#    from inside the block is still caught by check 3.
make_skill blk-skill '---
name: blk-skill
description: |
  Do the thing. Use when: '"'"'block alpha'"'"', '"'"'block beta'"'"'.
---

## Purpose

Committed baseline with a block-scalar description carrying two triggers.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add blk-skill'
make_skill blk-skill '---
name: blk-skill
description: |
  Do the thing. Use when: '"'"'block alpha'"'"'.
---

## Purpose

Working tree drops the block beta trigger.
'
out="$(run blk-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'block beta' <<<"$out"; then
  pass "block-scalar description is unfolded (trigger drop caught inside |)"
else
  fail "block-scalar trigger drop should be caught (rc=$rc): $out"
fi

# 9. An unquoted `Use when:` list warns (drop-protection gap surfaced) but passes.
make_skill unq-skill '---
name: unq-skill
description: "Do the thing. Use when: you need it, or someone asks."
---

## Purpose

Unquoted Use-when triggers.

## Gotchas

None known.
'
out="$(run unq-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'not single-quoted' <<<"$out"; then
  pass "unquoted Use-when triggers warn (drop-protection gap surfaced)"
else
  fail "unquoted triggers should warn without failing (rc=$rc): $out"
fi

# 10. CHECK_SKILL_BASE_REF catches an ALREADY-COMMITTED trigger drop that the
#     default working-tree-vs-HEAD comparison misses (HEAD == tree).
make_skill baseref-skill '---
name: baseref-skill
description: "Thing. Use when: '"'"'ref alpha'"'"', '"'"'ref beta'"'"'."
---

## Purpose

First commit carries two triggers.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'baseref v1'
make_skill baseref-skill '---
name: baseref-skill
description: "Thing. Use when: '"'"'ref alpha'"'"'."
---

## Purpose

Second commit drops ref beta — now committed, so HEAD == tree.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'baseref v2 drops beta'
run baseref-skill >/dev/null 2>&1
rc_head=$?
out_base="$(cd "$TMP" \
  && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 CHECK_SKILL_BASE_REF=HEAD^ \
    bash "$SUT" baseref-skill 2>&1)"
rc_base=$?
if [[ $rc_head -eq 0 ]] && [[ $rc_base -eq 1 ]] && grep -q 'ref beta' <<<"$out_base"; then
  pass "post-commit base ref catches a committed trigger drop that HEAD misses"
else
  fail "base-ref audit should catch a committed drop HEAD misses (rc_head=$rc_head rc_base=$rc_base): $out_base"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
