#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixture SKILL.md bodies are literal bytes passed in single quotes (backticks and ! are content, never shell expansion)
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

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_CONFIG 2>/dev/null || true
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
  (cd "$TMP" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" "$@")
}

run_require_evals() {
  (cd "$TMP" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" --require-evals "$@")
}

run_roots() {
  (cd "${ROOTS_CWD:-$TMP}" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" "$@")
}

if run --help >/dev/null 2>&1; then
  pass "--help exits 0"
else
  fail "--help should exit 0"
fi

out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS' <<<"$out"; then
  pass "well-formed skill passes"
else
  fail "well-formed skill should pass (rc=$rc): $out"
fi

out="$(run bad-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL' <<<"$out"; then
  pass "frontmatter-less skill fails"
else
  fail "frontmatter-less skill should fail (rc=$rc): $out"
fi

colon_body='---
name: colon-skill
description: Use when: the user asks for a thing.
---

## Purpose

A skill whose plain description contains a mapping indicator.

## Gotchas

None known.
'
make_skill colon-skill "$colon_body"
out="$(run colon-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "YAML mapping indicator" <<<"$out"; then
  pass "unquoted colon-space in description fails"
else
  fail "unquoted colon-space in description should fail (rc=$rc): $out"
fi

block_body='---
name: block-colon-skill
description: |
  Use when: the user asks for a thing.
compatibility: Requires git.
---

## Purpose

A block description may contain a colon-space.

## Gotchas

None known.
'
make_skill block-colon-skill "$block_body"
out="$(run block-colon-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "YAML mapping indicator" <<<"$out"; then
  pass "block description with colon-space and a short compatibility passes"
else
  fail "block description with colon-space should pass (rc=$rc): $out"
fi

long_compat="$(printf 'x%.0s' {1..501})"
compat_body="---
name: compat-skill
description: \"Do a thing. Use when a thing is needed.\"
compatibility: ${long_compat}
---

## Purpose

Compatibility longer than the spec allows.

## Gotchas

None known.
"
make_skill compat-skill "$compat_body"
out="$(run compat-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "compatibility is 501 characters" <<<"$out"; then
  pass "compatibility over 500 characters fails"
else
  fail "compatibility over 500 characters should fail (rc=$rc): $out"
fi

run does-not-exist >/dev/null 2>&1
rc=$?
if [[ $rc -eq 1 ]]; then
  pass "missing skill exits 1"
else
  fail "missing skill should exit 1 (rc=$rc)"
fi

out="$(run does-not-exist 2>&1)"
if grep -q 'CHECK_SKILL_SKILLS_ROOT' <<<"$out"; then
  pass "missing bare-name skill hints at CHECK_SKILL_SKILLS_ROOT"
else
  fail "missing bare-name skill should hint at CHECK_SKILL_SKILLS_ROOT: $out"
fi

out="$(run source-control:setup 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'plugin:skill name' <<<"$out" &&
  grep -q 'CHECK_SKILL_SKILLS_ROOT=~/.claude/plugins/cache' <<<"$out" &&
  grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh' <<<"$out" &&
  grep -q 'setup' <<<"$out"; then
  pass "plugin:skill name gets installed-skill resolution guidance"
else
  fail "plugin:skill name should get installed-skill guidance (rc=$rc): $out"
fi

out="$(run 'x:$(touch pwn)' 2>&1)"
cmd_line="$(grep 'check-skill.sh' <<<"$out")"
if grep -qF '$(touch pwn)' <<<"$cmd_line"; then
  fail "leaf with shell syntax should be escaped in the rerun command, not left bare: $cmd_line"
elif grep -qF 'touch' <<<"$cmd_line"; then
  pass "leaf with shell syntax is shell-escaped in the suggested command"
else
  fail "leaf-escape assertion did not find the escaped leaf: $cmd_line"
fi
[[ -e "$TMP/pwn" ]] && fail "escaping test must not create a file"

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
make_skill trig-skill '---
name: trig-skill
description: "Trigger fixture. Use when: '"'"'alpha trigger'"'"'."
---

## Purpose

Working-tree version with one trigger phrase dropped.
'
out="$(run trig-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" &&
  grep -q 'beta trigger' <<<"$out" &&
  grep -q 'Confirm the description still names each intent' <<<"$out" &&
  ! grep -q 'FAIL: dropped trigger keyword' <<<"$out"; then
  pass "dropped committed trigger phrase warns and passes (check 3 advisory)"
else
  fail "dropped trigger phrase should warn, name the phrase, and pass (rc=$rc): $out"
fi

make_skill mover-src '---
name: mover-src
description: "Move fixture. Use when: '"'"'gamma trigger'"'"', '"'"'delta trigger'"'"'."
---

## Purpose

Committed baseline carrying the phrase that will move.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add mover-src'
make_skill mover-src '---
name: mover-src
description: "Move fixture. Use when: '"'"'gamma trigger'"'"'."
---

## Purpose

Working tree drops delta trigger, moved to the sibling below.
'
make_skill mover-dst '---
name: mover-dst
description: "Move target fixture. Use when: '"'"'delta trigger'"'"'."
---

## Purpose

Sibling now owning the moved phrase.

## Gotchas

None known.
'
out="$(run mover-src 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "moved to sibling skill 'mover-dst'" <<<"$out" && ! grep -q 'dropped trigger keyword' <<<"$out"; then
  pass "trigger phrase moved to a sibling skill warns and passes (move exception)"
else
  fail "moved trigger phrase should warn, name the host, and pass (rc=$rc): $out"
fi

make_skill coinc-src '---
name: coinc-src
description: "Overlap fixture. Use when: '"'"'epsilon trigger'"'"', '"'"'shared trigger'"'"'."
---

## Purpose

Committed baseline sharing a phrase with a committed sibling.
'
make_skill coinc-peer '---
name: coinc-peer
description: "Overlap peer fixture. Use when: '"'"'shared trigger'"'"'."
---

## Purpose

Committed sibling that carried the shared phrase all along.

## Gotchas

None known.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add coincidental-overlap fixtures'
make_skill coinc-src '---
name: coinc-src
description: "Overlap fixture. Use when: '"'"'epsilon trigger'"'"'."
---

## Purpose

Working tree drops the shared phrase; the peer had it at base already.
'
out="$(run coinc-src 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" &&
  grep -q 'shared trigger' <<<"$out" && ! grep -q 'moved to sibling skill' <<<"$out"; then
  pass "phrase the sibling carried at base is coincidental overlap: warns as dropped, not as a move"
else
  fail "pre-existing sibling overlap should warn as dropped, not count as a move (rc=$rc): $out"
fi

mkdir -p "$TMP/subdir"
out="$(cd "$TMP/subdir" &&
  CLAUDE_PROJECT_DIR="$TMP" CHECK_SKILL_SKILLS_ROOT=".claude/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS' <<<"$out"; then
  pass "relative skills root resolves via CLAUDE_PROJECT_DIR from a subdir"
else
  fail "relative skills root should resolve via CLAUDE_PROJECT_DIR (rc=$rc): $out"
fi

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
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" && grep -q 'block beta' <<<"$out"; then
  pass "block-scalar description is unfolded (trigger drop surfaced inside |, advisory)"
else
  fail "block-scalar trigger drop should warn without failing (rc=$rc): $out"
fi

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
if [[ $rc -eq 0 ]] && ! grep -q 'WARN:.*Use when' <<<"$out"; then
  pass "unquoted Use-when triggers pass without a quoting warning"
else
  fail "unquoted triggers should pass with no Use-when warning (rc=$rc): $out"
fi

make_skill unq-drop '---
name: unq-drop
description: "Do the thing. Use when you need it, a build breaks, or someone asks. Other prose: x."
---

## Purpose

Committed baseline carrying three unquoted Use-when items.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add unq-drop'
make_skill unq-drop '---
name: unq-drop
description: "Do the thing. Use when you need it, or someone asks. Other prose: y."
---

## Purpose

Working tree drops the unquoted build-breaks item.
'
out="$(run unq-drop 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" &&
  grep -qF "'a build breaks'" <<<"$out" &&
  ! grep -qF "'you need it'" <<<"$out" && ! grep -qF "'someone asks'" <<<"$out" &&
  ! grep -q 'Other prose' <<<"$out"; then
  pass "dropped unquoted Use-when item warns, names only that item, and passes (check 3)"
else
  fail "dropped unquoted trigger should warn naming only that item (rc=$rc): $out"
fi

git -C "$TMP" add -A
git -C "$TMP" commit -qm 'unq-drop: two unquoted items'
make_skill unq-drop '---
name: unq-drop
description: "Do the thing. Use when '"'"'you need it'"'"', or someone asks. Other prose: y."
---

## Purpose

Working tree quotes the first item.
'
out="$(run unq-drop 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'dropped trigger keyword' <<<"$out"; then
  pass "quoting a formerly unquoted Use-when item is not a drop (check 3)"
else
  fail "quoting an unquoted item should not warn as dropped (rc=$rc): $out"
fi

# 9b. Single-quoted triggers in when_to_use alone satisfy check 12 (#1451).
make_skill wtu-only-skill '---
name: wtu-only-skill
description: "Summary without Use-when prose in the description field."
when_to_use: "'"'alpha trigger'"'", "'"'beta trigger'"'"
---

## Purpose

Triggers live in when_to_use only.

## Gotchas

None known.
'
out="$(run wtu-only-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "no 'Use when:' trigger phrasing" <<<"$out"; then
  pass "when_to_use single-quoted triggers satisfy check 12 without description prose"
else
  fail "when_to_use triggers should satisfy check 12 (rc=$rc): $out"
fi

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
out_head="$(run baseref-skill 2>&1)"
rc_head=$?
out_base="$(cd "$TMP" &&
  CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 CHECK_SKILL_BASE_REF=HEAD^ \
    bash "$SUT" baseref-skill 2>&1)"
rc_base=$?
if [[ $rc_head -eq 0 ]] && ! grep -q 'dropped trigger keyword' <<<"$out_head" &&
  [[ $rc_base -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out_base" &&
  grep -q 'ref beta' <<<"$out_base"; then
  pass "post-commit base ref surfaces a committed trigger drop that HEAD misses (advisory)"
else
  fail "base-ref audit should warn on a committed drop HEAD misses, without failing (rc_head=$rc_head rc_base=$rc_base): head=$out_head base=$out_base"
fi

make_skill blkord-skill '---
name: blkord-skill
description: |-2
  Do the thing. Use when: '"'"'order alpha'"'"', '"'"'order beta'"'"'.
---

## Purpose

Committed baseline with a sign-first block header carrying two triggers.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add blkord-skill'
make_skill blkord-skill '---
name: blkord-skill
description: |-2
  Do the thing. Use when: '"'"'order alpha'"'"'.
---

## Purpose

Working tree drops order beta.
'
out="$(run blkord-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" && grep -q 'order beta' <<<"$out"; then
  pass "sign-first block header (|-2) is recognized and unfolded (drop warns, advisory)"
else
  fail "sign-first block header should be unfolded and the drop should warn without failing (rc=$rc): $out"
fi

make_skill blkcmt-skill '---
name: blkcmt-skill
description: | # trigger notes
  Do the thing. Use when: '"'"'comment alpha'"'"', '"'"'comment beta'"'"'.
---

## Purpose

Committed baseline with a commented block header carrying two triggers.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add blkcmt-skill'
make_skill blkcmt-skill '---
name: blkcmt-skill
description: | # trigger notes
  Do the thing. Use when: '"'"'comment alpha'"'"'.
---

## Purpose

Working tree drops comment beta.
'
out="$(run blkcmt-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" && grep -q 'comment beta' <<<"$out"; then
  pass "commented block header (| # ...) is recognized and unfolded (drop warns, advisory)"
else
  fail "commented block header should be unfolded and the drop should warn without failing (rc=$rc): $out"
fi

make_skill blkindent-skill '---
name: blkindent-skill
description: |2
    Deeply indented first line. Use when: '"'"'indent alpha'"'"'.
  Shallower valid line. Use when: '"'"'indent beta'"'"'.
---

## Purpose

Baseline with triggers on lines of differing indent under an explicit indicator.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add blkindent-skill'
make_skill blkindent-skill '---
name: blkindent-skill
description: |2
    Deeply indented first line. Use when: '"'"'indent alpha'"'"'.
---

## Purpose

Working tree drops the shallower line carrying indent beta.
'
out="$(run blkindent-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: dropped trigger keyword' <<<"$out" && grep -q 'indent beta' <<<"$out"; then
  pass "block content past a more-indented first line is captured (indent indicator honored, drop warns)"
else
  fail "trigger on a less-indented block line should be tracked and warn without failing (rc=$rc): $out"
fi

make_skill misnamed-skill '---
name: some-other-name
description: "Name does not match its directory. Use when: '"'"'checking the name gate'"'"'."
---

## Purpose

Fixture whose frontmatter name diverges from its directory name.

## Gotchas

None known.
'
out="$(run misnamed-skill 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "does not match skill directory 'misnamed-skill'" <<<"$out"; then
  pass "frontmatter name mismatching the directory fails"
else
  fail "name/directory mismatch should fail (rc=$rc): $out"
fi

make_skill quoted-name '---
name: "quoted-name"
description: "Quoted name matching its directory. Use when: '"'"'checking quoted names'"'"'."
---

## Purpose

Fixture whose frontmatter name is quoted but matches its directory.

## Gotchas

None known.
'
out="$(run quoted-name 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'does not match skill directory' <<<"$out"; then
  pass "quoted name matching the directory does not trip the gate"
else
  fail "quoted matching name should not trip the gate (rc=$rc): $out"
fi

make_skill commented-name '---
name: commented-name # kept for the migration note
description: "Name carries a trailing YAML comment. Use when: '"'"'checking comment stripping'"'"'."
---

## Purpose

Fixture whose frontmatter name carries a legal trailing comment.

## Gotchas

None known.
'
out="$(run commented-name 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'does not match skill directory' <<<"$out"; then
  pass "trailing YAML comment on name does not trip the gate"
else
  fail "commented name should not trip the gate (rc=$rc): $out"
fi

make_skill escaped-name '---
name: "escaped\x2dname"
description: "Name carries a YAML escape. Use when: '"'"'checking the charset gate'"'"'."
---

## Purpose

Fixture whose frontmatter name uses a YAML escape sequence.

## Gotchas

None known.
'
out="$(run escaped-name 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'is not kebab-case' <<<"$out"; then
  pass "a YAML escape in the name reports as a charset defect, not a mismatch"
else
  fail "escaped name should fail the charset gate (rc=$rc): $out"
fi

make_skill commented-bad '---
name: wrong-name # with a comment too
description: "Wrong name plus a comment. Use when: '"'"'checking comment stripping'"'"'."
---

## Purpose

Fixture that is both misnamed and commented.

## Gotchas

None known.
'
out="$(run commented-bad 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "frontmatter name 'wrong-name' does not match" <<<"$out"; then
  pass "comment stripping does not mask a real mismatch"
else
  fail "commented misnamed skill should still fail (rc=$rc): $out"
fi

# 17b. The effective name is capped at the Agent Skills spec's 64 codepoints.
#      With no declared `name:` the directory leaf IS the name the harness uses,
#      so a 65-char leaf FAILs even though the frontmatter carries no name line.
#      Claude Code itself loads such a skill; the finding is portability.
long_leaf='abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-fghij'
make_skill "$long_leaf" '---
description: "Over-long directory leaf. Use when: '"'"'checking the name length cap'"'"'."
---

## Purpose

Fixture whose 65-character directory leaf is its effective name.

## Gotchas

None known.
'
out="$(run "$long_leaf" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "is 65 codepoints (Agent Skills spec maximum 64)" <<<"$out"; then
  pass "a 65-codepoint effective name fails the spec length cap"
else
  fail "a 65-codepoint name should fail the length cap (rc=$rc): $out"
fi

edge_leaf='abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-abcde-fghi'
make_skill "$edge_leaf" '---
description: "Sixty-four character leaf. Use when: '"'"'checking the name length boundary'"'"'."
---

## Purpose

Fixture whose directory leaf sits exactly at the cap.

## Gotchas

None known.
'
out="$(run "$edge_leaf" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'Agent Skills spec maximum 64' <<<"$out"; then
  pass "a 64-codepoint effective name is conforming"
else
  fail "a 64-codepoint name should pass the length cap (rc=$rc): $out"
fi

# 17c. A reserved word anywhere in the effective name WARNs (a Skills API upload
#      rejects it; Claude Code loads it). Directory-leaf form: no declared name,
#      the leaf carries "claude".
make_skill claude-helper '---
description: "Reserved word in the leaf. Use when: '"'"'checking reserved names'"'"'."
---

## Purpose

Fixture whose directory leaf carries a reserved word.

## Gotchas

None known.
'
out="$(run claude-helper 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: skill name 'claude-helper' contains the word 'claude'" <<<"$out"; then
  pass "a directory leaf containing 'claude' warns on the reserved-word rule and passes"
else
  fail "a leaf containing 'claude' should warn and pass (rc=$rc): $out"
fi

make_skill anthropic-notes '---
name: anthropic-notes
description: "Reserved word in the declared name. Use when: '"'"'checking reserved names'"'"'."
---

## Purpose

Fixture whose declared name carries a reserved word.

## Gotchas

None known.
'
out="$(run anthropic-notes 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q "WARN: skill name 'anthropic-notes' contains the word 'anthropic'" <<<"$out" &&
  grep -q 'rename the declared name' <<<"$out"; then
  pass "a declared name containing 'anthropic' warns, passes, and names the declared field"
else
  fail "a declared name containing 'anthropic' should warn and pass (rc=$rc): $out"
fi

make_skill precompute-cand '---
name: precompute-cand
description: "Gather repo context. Use when: '"'"'gathering repo context'"'"'."
---

## Steps

Inspect the working tree first:

```bash
git status --short
git diff HEAD
```

## Gotchas

None known.
'
out="$(run precompute-cand 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'precompute opportunity' <<<"$out"; then
  pass "read-only shell block without !-injection warns (precompute opportunity)"
else
  fail "read-only context block should warn as a precompute opportunity (rc=$rc): $out"
fi

make_skill precompute-injects '---
name: precompute-injects
description: "Already precomputes. Use when: '"'"'already injecting context'"'"'."
---

## Context
- Tree: !`git status --short`

## Steps

```bash
git diff HEAD
```

## Gotchas

None known.
'
out="$(run precompute-injects 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "skill already using !-injection is silent (whole-file gate)"
else
  fail "skill already injecting with ! should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-sideeffect '---
name: precompute-sideeffect
description: "Builds things. Use when: '"'"'building the project'"'"'."
---

## Steps

```bash
npm run build
bash ./scripts/deploy.sh prod
```

## Gotchas

None known.
'
out="$(run precompute-sideeffect 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "side-effecting shell block is not flagged as a precompute opportunity"
else
  fail "build/deploy block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-gitwrite '---
name: precompute-gitwrite
description: "Commits work. Use when: '"'"'committing changes'"'"'."
---

## Steps

```bash
git add -A
git commit -m "wip"
```

## Gotchas

None known.
'
out="$(run precompute-gitwrite 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "git write block is not classified read-only (subcommand allowlist)"
else
  fail "git add/commit block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-gitmutate '---
name: precompute-gitmutate
description: "Cleans the tree. Use when: '"'"'cleaning the worktree'"'"'."
---

## Steps

```bash
git stash
git clean -fd
```

## Gotchas

None known.
'
out="$(run precompute-gitmutate 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "unlisted mutating git subcommand (stash/clean) is not a precompute candidate"
else
  fail "git stash/clean block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-jsonfence '---
name: precompute-jsonfence
description: "Returns JSON. Use when: '"'"'shaping json output'"'"'."
---

## Example

```json
{"key": "value"}
```

## Gotchas

None known.
'
out="$(run precompute-jsonfence 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "non-shell fenced block (json) is not flagged as a precompute opportunity"
else
  fail "json block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-ghread '---
name: precompute-ghread
description: "Reads PR state. Use when: '"'"'reading pr context'"'"'."
---

## Context

```bash
gh pr diff
gh run list
```

## Gotchas

None known.
'
out="$(run precompute-ghread 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'precompute opportunity' <<<"$out"; then
  pass "read-only gh subcommand (pr diff / run list) is a precompute candidate"
else
  fail "gh read-only block should warn precompute (rc=$rc): $out"
fi

make_skill precompute-pipesink '---
name: precompute-pipesink
description: "Snapshots the tree. Use when: '"'"'snapshotting the tree'"'"'."
---

## Steps

```bash
git status --short | tee snapshot.txt
```

## Gotchas

None known.
'
out="$(run precompute-pipesink 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "read-only command piped into a mutating sink (| tee) is not a candidate"
else
  fail "piped mutation should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-orfallback '---
name: precompute-orfallback
description: "Reads status. Use when: '"'"'reading tree status'"'"'."
---

## Steps

```bash
git status --short || echo "(status unavailable)"
```

## Gotchas

None known.
'
out="$(run precompute-orfallback 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'precompute opportunity' <<<"$out"; then
  pass "read-only command with a || echo fallback is still a candidate"
else
  fail "|| echo fallback block should warn precompute (rc=$rc): $out"
fi

make_skill precompute-findexec '---
name: precompute-findexec
description: "Runs cleanup. Use when: '"'"'running find exec'"'"'."
---

## Steps

```bash
find . -name "*.tmp" -exec ./cleanup.sh {} +
```

## Gotchas

None known.
'
out="$(run precompute-findexec 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "command-launching find -exec is not a precompute candidate"
else
  fail "find -exec block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-chain '---
name: precompute-chain
description: "Marks state. Use when: '"'"'chaining a marker'"'"'."
---

## Steps

```bash
git status --short && touch marker
```

## Gotchas

None known.
'
out="$(run precompute-chain 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "shell continuation (&&) after a read-only command fails closed"
else
  fail "&& continuation block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-cmdsubst '---
name: precompute-cmdsubst
description: "Expands a subst. Use when: '"'"'expanding a substitution'"'"'."
---

## Steps

```bash
git status --short "$(touch marker)"
```

## Gotchas

None known.
'
out="$(run precompute-cmdsubst 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "command substitution in the line fails closed"
else
  fail "command-substitution block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-gitoutput '---
name: precompute-gitoutput
description: "Writes a patch. Use when: '"'"'writing a patch file'"'"'."
---

## Steps

```bash
git diff --output=changes.patch
```

## Gotchas

None known.
'
out="$(run precompute-gitoutput 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "file-output option on a git reader (--output) fails closed"
else
  fail "git diff --output block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-extdiff '---
name: precompute-extdiff
description: "External diff. Use when: '"'"'running an external diff'"'"'."
---

## Steps

```bash
git diff --ext-diff
```

## Gotchas

None known.
'
out="$(run precompute-extdiff 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "external-diff option on a git reader (--ext-diff) fails closed"
else
  fail "git diff --ext-diff block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-ornonecho '---
name: precompute-ornonecho
description: "Runs a fallback. Use when: '"'"'running an or fallback'"'"'."
---

## Steps

```bash
git status --short || bash ./recover.sh
```

## Gotchas

None known.
'
out="$(run precompute-ornonecho 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "a || continuation into a non-echo command fails closed"
else
  fail "|| bash continuation block should not warn precompute (rc=$rc): $out"
fi

make_skill precompute-fprint0 '---
name: precompute-fprint0
description: "Writes a file list. Use when: '"'"'writing a file list'"'"'."
---

## Steps

```bash
find . -name "*.md" -fprint0 files.txt
```

## Gotchas

None known.
'
out="$(run precompute-fprint0 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'precompute opportunity' <<<"$out"; then
  pass "find -fprint0 file-output primary fails closed"
else
  fail "find -fprint0 block should not warn precompute (rc=$rc): $out"
fi

mkdir -p "$SKILLS/vendor-skill-ok/vendor"
printf 'v1\n' >"$SKILLS/vendor-skill-ok/vendor/UPSTREAM.txt"
make_skill vendor-skill-ok '---
name: vendor-skill-ok
description: "Vendor sync fixture. Use when: '"'"'vendor sync passes'"'"'."
metadata:
  upstream-version: 1.0.0
  synced: 2026-01-01
---

## Purpose

Vendor-backed fixture for the version-paired sync exception.

## Gotchas

None known.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add vendor-skill-ok'
printf 'v2\n' >"$SKILLS/vendor-skill-ok/vendor/UPSTREAM.txt"
make_skill vendor-skill-ok '---
name: vendor-skill-ok
description: "Vendor sync fixture. Use when: '"'"'vendor sync passes'"'"'."
metadata:
  upstream-version: 1.1.0
  synced: 2026-02-01
---

## Purpose

Vendor-backed fixture for the version-paired sync exception.

## Gotchas

None known.
'
out="$(run vendor-skill-ok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'legitimate sync' <<<"$out" && ! grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ diff paired with an upstream-version bump passes (legitimate sync)"
else
  fail "version-paired vendor/ diff should pass (rc=$rc): $out"
fi

mkdir -p "$SKILLS/vendor-skill-bad/vendor"
printf 'v1\n' >"$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt"
make_skill vendor-skill-bad '---
name: vendor-skill-bad
description: "Vendor sync fixture. Use when: '"'"'vendor sync fails'"'"'."
metadata:
  upstream-version: 1.0.0
  synced: 2026-01-01
---

## Purpose

Vendor-backed fixture for the unpaired-edit regression guard.

## Gotchas

None known.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add vendor-skill-bad'
printf 'v2 - hand edited\n' >"$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt"
out="$(run vendor-skill-bad 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ diff without an upstream-version bump still fails (hand-edit guard)"
else
  fail "unpaired vendor/ diff should still fail (rc=$rc): $out"
fi

git -C "$TMP" checkout -q -- "$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt"
git -C "$TMP" mv "$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt" "$SKILLS/vendor-skill-bad/vendor/UPSTREAM.md"
out="$(run vendor-skill-bad 2>&1)"
if grep -q 'only renamed' <<<"$out" && ! grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ pure rename passes check 8"
else
  fail "a pure vendor/ rename should pass check 8: $out"
fi
printf 'renamed and edited\n' >"$SKILLS/vendor-skill-bad/vendor/UPSTREAM.md"
out="$(run vendor-skill-bad 2>&1)"
if grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ rename with an edit still fails check 8"
else
  fail "an edited vendor/ rename should fail check 8: $out"
fi
git -C "$TMP" mv -f "$SKILLS/vendor-skill-bad/vendor/UPSTREAM.md" "$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt"
printf 'v2 - hand edited\n' >"$SKILLS/vendor-skill-bad/vendor/UPSTREAM.txt"

vendor_sha_fixture() {
  make_skill vendor-skill-sha '---
name: vendor-skill-sha
description: "Vendor sha fixture. Use when: '"'"'vendor sha sync'"'"'."
metadata:
  upstream-version: 1.0.0
  upstream-sha: '"$1"'
  synced: 2026-01-01
---

## Purpose

Vendor-backed fixture for the sha-paired sync exception.

## Gotchas

None known.
'
}
# sha256sum where present, else shasum -a 256 (macOS without coreutils), as check 8 does.
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
mkdir -p "$SKILLS/vendor-skill-sha/vendor"
printf 'v1\n' >"$SKILLS/vendor-skill-sha/vendor/UPSTREAM.txt"
printf '{}\n' >"$SKILLS/vendor-skill-sha/vendor/.markdownlint-cli2.jsonc"
vendor_sha_fixture "$(printf 'v1\n' | sha256_of)"
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add vendor-skill-sha'
printf 'v1 republished\n' >"$SKILLS/vendor-skill-sha/vendor/UPSTREAM.txt"
good_sha="$(printf 'v1 republished\n' | sha256_of)"
vendor_sha_fixture "$good_sha"
out="$(run vendor-skill-sha 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'upstream-sha bump matching' <<<"$out" && ! grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ diff paired with a matching upstream-sha bump passes"
else
  fail "sha-paired vendor/ diff should pass (rc=$rc): $out"
fi
bad_sha="$(printf 'something else\n' | sha256_of)"
vendor_sha_fixture "$bad_sha"
out="$(run vendor-skill-sha 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "$bad_sha" <<<"$out" && grep -q "$good_sha" <<<"$out"; then
  pass "vendor/ diff with a non-matching upstream-sha bump fails, naming both hashes"
elif [[ $rc -eq 1 ]] && grep -q 'byte-identical guarantee' <<<"$out"; then
  pass "vendor/ diff with a non-matching upstream-sha bump fails"
else
  fail "a non-matching upstream-sha bump should fail check 8 (rc=$rc): $out"
fi
git -C "$TMP" checkout -q -- "$SKILLS/vendor-skill-sha"

make_skill inj-shell-ok '---
name: inj-shell-ok
description: "Injects context. Use when: '"'"'injecting with a shell decl'"'"'."
shell: bash
---

## Context
- Tree: !`git status --short 2>/dev/null || echo "(clean)"`

## Gotchas

None known.
'
out="$(run inj-shell-ok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'falls through to the PowerShell tool' <<<"$out" && ! grep -q 'look portable but static analysis' <<<"$out"; then
  pass "injection with a shell: declaration is silent (check 19)"
else
  fail "injection + shell: decl should not warn/fail check 19 (rc=$rc): $out"
fi

make_skill inj-bashonly-fail '---
name: inj-bashonly-fail
description: "Injects context. Use when: '"'"'injecting bash-only syntax'"'"'."
---

## Context
- Tree: !`git status --short 2>/dev/null || echo "(clean)"`

## Gotchas

None known.
'
out="$(run inj-bashonly-fail 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'falls through to the PowerShell tool' <<<"$out"; then
  pass "bash-only injection without shell: fails (check 19)"
else
  fail "bash-only injection + no shell: should fail check 19 (rc=$rc): $out"
fi

make_skill inj-portable-warn '---
name: inj-portable-warn
description: "Injects context. Use when: '"'"'injecting portable commands'"'"'."
---

## Context
- Branch: !`git branch --show-current`

## Gotchas

None known.
'
out="$(run inj-portable-warn 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'look portable but static analysis' <<<"$out"; then
  pass "portable-looking injection without shell: warns without failing (check 19)"
else
  fail "portable injection + no shell: should warn not fail (rc=$rc): $out"
fi

make_skill inj-fenced-fail '---
name: inj-fenced-fail
description: "Injects a block. Use when: '"'"'injecting a fenced block'"'"'."
---

## Snapshot

```!
git log --oneline | head -5
```

## Gotchas

None known.
'
out="$(run inj-fenced-fail 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'falls through to the PowerShell tool' <<<"$out"; then
  pass "fenced injection block with bash-only syntax fails (check 19 fence extraction)"
else
  fail "bash-only fenced injection should fail check 19 (rc=$rc): $out"
fi

make_skill inj-plainblock-safe '---
name: inj-plainblock-safe
description: "Shows an example. Use when: '"'"'showing a plain shell example'"'"'."
---

## Example

```bash
git status --short 2>/dev/null | head -5
```

## Gotchas

None known.
'
out="$(run inj-plainblock-safe 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'falls through to the PowerShell tool' <<<"$out" && ! grep -q 'look portable but static analysis' <<<"$out"; then
  pass "bash-only tokens in a plain bash code block do not flag check 19 (scoped to injections)"
else
  fail "plain bash code block should not trip the injection checks (rc=$rc): $out"
fi

make_skill inj-nofallback-warn '---
name: inj-nofallback-warn
description: "Injects context. Use when: '"'"'injecting without a fallback'"'"'."
shell: bash
---

## Context
- Tree: !`git status --short`

## Gotchas

None known.
'
out="$(run inj-nofallback-warn 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'carry no' <<<"$out"; then
  pass "injected command without a || fallback warns (check 20)"
else
  fail "missing || fallback should warn (rc=$rc): $out"
fi

make_skill inj-printf-fallback '---
name: inj-printf-fallback
description: "Injects context. Use when: '"'"'injecting with a printf fallback'"'"'."
shell: bash
---

## Context
- Tree: !`git status --short || printf "(clean)"`

## Gotchas

None known.
'
out="$(run inj-printf-fallback 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'carry no' <<<"$out"; then
  pass "a || printf fallback satisfies check 20 (matches || not echo)"
else
  fail "|| printf should count as a fallback (rc=$rc): $out"
fi

make_skill inj-prose-hashbang '---
name: inj-prose-hashbang
description: "Mentions a shebang. Use when: '"'"'mentioning a shebang in prose'"'"'."
---

## Notes

For a file whose first line is a shebang (`#!`), confirm the recorded mode.

## Gotchas

None known.
'
out="$(run inj-prose-hashbang 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'falls through to the PowerShell tool' <<<"$out" && ! grep -q 'look portable but static analysis' <<<"$out" && ! grep -q 'carry no' <<<"$out"; then
  pass "a mid-token !\` in prose (inline #! code span) is not treated as an injection"
else
  fail "prose #! code span should not trip the injection checks (rc=$rc): $out"
fi

make_skill fe-malformed '---
name: fe-malformed
description: "Fresh-eyes fixture. Use when: '"'"'fe malformed fixture'"'"'."
---

## Steps

<!-- fresh-eyes-exempt deterministic-gate no colon -->

## Gotchas

None known.
'
out="$(run fe-malformed 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'malformed fresh-eyes-exempt' <<<"$out"; then
  pass "malformed fresh-eyes directive fails (check 21)"
else
  fail "malformed fresh-eyes directive should FAIL (rc=$rc): $out"
fi

make_skill fe-unknown-class '---
name: fe-unknown-class
description: "Fresh-eyes fixture. Use when: '"'"'fe unknown class fixture'"'"'."
---

## Steps

<!-- fresh-eyes-exempt: because-i-said-so -- not a real class -->

## Gotchas

None known.
'
out="$(run fe-unknown-class 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'malformed fresh-eyes-exempt' <<<"$out"; then
  pass "unknown fresh-eyes class fails (check 21)"
else
  fail "unknown fresh-eyes class should FAIL (rc=$rc): $out"
fi

make_skill fe-no-reason '---
name: fe-no-reason
description: "Fresh-eyes fixture. Use when: '"'"'fe no reason fixture'"'"'."
---

## Steps

Score each item against the rubric.
<!-- fresh-eyes-exempt: deterministic-gate -->

## Gotchas

None known.
'
out="$(run fe-no-reason 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "missing its '-- <reason>'" <<<"$out"; then
  pass "reason-less fresh-eyes directive fails (check 21)"
else
  fail "reason-less fresh-eyes directive should FAIL (rc=$rc): $out"
fi

make_skill fe-undeclared '---
name: fe-undeclared
description: "Fresh-eyes fixture. Use when: '"'"'fe undeclared fixture'"'"'."
---

## Steps

Self-review the diff before presenting it.

## Gotchas

None known.
'
out="$(run fe-undeclared 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no fresh-context delegation' <<<"$out"; then
  pass "undeclared judgment language warns (check 21)"
else
  fail "undeclared judgment language should WARN and pass (rc=$rc): $out"
fi

make_skill fe-stale '---
name: fe-stale
description: "Fresh-eyes fixture. Use when: '"'"'fe stale fixture'"'"'."
---

## Steps

<!-- fresh-eyes-exempt: external-input -- triage of another author'"'"'s report -->

Nothing here reads like a judgment step.

## Gotchas

None known.
'
out="$(run fe-stale 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'stale fresh-eyes-exempt directive' <<<"$out"; then
  pass "stale fresh-eyes directive warns (check 21)"
else
  fail "stale fresh-eyes directive should WARN and pass (rc=$rc): $out"
fi

make_skill fe-delegated '---
name: fe-delegated
description: "Fresh-eyes fixture. Use when: '"'"'fe delegated fixture'"'"'."
---

## Steps

Self-review the plan by dispatching a fresh-context subagent with the artifact.
Later, score each finding via a fresh context worker, artifact-not-story.

## Gotchas

None known.
'
out="$(run fe-delegated 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'same-context judgment language with no' <<<"$out" &&
  ! grep -q 'stale fresh-eyes-exempt' <<<"$out"; then
  pass "fresh-context delegation prose passes both spellings (check 21)"
else
  fail "delegation prose should satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-called-done '---
name: fe-called-done
description: "Fresh-eyes fixture. Use when: '"'"'fe called done fixture'"'"'."
---

## Steps

Every render is checked by the script, and you read its frames back, before the video
is called done.

## Gotchas

None known.
'
out="$(run fe-called-done 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no fresh-context delegation.*SKILL.md:9)' <<<"$out"; then
  pass "called-done self-check warns (check 21)"
else
  fail "called-done self-check should WARN at SKILL.md:9 and pass (rc=$rc): $out"
fi

make_skill fe-called-done-delegated '---
name: fe-called-done-delegated
description: "Fresh-eyes fixture. Use when: '"'"'fe called done delegated fixture'"'"'."
---

## Steps

Read your own frames to fix what you see. Before calling the video done,
dispatch a fresh-context subagent that judges the frames against the script.

## Gotchas

None known.
'
out="$(run fe-called-done-delegated 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'same-context judgment language with no' <<<"$out" &&
  grep -q 'fresh-context delegation declared nearby' <<<"$out"; then
  pass "called-done with fresh-context judge passes (check 21)"
else
  fail "called-done with fresh-context judge should pass clean (rc=$rc): $out"
fi

make_skill fe-exempt-valid '---
name: fe-exempt-valid
description: "Fresh-eyes fixture. Use when: '"'"'fe exempt valid fixture'"'"'."
---

## Steps

<!-- fresh-eyes-exempt: deterministic-gate -- the test script'"'"'s exit code is the verdict -->
Verify its own output by running the test suite and score each case.

## Gotchas

None known.
'
out="$(run fe-exempt-valid 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'same-context judgment language with no' <<<"$out" &&
  ! grep -q 'stale fresh-eyes-exempt' <<<"$out"; then
  pass "valid exemption directive near judgment language passes (check 21)"
else
  fail "valid exemption directive should satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-fenced '---
name: fe-fenced
description: "Fresh-eyes fixture. Use when: '"'"'fe fenced fixture'"'"'."
---

## Docs

The directive form, shown literally:

```markdown
<!-- fresh-eyes-exempt: bogus-class -- fenced example never scanned -->
Self-review your own work here.
```

Inline span mention: `self-review` stays unscanned.

## Gotchas

None known.
'
out="$(run fe-fenced 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -qE 'fresh-eyes-exempt|same-context judgment' <<<"$out"; then
  pass "fenced/inline-span fresh-eyes content is not scanned (check 21)"
else
  fail "fenced fresh-eyes content should be ignored (rc=$rc): $out"
fi

make_skill fe-contradictory '---
name: fe-contradictory
description: "Fresh-eyes fixture. Use when: '"'"'fe contradictory fixture'"'"'."
---

## Steps

<!-- fresh-eyes-exempt: deterministic-gate -- the suite exit code is the verdict -->
Self-review the output, then dispatch a fresh-context subagent for the verdict.

## Gotchas

None known.
'
out="$(run fe-contradictory 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'contradictory declaration' <<<"$out"; then
  pass "both wording and directive in window notes contradictory (check 21)"
else
  fail "both-declared case should pass with contradictory INFO (rc=$rc): $out"
fi

make_skill fe-fence-info '---
name: fe-fence-info
description: "Fresh-eyes fixture. Use when: '"'"'fe fence info fixture'"'"'."
---

## Docs

```
```yaml
<!-- fresh-eyes-exempt: bogus-class -- info-string line must not close the fence -->
```

## Gotchas

None known.
'
out="$(run fe-fence-info 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'fresh-eyes-exempt' <<<"$out"; then
  pass "info-string fence line does not close the fence (check 21)"
else
  fail "info-string fence line should not desync the fence guard (rc=$rc): $out"
fi

make_skill fe-span-double '---
name: fe-span-double
description: "Fresh-eyes fixture. Use when: '"'"'fe span double fixture'"'"'."
---

## Docs

Span form: `` <!-- fresh-eyes-exempt: bogus-class -- literal --> `` stays unscanned.

## Gotchas

None known.
'
out="$(run fe-span-double 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'fresh-eyes-exempt directive' <<<"$out"; then
  pass "backtick-bearing line declines directive hard verdicts (check 21)"
else
  fail "backtick-bearing line should not FAIL on a literal directive (rc=$rc): $out"
fi

make_skill fe-bare-wording '---
name: fe-bare-wording
description: "Fresh-eyes fixture. Use when: '"'"'fe bare wording fixture'"'"'."
---

## Steps

Self-review the work in a fresh context before presenting it.

## Gotchas

None known.
'
out="$(run fe-bare-wording 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "bare fresh-context wording without a worker still warns (check 21)"
else
  fail "worker-less fresh-context wording should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-verification-word '---
name: fe-verification-word
description: "Fresh-eyes fixture. Use when: '"'"'fe verification word fixture'"'"'."
---

## Steps

Self-review the work in a fresh context before verification.

## Gotchas

None known.
'
out="$(run fe-verification-word 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "verification wording without a worker still warns (check 21)"
else
  fail "verification-word bypass should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-indented-fence '---
name: fe-indented-fence
description: "Fresh-eyes fixture. Use when: '"'"'fe indented fence fixture'"'"'."
---

## Steps

    ```
Regular prose resumes here.

<!-- fresh-eyes-exempt: bogus-class -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-indented-fence 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "indented backtick run does not open a fence (check 21)"
else
  fail "malformed directive after indented code block should FAIL (rc=$rc): $out"
fi

make_skill fe-backtick-info '---
name: fe-backtick-info
description: "Fresh-eyes fixture. Use when: '"'"'fe backtick info fixture'"'"'."
---

## Steps

```markdown `
Regular prose resumes here.

<!-- fresh-eyes-exempt: bogus-class -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-backtick-info 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "backtick-in-info-string run does not open a fence (check 21)"
else
  fail "malformed directive after invalid backtick opener should FAIL (rc=$rc): $out"
fi

make_skill fe-agentless '---
name: fe-agentless
description: "Fresh-eyes fixture. Use when: '"'"'fe agentless fixture'"'"'."
---

## Steps

Self-review the work in a fresh context using an agentless workflow.

## Gotchas

None known.
'
out="$(run fe-agentless 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "embedded worker stem without a whole-word token still warns (check 21)"
else
  fail "agentless stem should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-span-crossline '---
name: fe-span-crossline
description: "Fresh-eyes fixture. Use when: '"'"'fe crossline span fixture'"'"'."
---

## Steps

A literal directive inside a span that crosses a line: `<!-- fresh-eyes-exempt: bogus-class -- literal
example -->` and the prose continues here.

## Gotchas

None known.
'
out="$(run fe-span-crossline 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "backtick-bearing line declines directive hard verdicts (check 21)"
else
  fail "backtick-bearing line should not FAIL on a literal directive (rc=$rc): $out"
fi

make_skill fe-span-stray '---
name: fe-span-stray
description: "Fresh-eyes fixture. Use when: '"'"'fe stray backtick fixture'"'"'."
---

## Steps

A stray unclosed backtick ` ends this paragraph.

<!-- fresh-eyes-exempt: bogus-class -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-span-stray 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "directive on a later line still FAILs after a stray backtick (check 21)"
else
  fail "directive after a stray-backtick line should still FAIL (rc=$rc): $out"
fi

make_skill fe-quoted-fence '---
name: fe-quoted-fence
description: "Fresh-eyes fixture. Use when: '"'"'fe quoted fence fixture'"'"'."
---

## Steps

Quoted example:

> ~~~markdown
> <!-- fresh-eyes-exempt: bogus -- example -->
> ~~~

Prose resumes here.

## Gotchas

None known.
'
out="$(run fe-quoted-fence 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "blockquoted fence still suppresses its content (check 21)"
else
  fail "directive inside a blockquoted fence should not be parsed (rc=$rc): $out"
fi

make_skill fe-escaped-span '---
name: fe-escaped-span
description: "Fresh-eyes fixture. Use when: '"'"'fe escaped span fixture'"'"'."
---

## Steps

Prose showing \`<!-- fresh-eyes-exempt: bogus -- reason -->\` between escaped backticks.

## Gotchas

None known.
'
out="$(run fe-escaped-span 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "backtick-bearing line declines directive hard verdicts (check 21)"
else
  fail "backtick-bearing line should not FAIL on a literal directive (rc=$rc): $out"
fi

make_skill fe-two-directives '---
name: fe-two-directives
description: "Fresh-eyes fixture. Use when: '"'"'fe two directives fixture'"'"'."
---

## Steps

Self-review the output.

<!-- fresh-eyes-exempt: bogus -- unknown class --> <!-- fresh-eyes-exempt: deferred -- tracked -->

## Gotchas

None known.
'
out="$(run fe-two-directives 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "malformed directive beside a valid one still FAILs (check 21)"
else
  fail "shared-line malformed directive should FAIL (rc=$rc): $out"
fi

make_skill fe-refresh-context '---
name: fe-refresh-context
description: "Fresh-eyes fixture. Use when: '"'"'fe refresh context fixture'"'"'."
---

## Steps

Refresh context with agent output, then self-review your work.

## Gotchas

None known.
'
out="$(run fe-refresh-context 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "Refresh-context prose does not declare delegation (check 21)"
else
  fail "\"Refresh context\" should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-nested-quoted-fence '---
name: fe-nested-quoted-fence
description: "Fresh-eyes fixture. Use when: '"'"'fe nested quoted fence fixture'"'"'."
---

## Steps

```markdown
> ```
> <!-- fresh-eyes-exempt: bogus -- x -->
> ```
```

## Gotchas

None known.
'
out="$(run fe-nested-quoted-fence 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "quoted runs inside an unprefixed fence do not close it (check 21)"
else
  fail "nested quoted fence content should stay suppressed (rc=$rc): $out"
fi

# 37p. Check 21: an escaped backslash-< renders literally, so the escaped
#      comment form is text, not an HTML comment, and therefore not a
#      directive at all. The backslash reaches the fixture through ${fe_bs}
#      so neither shell-portability-lint's backslash-< token nor a quote
#      splice shellcheck misreads ever appears on a source line; the fixture
#      bytes are unchanged.
fe_bs="\\"
fe_escaped_body=$(
  cat <<FIXTURE
---
name: fe-escaped-angle
description: "Fresh-eyes fixture. Use when: 'fe escaped angle fixture'."
---

## Steps

Escaped angle bracket renders literally: ${fe_bs}<!-- fresh-eyes-exempt: bogus -- z -->

## Gotchas

None known.
FIXTURE
)
make_skill fe-escaped-angle "$fe_escaped_body
"
out="$(run fe-escaped-angle 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'fresh-eyes-exempt directive' <<<"$out"; then
  pass "escaped angle bracket is not a directive (check 21)"
else
  fail "escaped angle-bracket comment should not parse as a directive (rc=$rc): $out"
fi

make_skill fe-runaway-quoted-fence '---
name: fe-runaway-quoted-fence
description: "Fresh-eyes fixture. Use when: '"'"'fe runaway quoted fence fixture'"'"'."
---

## Steps

> ```markdown
> an unclosed fence inside a blockquote

Top-level prose resumes here.

<!-- fresh-eyes-exempt: bogus -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-runaway-quoted-fence 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "unclosed quoted fence ends with its blockquote (check 21)"
else
  fail "directive after a runaway quoted fence should FAIL (rc=$rc): $out"
fi

make_skill fe-list-fence '---
name: fe-list-fence
description: "Fresh-eyes fixture. Use when: '"'"'fe list fence fixture'"'"'."
---

## Steps

- ```markdown
  <!-- fresh-eyes-exempt: bogus -- suppressed inside the list fence -->
  ```

Top-level prose resumes.

<!-- fresh-eyes-exempt: bogus2 -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-list-fence 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive (SKILL.md:14)' <<<"$out" &&
  ! grep -q 'malformed fresh-eyes-exempt directive (SKILL.md:9)' <<<"$out"; then
  pass "list-opened fence suppresses its body then releases (check 21)"
else
  fail "list fence body should be suppressed and the line-14 directive FAIL (rc=$rc): $out"
fi

make_skill fe-span-literal-backslash '---
name: fe-span-literal-backslash
description: "Fresh-eyes fixture. Use when: '"'"'fe span literal backslash fixture'"'"'."
---

## Steps

Literal `foo\` then <!-- fresh-eyes-exempt: bogus -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-span-literal-backslash 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "backtick-bearing line declines directive hard verdicts (check 21)"
else
  fail "backtick-bearing line should not FAIL on a literal directive (rc=$rc): $out"
fi

make_skill fe-indented-ambiguous '---
name: fe-indented-ambiguous
description: "Fresh-eyes fixture. Use when: '"'"'fe indented ambiguous fixture'"'"'."
---

## Steps

An indented block holding a literal directive:

    <!-- fresh-eyes-exempt: bogus -- indented, so no hard verdict -->

Prose resumes.

## Gotchas

None known.
'
out="$(run fe-indented-ambiguous 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'fresh-eyes-exempt directive' <<<"$out"; then
  pass "four-space-indented directive yields no hard verdict (check 21)"
else
  fail "ambiguous indented directive should not FAIL (rc=$rc): $out"
fi

make_skill fe-quote-depth '---
name: fe-quote-depth
description: "Fresh-eyes fixture. Use when: '"'"'fe quote depth fixture'"'"'."
---

## Steps

> > ~~~markdown
> > a fence opened at depth two
> <!-- fresh-eyes-exempt: bogus -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-quote-depth 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "depth-two fence ends when the inner quote does (check 21)"
else
  fail "directive at lower quote depth should FAIL (rc=$rc): $out"
fi

make_skill fe-comment-wording '---
name: fe-comment-wording
description: "Fresh-eyes fixture. Use when: '"'"'fe comment wording fixture'"'"'."
---

## Steps

<!-- dispatch this to a fresh-context agent -->

Self-review your own work.

## Gotchas

None known.
'
out="$(run fe-comment-wording 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "delegation wording in an HTML comment does not declare (check 21)"
else
  fail "commented wording should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-comment-multiline '---
name: fe-comment-multiline
description: "Fresh-eyes fixture. Use when: '"'"'fe comment multiline fixture'"'"'."
---

## Steps

<!--
dispatch this to a fresh-context agent
-->

Self-review your own work.

## Gotchas

None known.
'
out="$(run fe-comment-multiline 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "delegation wording in a multi-line HTML comment does not declare (check 21)"
else
  fail "multi-line commented wording should not satisfy check 21 (rc=$rc): $out"
fi

make_skill fe-name-prefix '---
name: fe-name-prefix
description: "Fresh-eyes fixture. Use when: '"'"'fe name prefix fixture'"'"'."
---

## Steps

Prose: <!-- fresh-eyes-exemption is explained here -->

## Gotchas

None known.
'
out="$(run fe-name-prefix 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'fresh-eyes-exempt directive' <<<"$out"; then
  pass "a longer name sharing the directive prefix is not a directive (check 21)"
else
  fail "fresh-eyes-exemption prose should not parse as a directive (rc=$rc): $out"
fi

make_skill fe-ambiguous-proximity '---
name: fe-ambiguous-proximity
description: "Fresh-eyes fixture. Use when: '"'"'fe ambiguous proximity fixture'"'"'."
---

## Steps

Self-review your own work.

An indented example:

    <!-- fresh-eyes-exempt: deferred -- literal example, not a live exemption -->

## Gotchas

None known.
'
out="$(run fe-ambiguous-proximity 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'same-context judgment language with no' <<<"$out"; then
  pass "an ambiguous directive does not satisfy a judgment step (check 21)"
else
  fail "indented literal exemption should not silence the WARN (rc=$rc): $out"
fi

make_skill fe-frontmatter-fence '---
name: fe-frontmatter-fence
description: >-
  Fresh-eyes fixture carrying an example fence. Use when: '"'"'fe frontmatter fence fixture'"'"'.
  ```text
  and prose after it.
---

## Steps

<!-- fresh-eyes-exempt: bogus -- wrong class stays malformed -->

## Gotchas

None known.
'
out="$(run fe-frontmatter-fence 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'malformed fresh-eyes-exempt directive' <<<"$out"; then
  pass "a fence inside frontmatter does not suppress the body (check 21)"
else
  fail "directive after a frontmatter fence should FAIL (rc=$rc): $out"
fi

out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -qE 'fresh-eyes|same-context judgment' <<<"$out"; then
  pass "no judgment language stays silent (check 21)"
else
  fail "check 21 should stay silent on good-skill (rc=$rc): $out"
fi

desc_1500="$(printf 'd%.0s' $(seq 1 1500))"
wtu_34="$(printf 'w%.0s' $(seq 1 34))"
make_skill joiner-boundary "---
name: joiner-boundary
description: \"$desc_1500\"
when_to_use: \"$wtu_34\"
---

## Purpose

Boundary fixture: desc(1500) + wtu(34) = 1534 (would pass check 2 if the
joiner were omitted, per the pre-fix bug); + the 3-char joiner = 1537, one
char over the 1536 cap.
"
out="$(run joiner-boundary 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'description+when_to_use is 1537 chars (cap 1536' <<<"$out"; then
  pass "check 2 counts the joiner: a desc+wtu sum at the cap without it now fails at 1537"
else
  fail "check 2 should count the 3-char joiner and fail at 1537/1536 (rc=$rc): $out"
fi

sum_100="$(printf 's%.0s' $(seq 1 100))"
make_skill cap-pass "---
name: cap-pass
description: \"Summary cap fixture. Use when: 'cap pass fixture'.\"
metadata:
  summary: $sum_100
---

## Purpose

Boundary fixture with a summary at exactly the 100-codepoint cap.

## Gotchas

None known.
"
out="$(run cap-pass 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'summary passes the shared contract' <<<"$out"; then
  pass "summary at exactly 100 codepoints passes (check 22)"
else
  fail "100-codepoint summary should pass at the boundary (rc=$rc): $out"
fi

sum_101="$(printf 's%.0s' $(seq 1 101))"
make_skill cap-fail "---
name: cap-fail
description: \"Summary cap fixture. Use when: 'cap fail fixture'.\"
metadata:
  summary: $sum_101
---

## Purpose

Fixture with a summary one codepoint over the cap.

## Gotchas

None known.
"
out="$(run cap-fail 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'metadata.summary is 101 codepoints (cap 100)' <<<"$out"; then
  pass "summary at 101 codepoints fails (check 22)"
else
  fail "101-codepoint summary should FAIL (rc=$rc): $out"
fi

sum_mb="$(printf 's%.0s' $(seq 1 99))—"
make_skill cap-multibyte "---
name: cap-multibyte
description: \"Summary cap fixture. Use when: 'cap multibyte fixture'.\"
metadata:
  summary: $sum_mb
---

## Purpose

Fixture whose summary is 100 codepoints but more than 100 bytes.

## Gotchas

None known.
"
out="$(run cap-multibyte 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'summary passes the shared contract' <<<"$out"; then
  pass "a 100-codepoint summary with a multi-byte em-dash passes (codepoints, not bytes)"
else
  fail "multi-byte 100-codepoint summary should pass (rc=$rc): $out"
fi

# 38d. Check 22: the #3162 regression. An unquoted summary carrying ": " passed
#      this gate while failing CI, because the gate enforced only the cap. It is
#      a YAML mapping indicator: the frontmatter does not parse, and a skill
#      whose frontmatter does not parse loads with EMPTY metadata.
make_skill summary-colon "---
name: summary-colon
description: \"Summary colon fixture. Use when: 'colon fixture'.\"
metadata:
  summary: Classify markdown noise: citations, ghost refs, preamble
---

## Purpose

Fixture whose summary carries a YAML mapping indicator.

## Gotchas

None known.
"
out="$(run summary-colon 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'contains ": "' <<<"$out"; then
  pass "an unquoted summary containing \": \" fails locally (check 22, #3189)"
else
  fail "summary with a mapping indicator should FAIL (rc=$rc): $out"
fi

# 38e. Check 22: the other half of the #3162 regression. Quoting the scalar is
#      the remedy an author reaches for first; it made the YAML parse but failed
#      a different CI gate. The gate must reject it HERE, and its message must
#      point at rewording rather than at quoting.
make_skill summary-quoted "---
name: summary-quoted
description: \"Summary quoting fixture. Use when: 'quoted fixture'.\"
metadata:
  summary: \"Classify markdown noise: citations, ghost refs\"
---

## Purpose

Fixture whose summary was quoted to survive the YAML parse.

## Gotchas

None known.
"
out="$(run summary-quoted 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'reword to a plain unquoted scalar' <<<"$out"; then
  pass "a quoted summary fails and the message names rewording, not quoting (check 22, #3189)"
else
  fail "quoted summary should FAIL with a rewording remedy (rc=$rc): $out"
fi

make_skill summary-decoy '---
name: summary-decoy
description: |
  Block scalar body. Use when: '"'"'decoy fixture'"'"'.
  summary: "decoy: not the real value"
metadata:
  summary: The real summary sits in the metadata block
---

## Purpose

Fixture with a decoy summary line inside a block scalar.

## Gotchas

None known.
'
out="$(run summary-decoy 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'summary passes the shared contract' <<<"$out"; then
  pass "the metadata block is read, not a decoy inside a block scalar (check 22, #3189)"
else
  fail "decoy summary inside a block scalar should not be read (rc=$rc): $out"
fi

make_skill nameless-skill '---
description: "Declares no name. Use when: '"'"'checking the optional name field'"'"'."
---

## Purpose

Fixture that declares no frontmatter name.

## Gotchas

None known.
'
out="$(run nameless-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "missing 'name:'" <<<"$out"; then
  pass "an omitted frontmatter name does not fail the gate"
else
  fail "omitted name should pass (rc=$rc): $out"
fi

PLUGIN_SKILLS="$TMP/plugins/demo/skills"
mkdir -p "$PLUGIN_SKILLS/aliased-skill" "$TMP/plugins/demo/.claude-plugin"
printf '{"name":"demo","version":"0.1.0"}\n' >"$TMP/plugins/demo/.claude-plugin/plugin.json"
printf '%s' '---
name: aliased-skill
description: "Repeats its directory. Use when: '"'"'checking the plugin redundancy warning'"'"'."
disable-model-invocation: false
---

## Purpose

Fixture whose plugin skill repeats its directory name.

## Gotchas

None known.
' >"$PLUGIN_SKILLS/aliased-skill/SKILL.md"
out="$( (cd "$TMP" &&
  CHECK_SKILL_SKILLS_ROOT="$PLUGIN_SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" aliased-skill) 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'repeats the plugin skill' <<<"$out"; then
  pass "a plugin skill repeating its directory name warns without failing"
else
  fail "redundant plugin name should warn, not fail (rc=$rc): $out"
fi

if ! grep -q 'repeats the plugin skill' <<<"$(run quoted-name 2>&1)"; then
  pass "a non-plugin skill repeating its directory name does not warn"
else
  fail "redundancy warning should be plugin-scoped"
fi

mkdir -p "$PLUGIN_SKILLS/xref-host/context" "$PLUGIN_SKILLS/xref-citer"
printf 'Sibling-owned supporting file.\n' >"$PLUGIN_SKILLS/xref-host/context/suppression.md"
printf '%s' '---
description: "Hosts a supporting file. Use when: '"'"'checking cross-skill citations'"'"'."
---

## Purpose

Fixture sibling that owns context/suppression.md.

## Gotchas

None known.
' >"$PLUGIN_SKILLS/xref-host/SKILL.md"
printf '%s' '---
description: "Cites a sibling file. Use when: '"'"'checking cross-skill citations'"'"'."
---

## Purpose

Cites the sibling-owned `context/suppression.md` in the skill-internal form.

## Gotchas

None known.
' >"$PLUGIN_SKILLS/xref-citer/SKILL.md"
out="$( (cd "$TMP" &&
  CHECK_SKILL_SKILLS_ROOT="$PLUGIN_SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" xref-citer) 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'broken skill-internal ref: context/suppression.md' <<<"$out" &&
  grep -q "sibling skill 'xref-host'" <<<"$out" &&
  grep -qF '${CLAUDE_PLUGIN_ROOT}/skills/xref-host/context/suppression.md' <<<"$out" &&
  grep -q 'hand-verify the line' <<<"$out"; then
  pass "a sibling-hosted ref names the sibling and the plugin-root form"
else
  fail "sibling-hosted ref should name the sibling and the plugin-root form (rc=$rc): $out"
fi

mkdir -p "$SKILLS/plain-host/reference"
printf 'Sibling-owned supporting file.\n' >"$SKILLS/plain-host/reference/scaling.md"
make_skill plain-host '---
description: "Hosts a supporting file. Use when: '"'"'checking non-plugin cross-skill citations'"'"'."
---

## Purpose

Fixture sibling that owns reference/scaling.md.

## Gotchas

None known.
'
make_skill plain-citer '---
description: "Cites a sibling file. Use when: '"'"'checking non-plugin cross-skill citations'"'"'."
---

## Purpose

Cites the sibling-owned `reference/scaling.md` in the skill-internal form.

## Gotchas

None known.
'
out="$(run plain-citer 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q "sibling skill 'plain-host'" <<<"$out" &&
  grep -q '\.\./plain-host/reference/scaling\.md' <<<"$out" &&
  ! grep -q 'skills/plain-host/reference/scaling\.md' <<<"$out"; then
  pass "outside a plugin the sibling message names the relative form, not the plugin root"
else
  fail "non-plugin sibling message should name ../plain-host/... (rc=$rc): $out"
fi

make_skill orphan-citer '---
description: "Cites a file nobody owns. Use when: '"'"'checking the broken-ref message'"'"'."
---

## Purpose

Cites `context/nowhere-at-all.md`, which no skill in this root owns.

## Gotchas

None known.
'
out="$(run orphan-citer 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'broken skill-internal ref: context/nowhere-at-all.md' <<<"$out" &&
  ! grep -q 'sibling skill' <<<"$out"; then
  pass "a ref no sibling hosts keeps the plain broken-internal-ref message"
else
  fail "unhosted ref should keep the broken-internal-ref message (rc=$rc): $out"
fi

# 36d. Check 5: a backslash-separated pointer FAILs in its own right, naming the
#      forward-slash form. The resolve loop never sees such a path (its
#      char-class has no backslash), so without this limb a Windows-authored
#      pointer skipped the check silently. Both citation forms are covered; the
#      file existing under the skill does not rescue it, because the defect is
#      the separator (rejected at plugin load on macOS and Linux), not a miss.
mkdir -p "$SKILLS/backslash-citer/scripts" "$SKILLS/backslash-citer/reference"
printf 'echo helper\n' >"$SKILLS/backslash-citer/scripts/helper.py"
printf 'guide\n' >"$SKILLS/backslash-citer/reference/guide.md"
make_skill backslash-citer '---
description: "Cites files with backslashes. Use when: '"'"'checking backslash pointers'"'"'."
---

## Purpose

Run `scripts\helper.py` first, then read [the guide](reference\guide.md#setup).

## Gotchas

None known.
'
out="$(run backslash-citer 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'backslash path separator in skill-internal ref: scripts\\helper.py' <<<"$out" &&
  grep -q 'write it with forward slashes: scripts/helper.py' <<<"$out" &&
  grep -q 'backslash path separator in skill-internal ref: reference\\guide.md' <<<"$out"; then
  pass "a backslash-separated pointer fails and names the forward-slash form"
else
  fail "backslash pointers should fail in both citation forms (rc=$rc): $out"
fi

mkdir -p "$SKILLS/escape-prose/scripts"
printf 'echo update\n' >"$SKILLS/escape-prose/scripts/update.sh"
make_skill escape-prose '---
description: "Carries prose escapes. Use when: '"'"'checking backslash false positives'"'"'."
---

## Purpose

Run `scripts/update.sh [--check\|--apply]`; the scripts\_dir note uses `\n` between context\ lines.

## Gotchas

None known.
'
out="$(run escape-prose 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'backslash path separator' <<<"$out"; then
  pass "prose escapes near an internal-dir token do not trip the backslash limb"
else
  fail "prose escapes should not trip the backslash limb (rc=$rc): $out"
fi

mkdir -p "$SKILLS/backslash-spoke/scripts" "$SKILLS/backslash-spoke/reference/topic"
printf 'echo helper\n' >"$SKILLS/backslash-spoke/scripts/helper.py"
make_skill backslash-spoke '---
description: "Clean hub over a spoke with a backslash pointer. Use when: '"'"'checking spoke backslash pointers'"'"'."
---

## Purpose

See `reference/usage.md` and `reference/topic/notes.md`.

## Gotchas

None known.
'
printf '# Usage\n\nRun `scripts\\helper.py` before anything else.\n' >"$SKILLS/backslash-spoke/reference/usage.md"
printf '# Notes\n\nDetails in [the helper](scripts\\helper.py).\n' >"$SKILLS/backslash-spoke/reference/topic/notes.md"
out="$(run backslash-spoke 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'backslash path separator in skill-internal ref: scripts\\helper.py (cited at reference/usage.md:3)' <<<"$out" &&
  grep -q 'backslash path separator in skill-internal ref: scripts\\helper.py (cited at reference/topic/notes.md:3)' <<<"$out"; then
  pass "a backslash pointer inside a spoke fails and names the citing file, nested spokes included"
else
  fail "backslash pointers inside spokes should fail and name the file (rc=$rc): $out"
fi

make_skill no-evals '---
description: "A plain skill. Use when: '"'"'checking evals presence'"'"'."
---

## Purpose

Not action-router-shaped.

## Gotchas

None known.
'
out="$(run_require_evals no-evals 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "--require-evals fails when evals/evals.json is absent"
else
  fail "--require-evals should fail without evals (rc=$rc): $out"
fi

out="$(run no-evals 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "legacy fleet: non-action-router without evals passes without --require-evals"
else
  fail "non-action-router without evals should pass without --require-evals (rc=$rc): $out"
fi

git -C "$TMP" add -A && git -C "$TMP" commit -qm base >/dev/null
make_skill brand-new '---
description: "A brand-new skill. Use when: '"'"'checking new-skill evals'"'"'."
---

## Purpose

New-skill ratchet fixture.

## Gotchas

None known.
'
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  CHECK_SKILL_BASE_REF=HEAD bash "$SUT" --require-evals brand-new 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "--require-evals fails for a new skill without evals"
else
  fail "new skill without evals should fail under --require-evals (rc=$rc): $out"
fi

out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  CHECK_SKILL_REQUIRE_EVALS=1 bash "$SUT" no-evals 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "CHECK_SKILL_REQUIRE_EVALS=1 mirrors --require-evals"
else
  fail "CHECK_SKILL_REQUIRE_EVALS=1 should fail without evals (rc=$rc): $out"
fi

CACHE_TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP"' EXIT
CACHE_SKILLS="$CACHE_TMP/marketplace/disk-hygiene/0.17.9/skills"
mkdir -p "$CACHE_SKILLS/clean"
cat >"$CACHE_SKILLS/clean/SKILL.md" <<'EOF'
---
description: "Clean disk. Use when: 'disk full' or 'clean cache'."
---

## Purpose

Fixture skill shaped like a marketplace cache install (no .git).

## Gotchas

None known.
EOF
# Isolate from ambient git: empty GIT_DIR would still walk parents; run from
# the non-git cache tree itself with GIT_DIR unset.
out="$(
  cd "$CACHE_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      CHECK_SKILL_SKILLS_ROOT="$CACHE_SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" clean 2>&1
)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'PASS' <<<"$out" &&
  ! grep -q 'Error: not in a git repo' <<<"$out" &&
  grep -q 'trigger-keyword preservation (check 3) skipped' <<<"$out" &&
  grep -q 'committed-artifact scan (check 13) skipped' <<<"$out"; then
  pass "non-git plugin-cache tree: check-skill runs and skips git-backed checks"
else
  fail "non-git plugin-cache tree should PASS with git checks skipped (rc=$rc): $out"
fi

out="$(
  cd "$CACHE_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
      CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" clean 2>&1
)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no skills root set' <<<"$out"; then
  pass "outside git with no skills root still exits 2 naming the missing root"
else
  fail "outside git with no skills root should exit 2 (rc=$rc): $out"
fi

make_skill cc-signal-missing '---
name: cc-signal-missing
description: "Rotate the config. Use when: '"'"'rotating the config'"'"'."
---

## Steps

1. Open the config file.
2. Update the rotation value.
3. Save the file.

## Gotchas

None known.
'
out="$(run cc-signal-missing 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'completion-criteria signal' <<<"$out"; then
  pass "3-step procedure without any completion signal warns (completion-criteria)"
else
  fail "signal-free numbered procedure should warn (rc=$rc): $out"
fi

make_skill cc-signal-present '---
name: cc-signal-present
description: "Rotate the config safely. Use when: '"'"'rotating the config safely'"'"'."
---

## Steps

1. Open the config file.
2. Update the rotation value.
3. Save the file; the step is done when `validate --config` exits 0.

## Gotchas

None known.
'
out="$(run cc-signal-present 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'completion-criteria signal.*no completion' <<<"$out" && ! grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "procedure with a done-condition does not warn (completion-criteria)"
else
  fail "signal-carrying procedure should not warn (rc=$rc): $out"
fi

make_skill cc-signal-mixed-fence '---
name: cc-signal-mixed-fence
description: "Show fence forms. Use when: '"'"'showing fence forms'"'"'."
---

## Example

```markdown
You can also use ~~~ fences:

~~~text
1. Open the config file.
2. Update the rotation value.
3. Save the file.
~~~
```

## Gotchas

None known.
'
out="$(run cc-signal-mixed-fence 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "literal tilde markers inside a backtick fence stay masked (matching-close)"
else
  fail "mixed fence markers should not unmask fenced content (rc=$rc): $out"
fi

make_skill cc-signal-adjacent '---
name: cc-signal-adjacent
description: "Two short flows. Use when: '"'"'running two short flows'"'"'."
---

## Flow A then flow B

1. Open the first file.
2. Update the first value.

1. Open the second file.
2. Update the second value.

## Gotchas

None known.
'
out="$(run cc-signal-adjacent 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "adjacent 2-step lists split at the numbering restart (no spurious warn)"
else
  fail "adjacent short lists should not merge into a warnable block (rc=$rc): $out"
fi

make_skill cc-signal-loose '---
name: cc-signal-loose
description: "Rotate the loose config. Use when: '"'"'rotating the loose config'"'"'."
---

## Steps

1. Open the config file.

2. Update the rotation value.

3. Save the file.

## Gotchas

None known.
'
out="$(run cc-signal-loose 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "loose ascending 3-step list stays one block and warns when signal-free"
else
  fail "loose signal-free procedure should still warn (rc=$rc): $out"
fi

make_skill cc-signal-tilde '---
name: cc-signal-tilde
description: "Show a tilde sample plan. Use when: '"'"'showing a tilde sample plan'"'"'."
---

## Example output

~~~text
1. Open the config file.
2. Update the rotation value.
3. Save the file.
~~~

## Gotchas

None known.
'
out="$(run cc-signal-tilde 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "tilde-fenced numbered list is ignored by the completion-criteria heuristic"
else
  fail "tilde-fenced list should not fire the completion-criteria warn (rc=$rc): $out"
fi

make_skill cc-signal-fenced '---
name: cc-signal-fenced
description: "Show a sample plan. Use when: '"'"'showing a sample plan'"'"'."
---

## Example output

```text
1. Open the config file.
2. Update the rotation value.
3. Save the file.
```

## Gotchas

None known.
'
out="$(run cc-signal-fenced 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'carry no completion-criteria signal' <<<"$out"; then
  pass "fenced numbered list is ignored by the completion-criteria heuristic"
else
  fail "fenced list should not fire the completion-criteria warn (rc=$rc): $out"
fi

make_skill dmi-explicit-false '---
name: dmi-explicit-false
description: "State the mode. Use when: '"'"'stating the mode'"'"'."
disable-model-invocation: false
---

## Purpose

A skill that states its invocation mode.

## Gotchas

None known.
'
out="$(run dmi-explicit-false 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'invocation mode: model-invoked' <<<"$out" &&
  ! grep -q 'no explicit disable-model-invocation key' <<<"$out"; then
  pass "explicit disable-model-invocation: false reports the fleet default"
else
  fail "explicit false should report the model-invoked default (rc=$rc): $out"
fi

out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: frontmatter has no explicit disable-model-invocation key' <<<"$out"; then
  pass "missing key outside plugins/ warns without failing"
else
  fail "missing key outside plugins/ should warn, not fail (rc=$rc): $out"
fi

mkdir -p "$PLUGIN_SKILLS/dmi-plugin-missing"
printf '%s' '---
name: dmi-plugin-missing
description: "Omit the mode. Use when: '"'"'omitting the mode'"'"'."
---

## Purpose

A plugin skill missing its invocation mode.

## Gotchas

None known.
' >"$PLUGIN_SKILLS/dmi-plugin-missing/SKILL.md"
out="$( (cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$PLUGIN_SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" dmi-plugin-missing) 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: frontmatter has no explicit disable-model-invocation key' <<<"$out"; then
  pass "missing key inside plugins/*/skills/* fails"
else
  fail "missing key inside plugins/ should fail (rc=$rc): $out"
fi

make_skill dmi-bad-value '---
name: dmi-bad-value
description: "State a bad mode. Use when: '"'"'stating a bad mode'"'"'."
disable-model-invocation: maybe
---

## Purpose

A skill whose invocation mode is not a boolean.

## Gotchas

None known.
'
out="$(run dmi-bad-value 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "disable-model-invocation is 'maybe'" <<<"$out"; then
  pass "non-boolean disable-model-invocation fails"
else
  fail "non-boolean value should fail (rc=$rc): $out"
fi

# 24d-spellings. Boolean frontmatter accepts `yes`, `no`, `on`, `off`, `1` and
#      `0` in any letter case beside `true` and `false`
#      (https://code.claude.com/docs/en/skills#frontmatter-reference).
assert_dmi_spelling() {
  local spelling="$1" expected="$2" name
  name="dmi-spelling-$(tr '[:upper:]' '[:lower:]' <<<"$spelling")"
  make_skill "$name" "---
name: $name
description: \"State the mode. Use when: 'stating the mode'.\"
disable-model-invocation: $spelling
---

## Purpose

A skill that spells its invocation mode another way.

## Gotchas

None known.
"
  out="$(run "$name" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]] && grep -q "invocation mode: $expected" <<<"$out"; then
    pass "disable-model-invocation: $spelling reads as $expected"
  else
    fail "disable-model-invocation: $spelling should read as $expected (rc=$rc): $out"
  fi
}
for spelling in yes YES on 1; do assert_dmi_spelling "$spelling" user-invoked; done
for spelling in no OFF 0; do assert_dmi_spelling "$spelling" model-invoked; done

make_skill dmi-quoted-value '---
name: dmi-quoted-value
description: "Quote the mode. Use when: '"'"'quoting the mode'"'"'."
disable-model-invocation: "false"
---

## Purpose

A skill whose invocation mode is a quoted string.

## Gotchas

None known.
'
out="$(run dmi-quoted-value 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'quoted string' <<<"$out"; then
  pass "a quoted boolean fails as the YAML string it is"
else
  fail "quoted boolean should fail (rc=$rc): $out"
fi

make_skill dmi-split-value '---
name: dmi-split-value
description: "Split the mode. Use when: '"'"'splitting the mode'"'"'."
disable-model-invocation: fa lse
---

## Purpose

A skill whose invocation mode carries an internal space.

## Gotchas

None known.
'
out="$(run dmi-split-value 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'expected a boolean: true, yes, on or 1, or false, no, off or 0' <<<"$out"; then
  pass "internal whitespace is not collapsed into a passing boolean"
else
  fail "internally-spaced value should fail (rc=$rc): $out"
fi

make_skill dmi-commented-value '---
name: dmi-commented-value
description: "Annotate the mode. Use when: '"'"'annotating the mode'"'"'."
disable-model-invocation: true # class (i) — mutating fleet sync, manual timing
---

## Purpose

A skill annotating its exception class inline.

## Gotchas

None known.
'
out="$(run dmi-commented-value 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'hand-verify it against an exception class' <<<"$out"; then
  pass "a trailing exception-class comment leaves the boolean valid"
else
  fail "commented boolean should stay valid (rc=$rc): $out"
fi

make_skill dmi-true-nonsetup '---
name: dmi-true-nonsetup
description: "Hide from the model. Use when: '"'"'hiding from the model'"'"'."
disable-model-invocation: true
---

## Purpose

A user-invoked-only skill that is not a setup skill.

## Gotchas

None known.
'
out="$(run dmi-true-nonsetup 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'hand-verify it against an exception class' <<<"$out" &&
  ! grep -q 'WARN.*exception class' <<<"$out"; then
  pass "non-setup true is noted for hand-verification, not warned"
else
  fail "non-setup true should emit a hand-verify note (rc=$rc): $out"
fi

make_skill setup '---
name: setup
description: "Install the thing. Use when: '"'"'installing the thing'"'"'."
disable-model-invocation: true
---

## Purpose

The setup skill.

## Gotchas

None known.
'
out="$(run setup 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'exception class (ii), setup contract' <<<"$out"; then
  pass "setup skill's true is attributed to class (ii) deterministically"
else
  fail "setup skill should be attributed to class (ii) (rc=$rc): $out"
fi

make_skill audit '---
name: audit
description: "Rewrites the files it reviews. Use when: '"'"'rewriting reviewed files'"'"'."
disable-model-invocation: false
---

## Purpose

An audit skill whose listing text advertises mutation.

## Gotchas

None known.
'
out="$(run audit 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'description/verb-contract mismatch' <<<"$out" &&
  grep -q "leaf verb 'audit' is a read-only findings report" <<<"$out"; then
  pass "audit verb + mutate-advertising description fails (verb-contract)"
else
  fail "audit+mutate-desc should fail (rc=$rc): $out"
fi

make_skill audit-fixok '---
name: audit-fixok
description: "Reports findings and remediates them. Use when: '"'"'auditing config'"'"'; pass --fix to apply auto-correctable findings."
disable-model-invocation: false
---

## Purpose

harness-config:audit [--fix] is the compliant precedent.

## Gotchas

None known.
'
out="$(run audit-fixok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "audit + --fix override in the listing is silent (compliant shape)"
else
  fail "audit+--fix should not warn (rc=$rc): $out"
fi

make_skill fix '---
name: fix
description: "Read-only findings report. Use when: '"'"'reporting findings'"'"'."
disable-model-invocation: false
---

## Purpose

A fix skill whose listing text claims it does not mutate.

## Gotchas

None known.
'
out="$(run fix 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'description/verb-contract mismatch' <<<"$out" &&
  grep -q "leaf verb 'fix' mutates the target" <<<"$out"; then
  pass "fix verb + read-only description fails (verb-contract)"
else
  fail "fix+readonly-desc should fail (rc=$rc): $out"
fi

make_skill report-then-write '---
name: report-then-write
description: "Read-only findings report. Use when: '"'"'reporting then writing'"'"'."
disable-model-invocation: false
---

## Purpose

On bare invocation, edit the tracked files in place.

## Gotchas

None known.
'
out="$(run report-then-write 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'description/verb-contract mismatch' <<<"$out" &&
  grep -q 'body mutates on bare invocation' <<<"$out"; then
  pass "read-only description + bare-mutate body fails (verb-contract)"
else
  fail "readonly-desc+bare-mutate-body should fail (rc=$rc): $out"
fi

make_skill advertise-no-write '---
name: advertise-no-write
description: "Rewrites the files you point at. Use when: '"'"'rewriting pointed files'"'"'."
disable-model-invocation: false
---

## Purpose

This skill never mutates anything; it only reports.

## Gotchas

None known.
'
out="$(run advertise-no-write 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'description/verb-contract mismatch' <<<"$out" &&
  grep -q 'description lead advertises fixing' <<<"$out"; then
  pass "mutate-advertising description + never-mutates body fails (verb-contract)"
else
  fail "mutate-desc+never-mutate-body should fail (rc=$rc): $out"
fi

make_skill audit-trigger-fix '---
name: audit-trigger-fix
description: "Emit a findings report. Use when: '"'"'fix the formatting'"'"'."
disable-model-invocation: false
---

## Purpose

Trigger-list "fix" is not a mutate advertisement.

## Gotchas

None known.
'
out="$(run audit-trigger-fix 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "Use-when 'fix' trigger does not advertise mutation"
else
  fail "trigger-list fix should not warn (rc=$rc): $out"
fi

make_skill clean '---
name: clean
description: "Inventory leftovers and optionally remove them after approval. Read-only by default. Use when: '"'"'cleaning leftovers'"'"'."
disable-model-invocation: false
---

## Purpose

Hybrid clean skill; default is read-only.

## Gotchas

None known.
'
out="$(run clean 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "read-only by default on a clean verb is silent"
else
  fail "read-only-by-default should not warn (rc=$rc): $out"
fi

make_skill audit-noun '---
name: audit-noun
description: "Emits a findings report; remediation only when pre-approved. It never deletes, prunes, or rewrites. Use when: '"'"'auditing with a noun'"'"'."
disable-model-invocation: false
---

## Purpose

Noun and negated-list must not read as mutate-advertising.

## Gotchas

None known.
'
out="$(run audit-noun 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "remediation-noun and negated rewrites list are silent"
else
  fail "noun/negated-list should not warn (rc=$rc): $out"
fi

make_skill audit-fenced '---
name: audit-fenced
description: "Read-only findings report. Use when: '"'"'showing a fenced example'"'"'."
disable-model-invocation: false
---

## Example

```text
On bare invocation, edit the tracked files in place.
This skill never mutates anything.
```

## Gotchas

None known.
'
out="$(run audit-fenced 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "fenced mismatch language is ignored by the body limbs"
else
  fail "fenced body example should not warn (rc=$rc): $out"
fi

make_skill fix-ok '---
name: fix-ok
description: "Rewrites the files that fail the gate. Use when: '"'"'rewriting failing files'"'"'."
disable-model-invocation: false
---

## Purpose

On bare invocation, rewrite the failing files. The step is done when the gate exits 0.

## Gotchas

None known.
'
out="$(run fix-ok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "consistent fix verb + mutate description + mutate body is silent"
else
  fail "consistent fix skill should not warn (rc=$rc): $out"
fi

make_skill audit-never-rewrite '---
name: audit-never-rewrite
description: "Reports findings and never rewrites the files. Use when: '"'"'reporting without rewriting'"'"'."
disable-model-invocation: false
---

## Purpose

Negated rewrite clause must not read as mutate-advertising.

## Gotchas

None known.
'
out="$(run audit-never-rewrite 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "never-rewrites-the-files is silent (negated mutate verb)"
else
  fail "never-rewrites-the-files should not warn (rc=$rc): $out"
fi

make_skill fix-scoped '---
name: fix-scoped
description: "Fixes the source files but does not modify vendored dependencies. Use when: '"'"'fixing sources only'"'"'."
disable-model-invocation: false
---

## Purpose

On bare invocation, rewrite the failing source files. The step is done when the gate exits 0.

## Gotchas

None known.
'
out="$(run fix-scoped 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'description/verb-contract mismatch' <<<"$out"; then
  pass "scoped does-not-modify next to a mutate lead is silent"
else
  fail "scoped does-not-modify should not warn (rc=$rc): $out"
fi

out="$(CHECK_SKILL_ONLY=25 run audit 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "leaf verb 'audit' is a read-only findings report" <<<"$out" &&
  grep -q '^CHECK-SKILL audit: FAIL — 1 error(s), 0 warning(s)$' <<<"$out" &&
  ! grep -q 'description length' <<<"$out"; then
  pass "CHECK_SKILL_ONLY=25 fails a check-25 mismatch and runs nothing else"
else
  fail "CHECK_SKILL_ONLY=25 on a mismatch should fail on check 25 alone (rc=$rc): $out"
fi

out="$(CHECK_SKILL_ONLY=25 run bad-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q '^CHECK-SKILL bad-skill: PASS' <<<"$out"; then
  pass "CHECK_SKILL_ONLY=25 skips the other checks"
else
  fail "CHECK_SKILL_ONLY=25 should skip check 1 (rc=$rc): $out"
fi

out="$(CHECK_SKILL_ONLY=7 run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'CHECK_SKILL_ONLY=7 is not supported' <<<"$out"; then
  pass "an unsupported CHECK_SKILL_ONLY value exits 2"
else
  fail "CHECK_SKILL_ONLY=7 should exit 2 (rc=$rc): $out"
fi

toc_hub='---
description: "Routes to a long spoke. Use when: '"'"'checking the spoke TOC heuristic'"'"'."
disable-model-invocation: false
---

## Purpose

Read `reference/x.md` for the long form.

## Gotchas

None known.
'
make_skill toc-long "$toc_hub"
mkdir -p "$SKILLS/toc-long/reference"
{
  printf '# Long spoke\n\n'
  for ((i = 1; i <= 299; i++)); do printf 'line %s\n' "$i"; done
} >"$SKILLS/toc-long/reference/x.md"
out="$(run toc-long 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'WARN: reference/x.md is 301 lines with no table of contents in its first 40 lines' <<<"$out"; then
  pass "a 301-line spoke without a TOC warns and still passes"
else
  fail "a 301-line spoke without a TOC should WARN (rc=$rc): $out"
fi

make_skill toc-present "$toc_hub"
mkdir -p "$SKILLS/toc-present/reference"
{
  printf '# Long spoke\n\n## Contents\n\n- [One](#one)\n- [Two](#two)\n- [Three](#three)\n\n## One\n\n'
  for ((i = 1; i <= 291; i++)); do printf 'line %s\n' "$i"; done
} >"$SKILLS/toc-present/reference/x.md"
out="$(run toc-present 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'no table of contents' <<<"$out"; then
  pass "a long spoke with a three-link TOC does not warn"
else
  fail "a long spoke with a TOC should not warn (rc=$rc): $out"
fi

make_skill toc-short "$toc_hub"
mkdir -p "$SKILLS/toc-short/reference"
{
  printf '# Short spoke\n\n'
  for ((i = 1; i <= 148; i++)); do printf 'line %s\n' "$i"; done
} >"$SKILLS/toc-short/reference/x.md"
out="$(run toc-short 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'no table of contents' <<<"$out"; then
  pass "a 150-line spoke without a TOC does not warn"
else
  fail "a 150-line spoke without a TOC should not warn (rc=$rc): $out"
fi

make_skill toc-nested '---
description: "Routes to a nested long spoke. Use when: '"'"'checking the nested spoke TOC heuristic'"'"'."
disable-model-invocation: false
---

## Purpose

Read `reference/topic/details.md` for the long form.

## Gotchas

None known.
'
mkdir -p "$SKILLS/toc-nested/reference/topic"
{
  printf '# Nested long spoke\n\n'
  for ((i = 1; i <= 304; i++)); do printf 'line %s\n' "$i"; done
} >"$SKILLS/toc-nested/reference/topic/details.md"
out="$(run toc-nested 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'WARN: reference/topic/details.md is 306 lines with no table of contents in its first 40 lines' <<<"$out"; then
  pass "a long nested spoke without a TOC warns and names its path from the skill root"
else
  fail "a long nested spoke without a TOC should WARN (rc=$rc): $out"
fi

# Portability guard: no ERE interval expressions in the checker's awk regexes.
#
# Every other assertion here is black-box, but this failure mode is invisible to
# a black-box run on the CI runner: gawk compiles intervals happily, so a
# reintroduced interval passes the whole suite on CI and only breaks for
# consumers on mawk — silently, because mawk 1.3.4 panics out of the awk program
# before it emits a record and mawk 1.3.3 matches the braces as literal text.
# Either way the affected check reports a clean run over a file it never
# scanned, which is the worst shape a gate can fail in. A source-level assertion
# is the only form that fires on a gawk runner, so it is deliberately
# implementation-aware.
#
# All three interval forms are rejected, {n} included: mawk panics on an
# exact-count interval before a group (a{3}(b)) exactly as it does on the
# a{0,3}(b) that motivated this guard, so a comma-only pattern would leave the
# same silent-failure class open.
#
# Scoped to what awk actually compiles, because Bash is not mawk and its own
# [[ =~ ]] regexes may use intervals freely — check-skill.sh dates a frontmatter
# synced: value with one, and rejecting it would be a false positive on correct
# code. Two surfaces reach awk:
# slash-delimited regex literals inside the embedded programs, and the judge
# regex handed across with -v.
INTERVAL_RE='\{[0-9]+(,[0-9]*)?\}'
interval_hits="$(
  {
    grep -nE "/[^/]*${INTERVAL_RE}[^/]*/" "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#'
    grep -nE "^[[:space:]]*FRESH_EYES_JUDGE_RE=.*${INTERVAL_RE}" "$SUT"
  } 2>/dev/null
)"
if [[ -n "$interval_hits" ]]; then
  fail "awk regexes must contain no ERE interval expressions (mawk-portability): ${interval_hits//$'\n'/ | }"
else
  pass "awk regexes are free of ERE interval expressions (mawk-portable)"
fi



run_with_baseline() {
  local baseline="$1"
  shift
  (cd "$TMP" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      CHECK_SKILL_DESC_FIELD_BASELINE="$baseline" \
      bash "$SUT" "$@")
}

desc_1025="$(printf 'd%.0s' $(seq 1 1025))"
make_skill field-cap-over "---
name: field-cap-over
description: \"$desc_1025\"
---

## Purpose

Field-cap fixture: description alone is 1025 chars, one over the 1024 spec
field maximum, while the assembled listing entry stays well under 1536.
"
out="$(run field-cap-over 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: description alone is 1025 codepoints' <<<"$out"; then
  pass "check 2b fails at 1025, one codepoint over the field maximum"
else
  fail "check 2b should FAIL at 1025/1024 (rc=$rc): $out"
fi

desc_1024="$(printf 'd%.0s' $(seq 1 1024))"
make_skill field-cap-exact "---
name: field-cap-exact
description: \"$desc_1024\"
---

## Purpose

Field-cap fixture: description alone is exactly 1024 chars, the spec maximum,
which is legal but has no headroom left.
"
out="$(run field-cap-exact 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  ! grep -q 'description alone is' <<<"$out" &&
  grep -q 'description is 1024 codepoints, within 32 of the Agent Skills spec field maximum 1024 — 0 left' <<<"$out"; then
  pass "check 2b warns but does not fail at exactly 1024 (the cap is >1024, not >=)"
else
  fail "check 2b should WARN with 0 left, not FAIL, at exactly 1024 (rc=$rc): $out"
fi

desc_993="$(printf 'd%.0s' $(seq 1 993))"
make_skill field-cap-margin-in "---
name: field-cap-margin-in
description: \"$desc_993\"
---

## Purpose

Margin fixture: 993 codepoints, the first count inside the 32-codepoint
approach margin below the 1024 field maximum.
"
out="$(run field-cap-margin-in 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'field-cap-margin-in: description is 993 codepoints, within 32 of the Agent Skills spec field maximum 1024 — 31 left' <<<"$out"; then
  pass "check 2b warns at 993, the first count inside the margin, naming the skill and count"
else
  fail "check 2b should WARN at 993 naming the skill and 31 left (rc=$rc): $out"
fi

desc_992="$(printf 'd%.0s' $(seq 1 992))"
make_skill field-cap-margin-out "---
name: field-cap-margin-out
description: \"$desc_992\"
---

## Purpose

Margin fixture: 992 codepoints, exactly cap minus margin, the last count
outside the approach band.
"
out="$(run field-cap-margin-out 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  ! grep -q 'within 32 of the Agent Skills spec field maximum' <<<"$out" &&
  grep -q 'description field 992/1024 codepoints' <<<"$out"; then
  pass "check 2b stays quiet at 992, exactly cap minus margin"
else
  fail "check 2b should not warn at 992 (rc=$rc): $out"
fi

desc_1100="$(printf 'd%.0s' $(seq 1 1100))"
wtu_40="$(printf 'w%.0s' $(seq 1 40))"
make_skill field-cap-independent "---
name: field-cap-independent
description: \"$desc_1100\"
when_to_use: \"$wtu_40\"
---

## Purpose

Independence fixture: the assembled entry is 1143 chars (passes check 2) while
the description field alone is 1100 (breaches check 2b).
"
out="$(run field-cap-independent 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'FAIL: description alone is 1100 codepoints' <<<"$out" &&
  ! grep -q 'description+when_to_use is .* chars (cap 1536' <<<"$out"; then
  pass "check 2b fires on a field breach that check 2's listing cap does not see"
else
  fail "check 2b should catch desc 1100 while check 2 passes the 1143 entry (rc=$rc): $out"
fi

# 2b-iv. Codepoints, not bytes. 600 'é' is 600 characters and 1200 UTF-8 bytes;
#        the spec's limit is "Maximum 1024 characters", so this must stay silent.
#        Run under LC_ALL=C, where `${#var}` degrades to byte counting and would
#        report 1200 — now a hard FAIL rather than a warning, so a byte-counting
#        implementation cannot slip past this assertion.
desc_600_multibyte="$(printf 'é%.0s' $(seq 1 600))"
make_skill field-cap-multibyte "---
name: field-cap-multibyte
description: \"$desc_600_multibyte\"
---

## Purpose

Multibyte fixture: 600 codepoints, 1200 UTF-8 bytes. Legal against a 1024
character cap; a byte count would report 1200 and fail the run.
"
out="$(LC_ALL=C run field-cap-multibyte 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  ! grep -q 'description alone is' <<<"$out" &&
  grep -q 'description field 600/1024 codepoints' <<<"$out"; then
  pass "check 2b counts codepoints, not bytes (600 multibyte chars stay silent under LC_ALL=C)"
else
  fail "check 2b must count codepoints: 600 'é' is 600 chars, not 1200 bytes (rc=$rc): $out"
fi

desc_1024_multibyte="$(printf 'd%.0s' $(seq 1 1000))$(printf 'é%.0s' $(seq 1 24))"
make_skill field-cap-multibyte-exact "---
name: field-cap-multibyte-exact
description: \"$desc_1024_multibyte\"
---

## Purpose

Multibyte boundary fixture: 1024 codepoints, 1048 UTF-8 bytes. Exactly at the
spec maximum, so legal; a byte count reports 1048 and fails.
"
out="$(LC_ALL=C run field-cap-multibyte-exact 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  ! grep -q 'description alone is' <<<"$out" &&
  grep -q 'description is 1024 codepoints, within 32 of' <<<"$out"; then
  pass "check 2b holds the cap in codepoints at the boundary (1024 'é' warns, does not fail)"
else
  fail "check 2b must not fail 1024 multibyte codepoints (2048 bytes) (rc=$rc): $out"
fi

printf '# recorded breach\n.claude/skills/field-cap-over\n' >"$TMP/desc-baseline.txt"
out="$(run_with_baseline "$TMP/desc-baseline.txt" field-cap-over 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'recorded as a pre-existing breach in' <<<"$out"; then
  pass "check 2b downgrades a baselined breach to a warning"
else
  fail "a baselined breach should WARN, not FAIL (rc=$rc): $out"
fi

printf '.claude/skills/field-cap-exact\n' >"$TMP/desc-baseline-stale.txt"
out="$(run_with_baseline "$TMP/desc-baseline-stale.txt" field-cap-exact 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'stale baseline row' <<<"$out"; then
  pass "check 2b fails a stale baseline row (the list can only shrink)"
else
  fail "a stale baseline row should FAIL (rc=$rc): $out"
fi

out="$(run_with_baseline "$TMP/no-such-baseline.txt" field-cap-over 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'does not exist' <<<"$out"; then
  pass "check 2b fails when the named baseline file is missing"
else
  fail "a missing named baseline should FAIL (rc=$rc): $out"
fi

out="$(run_with_baseline "" field-cap-over 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: description alone is 1025 codepoints' <<<"$out"; then
  pass "check 2b with no baseline set fails every breach"
else
  fail "an empty baseline setting must not downgrade anything (rc=$rc): $out"
fi

# 47. --require-evals honors a recorded warrant skip (#3135).
mkdir -p "$TMP/plugins/p1/skills/skipme" "$TMP/scripts"
cat >"$TMP/plugins/p1/skills/skipme/SKILL.md" <<'EOF'
---
description: "A pure-reference fixture. Use when: 'testing warrant skips'."
disable-model-invocation: false
---

## Purpose

Pure-reference skip fixture.

## Gotchas

None known.
EOF
printf '%s\n' 'plugins/p1/skills/skipme  # test skip' >"$TMP/scripts/evals-warrant-exemptions.txt"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals skipme 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'evals skip recorded' <<<"$out"; then
  pass "--require-evals honors a recorded warrant skip"
else
  fail "--require-evals should pass a recorded skip (rc=$rc): $out"
fi

mkdir -p "$TMP/plugins/p1/skills/listed"
cat >"$TMP/plugins/p1/skills/listed/SKILL.md" <<'EOF'
---
description: "An unlisted fixture. Use when: 'testing warrant unlisted'."
disable-model-invocation: false
---

## Purpose

Unlisted sibling of the skip fixture.

## Gotchas

None known.
EOF
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "--require-evals still fails an unlisted skill"
else
  fail "unlisted skill should still fail --require-evals (rc=$rc): $out"
fi

mkdir -p "$TMP/plugins/p1/evals/c1"
printf '%s\n' 'schema_version: 1' 'tags: [listed-other, hard]' >"$TMP/plugins/p1/evals/c1/case.yaml"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "--require-evals fails when no case.yaml tag is exactly the skill"
else
  fail "a case tagged only listed-other should not satisfy listed (rc=$rc): $out"
fi
printf '%s\n' 'schema_version: 1' "tags: [hard, 'listed']" >"$TMP/plugins/p1/evals/c1/case.yaml"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'case tags listed' <<<"$out"; then
  pass "--require-evals accepts a plugin case.yaml that tags the skill"
else
  fail "a case tagged listed should satisfy --require-evals (rc=$rc): $out"
fi

printf '%s\n' 'schema_version: "1.1"' "name: 'listed-c1'" 'graders:' >"$TMP/plugins/p1/evals/c1/case.yaml"
printf '%s\n' '---' "tags: ['other']" '---' '' "tags: ['listed']" >"$TMP/plugins/p1/evals/c1/prompt.md"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'skill ships no evals/evals.json' <<<"$out"; then
  pass "--require-evals ignores a tags line in the prompt body"
else
  fail "a tags line after the front matter should not count (rc=$rc): $out"
fi
printf '%s\n' '---' "tags: ['listed', 'hard']" 'allowed_tools: [Read, Glob, Grep, Skill]' '---' '' 'Prompt text.' >"$TMP/plugins/p1/evals/c1/prompt.md"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'case tags listed' <<<"$out"; then
  pass "--require-evals accepts a converted case whose prompt.md front matter tags the skill"
else
  fail "a converted case tagged listed should satisfy --require-evals (rc=$rc): $out"
fi
rm -f "$TMP/plugins/p1/evals/c1/case.yaml"
out="$(cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$TMP/plugins/p1/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" --require-evals listed 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'case tags listed' <<<"$out"; then
  pass "--require-evals accepts a prompt.md-only case whose front matter tags the skill"
else
  fail "a prompt.md-only case tagged listed should satisfy --require-evals (rc=$rc): $out"
fi
rm -rf "${TMP:?}/plugins/p1/evals"

# 49. The evals-warrant walk stops at a filesystem root instead of spinning.
# `dirname` is a fixed point at every root: `.` for a relative path on any
# platform, and `<drive>:` on Git Bash, where `git rev-parse --show-toplevel`
# hands back a drive-letter path. A walk that only stops on `/` never reaches
# it from either, so the whole run hangs with no output. The fixture is
# deliberately outside a git repo and anchored on a relative root, which is the
# shape that reproduces the fixed point on Linux as well as Windows.
WALK_TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP" "$WALK_TMP"' EXIT
mkdir -p "$WALK_TMP/plugins/p1/skills/walkroot"
cat >"$WALK_TMP/plugins/p1/skills/walkroot/SKILL.md" <<'EOF'
---
description: "A walk fixture. Use when: 'testing exemptions-walk termination'."
disable-model-invocation: false
---

## Purpose

Fixture for the exemptions-walk termination check.

## Gotchas

None known.
EOF
if ! command -v timeout >/dev/null 2>&1; then
  pass "timeout unavailable; skip exemptions-walk termination case"
else
  (cd "$WALK_TMP" && CLAUDE_PROJECT_DIR=. CHECK_SKILL_SKILLS_ROOT=plugins/p1/skills \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 timeout 60 bash "$SUT" --require-evals walkroot) >/dev/null 2>&1
  rc=$?
  if [[ $rc -ne 124 ]]; then
    pass "the evals-warrant walk terminates at a filesystem root"
  else
    fail "the evals-warrant walk never terminated (timed out at a dirname fixed point)"
  fi
fi

out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "INFO: no '## Next' section" <<<"$out" && ! grep -q "WARN: '## Next'" <<<"$out"; then
  pass "a skill with no '## Next' gets an INFO note and no warning"
else
  fail "absent '## Next' should be INFO only (rc=$rc): $out"
fi

make_skill next-ok '---
name: next-ok
description: "Next fixture. Use when: '"'"'next ok'"'"'."
---

## Purpose

Conforming successor section in the bullet shape.

## Next

- The numbers feed a comparison: `/verification:measure metrics`.
- A number is about to be quoted at someone, so the caveats come first:
  `/code-metrics:principles`.

## Gotchas

None known.
'
out="$(run next-ok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "INFO: '## Next' section present" <<<"$out" && ! grep -q "WARN: '## Next'" <<<"$out"; then
  pass "a conforming bullet-shape '## Next' before '## Gotchas' passes silently"
else
  fail "conforming '## Next' should not warn (rc=$rc): $out"
fi

make_skill next-single '---
name: next-single
description: "Next fixture. Use when: '"'"'next single'"'"'."
---

## Purpose

Conforming successor section in the single-invocation shape.

## Next

`/code-metrics:audit complexity`. The sibling skills cover the other measures.

## Gotchas

None known.
'
out="$(run next-single 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "WARN: '## Next'" <<<"$out"; then
  pass "a conforming single-invocation '## Next' passes silently"
else
  fail "single-invocation '## Next' should not warn (rc=$rc): $out"
fi

make_skill next-late '---
name: next-late
description: "Next fixture. Use when: '"'"'next late'"'"'."
---

## Purpose

Successor section placed after Gotchas.

## Gotchas

None known.

## Next

`/code-metrics:audit complexity`.
'
out="$(run next-late 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section placed after '## Gotchas'" <<<"$out"; then
  pass "a '## Next' after '## Gotchas' warns and passes"
else
  fail "misplaced '## Next' should warn and pass (rc=$rc): $out"
fi

make_skill next-malformed '---
name: next-malformed
description: "Next fixture. Use when: '"'"'next malformed'"'"'."
---

## Purpose

Successor section with one bullet that names no skill.

## Next

- Go do the next thing.

## Gotchas

None known.
'
out="$(run next-malformed 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section a single bullet; write it as the one-line form; 1 bullet(s) name no /plugin:skill successor" <<<"$out"; then
  pass "a malformed '## Next' warns on both the single bullet and the missing successor"
else
  fail "malformed '## Next' should warn on count and token (rc=$rc): $out"
fi

make_skill next-operative '---
name: next-operative
description: "Next fixture. Use when: '"'"'next operative'"'"'."
---

## Purpose

Single-shape successor section written as an operative chain: prose first, a
Skill-tool instruction, an availability gate, and a fallback clause.

## Next

Ask the Skill tool to invoke /code-metrics:audit complexity when it is installed.
Otherwise measure by hand.

## Gotchas

None known.
'
out="$(run next-operative 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section first line does not open with a /plugin:skill invocation; carries operative-chain phrasing ('Skill tool')" <<<"$out"; then
  pass "a prose-first operative '## Next' warns on the opening and the chain phrasing"
else
  fail "operative '## Next' should warn on opening and phrasing (rc=$rc): $out"
fi

make_skill next-bullets-fallback '---
name: next-bullets-fallback
description: "Next fixture. Use when: '"'"'next bullets fallback'"'"'."
---

## Purpose

Bullet-shape successor section whose second bullet carries a fallback clause.

## Next

- The numbers feed a comparison: `/verification:measure metrics`.
- A number is about to be quoted: `/code-metrics:principles`, or fall back to
  the README when that plugin is absent.

## Gotchas

None known.
'
out="$(run next-bullets-fallback 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section carries operative-chain phrasing ('fall back')" <<<"$out"; then
  pass "a bullet-shape '## Next' with a fallback clause warns on the chain phrasing"
else
  fail "bullet '## Next' with a fallback should warn on phrasing (rc=$rc): $out"
fi

make_skill next-enabled-gate '---
name: next-enabled-gate
description: "Next fixture. Use when: '"'"'next enabled gate'"'"'."
---

## Purpose

Single-shape successor section that carries the availability gate.

## Next

/code-metrics:principles (if that plugin is enabled)

## Gotchas

None known.
'
out="$(run next-enabled-gate 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section carries operative-chain phrasing ('is enabled')" <<<"$out"; then
  pass "a '## Next' line gated on the plugin being enabled warns on the chain phrasing"
else
  fail "'## Next' with an enabled gate should warn on phrasing (rc=$rc): $out"
fi

make_skill next-are-enabled-gate '---
name: next-are-enabled-gate
description: "Next fixture. Use when: '"'"'next are enabled gate'"'"'."
---

## Purpose

Bullet-shape successor section gated on two plugins being enabled.

## Next

- The numbers feed a comparison: `/verification:measure metrics`.
- A number is about to be quoted: `/code-metrics:principles`, when both plugins are enabled.

## Gotchas

None known.
'
out="$(run next-are-enabled-gate 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section carries operative-chain phrasing ('are enabled')" <<<"$out"; then
  pass "a '## Next' bullet gated on plugins that 'are enabled' warns on the chain phrasing"
else
  fail "'## Next' with an 'are enabled' gate should warn on phrasing (rc=$rc): $out"
fi

make_skill next-not-enabled-gate '---
name: next-not-enabled-gate
description: "Next fixture. Use when: '"'"'next not enabled gate'"'"'."
---

## Purpose

Single-shape successor section whose sentence covers the plugin not being enabled.

## Next

`/code-metrics:principles`. Skip it when code-metrics is not enabled.

## Gotchas

None known.
'
out="$(run next-not-enabled-gate 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: '## Next' section carries operative-chain phrasing ('is not enabled')" <<<"$out"; then
  pass "a '## Next' line covering a plugin that 'is not enabled' warns on the chain phrasing"
else
  fail "'## Next' with an 'is not enabled' clause should warn on phrasing (rc=$rc): $out"
fi

make_skill next-enabled-word '---
name: next-enabled-word
description: "Next fixture. Use when: '"'"'next enabled word'"'"'."
---

## Purpose

Conforming successor section whose sentence has a word ending in "is" before "enabled".

## Next

`/code-metrics:audit complexity`. It measures what this enabled.

## Gotchas

None known.
'
out="$(run next-enabled-word 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "WARN: '## Next'" <<<"$out"; then
  pass "a word merely ending in 'is' before 'enabled' is not an availability gate"
else
  fail "'## Next' with 'this enabled' should not warn (rc=$rc): $out"
fi

routing_case() {
  local name="$1" sections="$2" expect="$3" label="$4" desc="${5:-Routing fixture.}"
  make_skill "$name" '---
name: '"$name"'
description: "'"$desc"' Use when: '"'"''"$name"''"'"'."
---

## Purpose

Routing-section fixture.
'"$sections"'
## Gotchas

None known.
'
  out="$(run "$name" 2>&1)"
  rc=$?
  if [[ -z "$expect" ]]; then
    if [[ $rc -eq 0 ]] && ! grep -qE "WARN: ('## (Next|Related|See also)|description names)" <<<"$out"; then
      pass "$label"
    else
      fail "$label (rc=$rc): $out"
    fi
  elif [[ $rc -eq 0 ]] && grep -qF "$expect" <<<"$out"; then
    pass "$label"
  else
    fail "$label (rc=$rc): $out"
  fi
}

routing_case next-five-bullets '
## Next

- One: /a:one.
- Two: /a:two.
- Three: the plan stage (/planning:plan).
- Four: /a:four.
- Five: `/a:five args`.
' '' "five one-target outcome bullets, one a stage target, pass with no bullet cap"

routing_case next-chain '
## Next

- Fixed: /verification:confirm fix, then /review:quality-gate.
- Not fixed: /debugging:debug.
' "WARN: '## Next' section 1 bullet(s) name more than one skill; one target per bullet" \
  "a chained bullet naming two skills warns on one target per bullet"

routing_case next-no-lead '
## Next

- /verification:confirm when the fix lands.
- Not fixed: /debugging:debug.
' "WARN: '## Next' section 1 bullet(s) do not open with a '<result>: ' lead" \
  "a token-first bullet warns on the missing result lead"

routing_case next-filler '
## Next

- Fixed: /verification:confirm.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.
' "WARN: '## Next' section carries the 'unsure where this leaves the work' bullet" \
  "the unsure-reader workflow bullet warns"

routing_case related-bad '
## Related

- Ranking first: /a:rank.
- /a:other covers the rest.
- A plain note with no skill.
' "WARN: '## Related' has 2 bullet(s) not in the '<condition>: /plugin:skill [args].' form" \
  "Related bullets missing a condition lead or a skill warn, counted"

routing_case see-also-skill '
## See also

- [Source tiers](https://example.com/source-tiers).
- /a:rank for ranking.
' "WARN: '## See also' names the skill /a:rank" \
  "a skill token under See also warns"

routing_case see-also-files '
## See also

- [Source tiers](https://example.com/source-tiers).
' '' "a See also holding only files passes"

mkdir -p "$TMP/fixplug/skills/target"
printf -- '---\nname: target\ndescription: x\n---\n' >"$TMP/fixplug/skills/target/SKILL.md"
routing_case desc-bare '' "WARN: description names 'fixplug:target' without the slash; write a skill token as /fixplug:target" \
  "a description naming an existing skill without the slash warns" "Not for ranking: fixplug:target."
routing_case desc-slash '' '' "a slashed skill token, or a colon pair naming no skill, passes" \
  "Not for ranking: /fixplug:target. Cites file:line."

make_stage_skill() {
  make_skill "$1" '---
name: '"$1"'
description: "Stage fixture. Use when: '"'"''"$1"''"'"'."
metadata:
  workflow-stage: '"$2"'
---

## Purpose

A stage-bearing fixture.
'"$3"'
## Gotchas

None known.
'
}

make_stage_skill stage-plan-bare plan ''
out="$(run stage-plan-bare 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qF "WARN: no '## Next' section on a stage-bearing skill (workflow-stage: plan)" <<<"$out" && ! grep -q "INFO: no '## Next' section" <<<"$out"; then
  pass "a stage-bearing skill with no '## Next' or routing heading warns and passes"
else
  fail "stage-bearing skill with no successor section should warn (rc=$rc): $out"
fi

make_stage_skill stage-review-quoted '"review"' ''
out="$(run stage-review-quoted 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -qF "WARN: no '## Next' section on a stage-bearing skill (workflow-stage: review)" <<<"$out"; then
  pass "a quoted workflow-stage value is read unquoted and still warns"
else
  fail "quoted stage-bearing value should warn (rc=$rc): $out"
fi

stage_quiet_case() {
  local name="$1" label="$2"
  out="$(run "$name" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]] && ! grep -q "stage-bearing skill" <<<"$out" && ! grep -q "WARN: '## Next'" <<<"$out"; then
    pass "$label"
  else
    fail "$label (rc=$rc): $out"
  fi
}

for heading in '## Handoff' '## Routing table' '## Integration with workflow' '## Skill chaining during execution' '## handoff to `education:teach`'; do
  slug="$(printf '%s' "$heading" | tr -cs 'a-zA-Z' '-' | tr '[:upper:]' '[:lower:]')"
  slug="${slug%-}"
  make_stage_skill "stage-plan$slug" plan "
$heading

Routes to \`/implementation:implement\` in prose.
"
  stage_quiet_case "stage-plan$slug" "a stage-bearing skill routing under '$heading' does not warn"
done

make_stage_skill stage-plan-next plan '
## Next

`/implementation:implement`.
'
out="$(run stage-plan-next 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "INFO: '## Next' section present" <<<"$out" && ! grep -q "stage-bearing skill" <<<"$out"; then
  pass "a stage-bearing skill with a conforming '## Next' keeps today's silent verdict"
else
  fail "stage-bearing skill with '## Next' should not warn (rc=$rc): $out"
fi

make_stage_skill stage-anytime anytime ''
out="$(run stage-anytime 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "INFO: no '## Next' section" <<<"$out" && ! grep -q "stage-bearing skill" <<<"$out"; then
  pass "a non-stage workflow-stage (anytime) with no '## Next' stays an INFO note"
else
  fail "anytime skill should keep the INFO note (rc=$rc): $out"
fi

make_stage_skill stage-interview interview ''
stage_quiet_case stage-interview "an interview-stage skill with no '## Next' does not warn (interview routes through its slice)"


ROOTS_CWD="$TMP"
mkdir -p "$TMP/roots/a/root-pass-a" "$TMP/roots/b/root-fail-b" \
  "$TMP/roots/c/root-pass-c" "$TMP/roots/empty" "$TMP/roots/ev/root-needs-evals"

root_body='---
description: "Root-mode fixture. Use when: '"'"'root mode'"'"' is exercised."
disable-model-invocation: false
---

## Purpose

Root-mode fixture skill.

## Gotchas

None known.
'
printf '%s' "$root_body" >"$TMP/roots/a/root-pass-a/SKILL.md"
printf '%s' "$root_body" >"$TMP/roots/c/root-pass-c/SKILL.md"
printf '%s' "$root_body" >"$TMP/roots/ev/root-needs-evals/SKILL.md"
printf '%s' '# no frontmatter here
just a heading
' >"$TMP/roots/b/root-fail-b/SKILL.md"

out="$(run_roots "$TMP/roots/a" "$TMP/roots/b" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q '^=== .*/roots/a ===$' <<<"$out" &&
  grep -q '^=== .*/roots/b ===$' <<<"$out" &&
  grep -q 'CHECK-SKILL root-pass-a: PASS' <<<"$out" &&
  grep -q 'CHECK-SKILL root-fail-b: FAIL' <<<"$out" &&
  grep -q '^1 passed, 1 failed$' <<<"$out"; then
  pass "R1: two roots with one pass and one fail exit 1 with per-root headers, both verdicts and a rollup"
else
  fail "R1: two roots should exit 1 with both headers, both verdict lines and '1 passed, 1 failed' (rc=$rc): $out"
fi

out="$(run_roots "$TMP/roots/a" "$TMP/roots/c" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q '^2 passed, 0 failed$' <<<"$out"; then
  pass "R2: two all-passing roots exit 0 with a rollup"
else
  fail "R2: two all-passing roots should exit 0 with '2 passed, 0 failed' (rc=$rc): $out"
fi

out="$(run_roots "$TMP/roots/a" "$TMP/roots/nope" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'roots/nope' <<<"$out"; then
  pass "R3: an unresolvable path alongside a root exits 2 naming it"
else
  fail "R3: an unresolvable path should exit 2 naming it (rc=$rc): $out"
fi

out="$(run_roots "$TMP/roots/empty" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'No skills found under: .*/roots/empty' <<<"$out" &&
  grep -q '^0 passed, 0 failed$' <<<"$out"; then
  pass "R4: an empty root is named and exits 0"
else
  fail "R4: an empty root should be named at exit 0 (rc=$rc): $out"
fi

out="$(run_roots good-skill "$TMP/roots/a" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'mixed skill name and skills root' <<<"$out"; then
  pass "R5: a skill name mixed with a root exits 2"
else
  fail "R5: a mixed call should exit 2 (rc=$rc): $out"
fi

mkdir -p "$TMP/good-skill"
out="$(run good-skill 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'CHECK-SKILL good-skill: PASS' <<<"$out"; then
  pass "R6: a bare skill name still resolves as a name when a same-named cwd directory exists"
else
  fail "R6: a bare skill name should stay single-skill mode (rc=$rc): $out"
fi

out="$(run_roots --require-evals "$TMP/roots/ev" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'skill ships no evals/evals.json' <<<"$out" &&
  grep -q '^0 passed, 1 failed$' <<<"$out"; then
  pass "R7: --require-evals reaches the children in root mode"
else
  fail "R7: --require-evals should reach the children (rc=$rc): $out"
fi

out="$(run_roots --help 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -qF 'bash check-skill.sh [--require-evals] <root> [<root> ...]' <<<"$out" &&
  ! grep -q 'set -uo pipefail' <<<"$out"; then
  pass "R8: --help prints the root usage line and stops at the code"
else
  fail "R8: --help should print the root usage line and stop at the code (rc=$rc): $out"
fi

out="$(run_roots 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'Usage: check-skill.sh' <<<"$out"; then
  pass "R9: no positionals still takes the existing usage-error path"
else
  fail "R9: no positionals should keep the usage-error path (rc=$rc): $out"
fi
out="$(run_roots -- 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'Usage: check-skill.sh' <<<"$out"; then
  pass "R9: a bare -- with no positionals takes the same usage-error path"
else
  fail "R9: a bare -- should keep the usage-error path (rc=$rc): $out"
fi

out="$(run_roots good-skill bad-skill 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'more than one skill name' <<<"$out"; then
  pass "R10: two skill names with no root exit 2 instead of dropping the rest"
else
  fail "R10: two skill names should exit 2 (rc=$rc): $out"
fi

abs_out="$(run_roots "$TMP/roots/a" 2>&1)"
abs_rc=$?
ROOTS_CWD="$TMP/roots"
rel_out="$(run_roots a 2>&1)"
rel_rc=$?
ROOTS_CWD="$TMP"
if [[ $rel_rc -eq $abs_rc ]] && [[ $rel_rc -eq 0 ]] &&
  grep -q '^=== .*/roots/a ===$' <<<"$rel_out" &&
  grep -q '^1 passed, 0 failed$' <<<"$rel_out" &&
  grep -q '^1 passed, 0 failed$' <<<"$abs_out"; then
  pass "R11: a relative root resolves against the caller's cwd and checks that tree"
else
  fail "R11: a relative root should match the absolute run (rel=$rel_rc abs=$abs_rc): $rel_out"
fi

noslash_out="$(run_roots --require-evals "$TMP/plugins/p1/skills" 2>&1)"
noslash_rc=$?
slash_out="$(run_roots --require-evals "$TMP/plugins/p1/skills/" 2>&1)"
slash_rc=$?
if [[ $slash_rc -eq $noslash_rc ]] &&
  grep -q 'evals skip recorded' <<<"$noslash_out" &&
  grep -q 'evals skip recorded' <<<"$slash_out"; then
  pass "R12: a trailing-slash root still resolves the plugin-root branch"
else
  fail "R12: a trailing-slash root should match the plain spelling (slash=$slash_rc plain=$noslash_rc): $slash_out"
fi

out="$(run_roots "$TMP/roots/a/root-pass-a" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] &&
  grep -q 'root-pass-a' <<<"$out" &&
  grep -qi 'skill directory' <<<"$out"; then
  pass "R13: a skill's own directory passed as a root exits 2 instead of gating nothing"
else
  fail "R13: a skill directory as a root should exit 2 (rc=$rc): $out"
fi

out="$(run_roots "$TMP/roots/nope" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] &&
  grep -q 'roots/nope' <<<"$out" &&
  ! grep -q 'plugin:skill name' <<<"$out"; then
  pass "R14: a lone nonexistent root exits 2 naming it, not the plugin:skill guidance"
else
  fail "R14: a lone nonexistent root should exit 2 naming it (rc=$rc): $out"
fi

out="$(run_roots "$TMP/no-such-dir/*/skills" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'no-such-dir' <<<"$out"; then
  pass "R14b: an unmatched glob pattern reaching the script exits 2 naming it"
else
  fail "R14b: an unmatched glob literal should exit 2 naming it (rc=$rc): $out"
fi

# R15. A relative root is resolved against the cwd, never through CDPATH. `cd`
#      consults CDPATH before `.` and ECHOES the directory it landed in, so an
#      unguarded `$(cd "$arg" && pwd)` both resolves the wrong tree and captures
#      two lines into the root string.
mkdir -p "$TMP/cdpath-decoy/a"
ROOTS_CWD="$TMP"
out="$(cd "$TMP/roots" &&
  CDPATH="$TMP/cdpath-decoy" CHECK_SKILL_SKILLS_ROOT="$SKILLS" \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" a 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q '^=== .*/roots/a ===$' <<<"$out" &&
  grep -q '^1 passed, 0 failed$' <<<"$out"; then
  pass "R15: a relative root ignores CDPATH and resolves against the cwd"
else
  fail "R15: a relative root should ignore CDPATH (rc=$rc): $out"
fi

NOGIT_TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP" "$WALK_TMP" "$NOGIT_TMP"' EXIT
mkdir -p "$NOGIT_TMP/roots/x/nogit-skill"
printf '%s' "$root_body" >"$NOGIT_TMP/roots/x/nogit-skill/SKILL.md"
out="$(
  cd "$NOGIT_TMP" &&
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_PREFIX \
      -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
      CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      bash "$SUT" "$NOGIT_TMP/roots/x" 2>&1
)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'not in a git repo' <<<"$out" &&
  grep -q '^1 passed, 0 failed$' <<<"$out"; then
  pass "R16: an explicit root gates its skills outside a git repo with no env set"
else
  fail "R16: an explicit root should work with no env and no git (rc=$rc): $out"
fi

XREPO="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP" "$WALK_TMP" "$NOGIT_TMP" "$XREPO"' EXIT
mkdir -p "$XREPO/caller/skills/xskill/node_modules" "$XREPO/external/skills/xskill"
printf 'module.exports = 1;\n' >"$XREPO/caller/skills/xskill/node_modules/dep.js"
printf 'placeholder\n' >"$XREPO/caller/README.md"
printf '%s' "$root_body" >"$XREPO/external/skills/xskill/SKILL.md"
for xrepo_r in caller external; do
  git -C "$XREPO/$xrepo_r" init -q
  git -C "$XREPO/$xrepo_r" config user.email test@example.com
  git -C "$XREPO/$xrepo_r" config user.name test
  git -C "$XREPO/$xrepo_r" add -A
  git -C "$XREPO/$xrepo_r" commit -qm fixture
done
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q '^1 passed, 0 failed$' <<<"$out" &&
  ! grep -q 'committed cache/build artifact' <<<"$out"; then
  pass "R17: a child's git-backed checks query the dispatched repo, not the caller's"
else
  fail "R17: the caller's repo must not answer for the dispatched tree (rc=$rc): $out"
fi

out2="$(cd "$XREPO/external" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc2=$?
if [[ $rc2 -eq $rc ]] && grep -q '^1 passed, 0 failed$' <<<"$out2"; then
  pass "R17b: the same root gives the same verdict from either cwd"
else
  fail "R17b: verdict must not depend on the caller's cwd (from-caller=$rc from-own=$rc2): $out2"
fi

# R18. A root in NO repo at all, driven from a repo cwd, SKIPS the git-backed
#      checks with their documented notes rather than answering from the
#      caller's repo. Before the cwd fix this passed only by accident: SKILL_REL
#      came out empty, `git ls-files ""` failed as an invalid pathspec, and the
#      error was swallowed, so the run misreported "new skill" instead of
#      naming the absent repo.
mkdir -p "$XREPO/nogit/skills/xskill"
printf '%s' "$root_body" >"$XREPO/nogit/skills/xskill/SKILL.md"
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" "$XREPO/nogit/skills" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] &&
  grep -q 'trigger-keyword preservation (check 3) skipped' <<<"$out" &&
  grep -q 'committed-artifact scan (check 13) skipped' <<<"$out" &&
  grep -q '^1 passed, 0 failed$' <<<"$out"; then
  pass "R18: a non-git root skips the git-backed checks by name instead of answering from the caller's repo"
else
  fail "R18: a non-git root should name the absent repo (rc=$rc): $out"
fi

git -C "$XREPO/external" branch -q dispatched-only
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
    CHECK_SKILL_BASE_REF=dispatched-only CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q '^1 passed, 0 failed$' <<<"$out"; then
  pass "R19: a base ref present only in the dispatched repo is accepted"
else
  fail "R19: a dispatched-repo base ref should be accepted (rc=$rc): $out"
fi

out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR \
    CHECK_SKILL_BASE_REF=no-such-ref-anywhere CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'is not a valid commit' <<<"$out"; then
  pass "R19b: a base ref absent from the dispatched repo is an environment error there"
else
  fail "R19b: an absent base ref should exit 2 from the child (rc=$rc): $out"
fi

# R20. Check 6 runs markdownlint from the skill's repo top level, so a config
#      there applies when the dispatched root is a subdirectory below it
#      (markdownlint-cli2 never looks above its cwd). A stub npx records the
#      cwd and file it was handed, so the assertion needs no Node.
mkdir -p "$XREPO/bin"
printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$PWD" "${*: -1}" >"%s/npx.log"\n' "$XREPO" >"$XREPO/bin/npx"
chmod +x "$XREPO/bin/npx"
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_SKIP_MARKDOWNLINT \
    PATH="$XREPO/bin:$PATH" bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
ml_log="$(cat "$XREPO/npx.log" 2>/dev/null)"
# Suffix match: git and the shell spell the same temp dir differently on Windows.
if [[ $rc -eq 0 && "$ml_log" == */external\|skills/xskill/SKILL.md ]]; then
  pass "R20: markdownlint runs from the skill's repo top level"
else
  fail "R20: markdownlint should run from the repo top level (npx saw: $ml_log): $out"
fi

mkdir -p "$XREPO/external/skills/node_modules/.bin"
printf '#!/usr/bin/env bash\nprintf "local|%%s|%%s\\n" "$PWD" "$1" >"%s/npx.log"\n' "$XREPO" \
  >"$XREPO/external/skills/node_modules/.bin/markdownlint-cli2"
chmod +x "$XREPO/external/skills/node_modules/.bin/markdownlint-cli2"
rm -f "$XREPO/npx.log"
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_SKIP_MARKDOWNLINT \
    PATH="$XREPO/bin:$PATH" bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
ml_log="$(cat "$XREPO/npx.log" 2>/dev/null)"
if [[ $rc -eq 0 && "$ml_log" == local\|*/external\|skills/xskill/SKILL.md ]]; then
  pass "R20b: a workspace-local markdownlint-cli2 above the skill is preferred over npx"
else
  fail "R20b: the workspace-local install should run (saw: $ml_log): $out"
fi

no_npx_path=""
IFS=: read -ra path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [[ -e "$d/npx" ]] || no_npx_path="${no_npx_path:+$no_npx_path:}$d"
done
rm -f "$XREPO/npx.log"
out="$(cd "$XREPO/caller" &&
  env -u CHECK_SKILL_SKILLS_ROOT -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_SKIP_MARKDOWNLINT \
    PATH="$no_npx_path" bash "$SUT" "$XREPO/external/skills" 2>&1)"
rc=$?
ml_log="$(cat "$XREPO/npx.log" 2>/dev/null)"
if [[ $rc -eq 0 && "$ml_log" == local\|* ]] && ! grep -q 'npx not found' <<<"$out"; then
  pass "R20c: a local markdownlint-cli2 runs with no npx on PATH"
else
  fail "R20c: the local install should run without npx (saw: $ml_log): $out"
fi

model_tail='
## Purpose

A skill with a frontmatter model field.

## Gotchas

None known.
'
make_skill model-ok "---
name: model-ok
description: \"Do a thing. Use when: 'a thing' is needed.\"
model: opus[1m]
---
$model_tail"
out="$(run model-ok 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'PASS' <<<"$out"; then
  pass "frontmatter model opus[1m] passes"
else
  fail "frontmatter model opus[1m] should pass (rc=$rc): $out"
fi

make_skill model-bad "---
name: model-bad
description: \"Do a thing. Use when: 'a thing' is needed.\"
model: two words
---
$model_tail"
out="$(run model-bad 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q "frontmatter model" <<<"$out"; then
  pass "frontmatter model with a space fails"
else
  fail "spaced model should fail (rc=$rc): $out"
fi

model_case() {
  make_skill "$1" "---
name: $1
description: \"Do a thing. Use when: 'a thing' is needed.\"
$2
---
$model_tail"
  out="$(run "$1" 2>&1)"
  rc=$?
  if [[ $rc -eq $3 ]] && { [[ $3 -eq 0 ]] || grep -q "frontmatter model" <<<"$out"; }; then
    pass "$4"
  else
    fail "$4 (want rc=$3, got rc=$rc): $out"
  fi
}
model_case model-bedrock 'model: anthropic.claude-3-5-sonnet-20241022-v2:0' 0 "frontmatter model Bedrock id with ':' passes"
model_case model-arn 'model: arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.anthropic.claude-sonnet-4-v1:0' 0 "frontmatter model ARN with ':' and '/' passes"
model_case model-vertex 'model: claude-sonnet-4@20250514' 0 "frontmatter model Vertex id with '@' passes"
model_case model-empty 'model:' 1 "frontmatter model empty fails"
model_case model-flow-seq 'model: [foo]' 1 "frontmatter model unquoted flow sequence fails"
model_case model-flow-map 'model: {}' 1 "frontmatter model unquoted flow mapping fails"
model_case model-bool 'model: true' 1 "frontmatter model unquoted boolean fails"
model_case model-quoted-bool 'model: "true"' 0 "frontmatter model quoted string passes"

desc_case() {
  make_skill "$1" "---
name: $1
$2
---

## Purpose

A skill exercising the description colon check.

## Gotchas

None known.
"
  out="$(run "$1" 2>&1)"
  rc=$?
  if [[ $rc -eq $3 ]] && { [[ $3 -eq 0 ]] || grep -q "YAML mapping indicator" <<<"$out"; }; then
    pass "$4"
  else
    fail "$4 (want rc=$3, got rc=$rc): $out"
  fi
}
desc_case desc-cont-colon 'description: Do a thing and
  use when: the user asks.' 1 "colon-space only on a description continuation line fails"
desc_case desc-trailing-colon 'description: Use when the user asks:
  a thing.' 1 "description first line ending in a colon fails"
desc_case desc-plain-multi 'description: Do a thing and
  use it when the user asks.' 0 "multi-line plain description without a colon passes"
desc_case desc-comment-colon 'description: Do a thing and
  use it when asked # note: detail' 0 "colon-space inside a trailing YAML comment passes"
desc_case desc-quoted-multi 'description: "Do a thing and
  use when: the user asks."' 0 "multi-line quoted description with colon-space passes"
desc_case desc-block-multi 'description: >
  Do a thing and
  use when: the user asks:
  a thing.
compatibility: Requires git.' 0 "multi-line block-scalar description with colon-space passes"

make_skill script-stdin "$good_body"
mkdir -p "$SKILLS/script-stdin/scripts"
printf '#!/usr/bin/env bash\nif read -r -t 2 _x; then exit 1; fi\nexit 0\n' >"$SKILLS/script-stdin/scripts/x.test.sh"
git -C "$TMP" add "$SKILLS/script-stdin/scripts/x.test.sh"
out="$(run script-stdin 2>&1 </dev/zero)"
if grep -q 'script test passed: scripts/x.test.sh' <<<"$out"; then
  pass "check 7 gives a skill script test EOF on stdin"
else
  fail "check 7 should close stdin for the script test: $out"
fi
make_skill script-long "$good_body"
mkdir -p "$SKILLS/script-long/scripts"
printf '#!/usr/bin/env bash\nseq 1 300\nexit 1\n' >"$SKILLS/script-long/scripts/x.test.sh"
git -C "$TMP" add "$SKILLS/script-long/scripts/x.test.sh"
out="$(run script-long 2>&1)"
if grep -q 'output truncated to the last 100 lines; run bash .*x.test.sh for all of it' <<<"$out" &&
  grep -qx '300' <<<"$out" && ! grep -qx '200' <<<"$out"; then
  pass "check 7 replays only the last 100 lines of a long failing script test"
else
  fail "check 7 should truncate a 300-line failing test: $out"
fi
out="$(CHECK_SKILL_SKIP_SCRIPT_TESTS=1 run script-long 2>&1)"
if grep -q 'script tests skipped (CHECK_SKILL_SKIP_SCRIPT_TESTS=1)' <<<"$out" &&
  ! grep -q 'script test failed' <<<"$out" && ! grep -qx '300' <<<"$out"; then
  pass "CHECK_SKILL_SKIP_SCRIPT_TESTS=1 skips check 7"
else
  fail "CHECK_SKILL_SKIP_SCRIPT_TESTS=1 should skip check 7: $out"
fi

make_script_tests() {
  local skill="$1" body="$2" name
  make_skill "$skill" "${good_body//good-skill/$skill}"
  mkdir -p "$SKILLS/$skill/scripts"
  printf '#!/usr/bin/env bash\ntouch %q\n%s\n' "$TMP/$skill.a.ran" "$body" >"$SKILLS/$skill/scripts/a.test.sh"
  printf '#!/usr/bin/env bash\ntouch %q\nexit 0\n' "$TMP/$skill.b.ran" >"$SKILLS/$skill/scripts/b.test.sh"
  for name in a b; do
    git -C "$TMP" add "$SKILLS/$skill/scripts/$name.test.sh"
  done
}
b_skip_line() { printf 'SKIP .claude/skills/%s/scripts/b.test.sh (past the deadline, left to CI)' "$1"; }

make_script_tests deadline-none 'exit 0'
rc=0
out="$(run deadline-none 2>&1)" || rc=$?
if [[ $rc -eq 0 && -f "$TMP/deadline-none.a.ran" && -f "$TMP/deadline-none.b.ran" ]] &&
  grep -q 'CHECK-SKILL deadline-none: PASS' <<<"$out" && ! grep -q '^SKIP ' <<<"$out"; then
  pass "with no deadline check 7 runs every script test"
else
  fail "with no deadline check 7 should run every script test (rc=$rc): $out"
fi

make_script_tests deadline-past 'exit 0'
rc=0
out="$(PLUGIN_TEST_DEADLINE=1 run deadline-past 2>&1)" || rc=$?
if [[ $rc -eq 3 && ! -e "$TMP/deadline-past.a.ran" && ! -e "$TMP/deadline-past.b.ran" ]] &&
  grep -qxF 'SKIP .claude/skills/deadline-past/scripts/a.test.sh (past the deadline, left to CI)' <<<"$out" &&
  grep -qxF "$(b_skip_line deadline-past)" <<<"$out" &&
  grep -q 'CHECK-SKILL deadline-past: INCOMPLETE .* 2 script test(s) left to CI' <<<"$out" &&
  ! grep -q 'CHECK-SKILL deadline-past: PASS' <<<"$out"; then
  pass "past its deadline check 7 starts nothing, names each test and exits 3"
else
  fail "past its deadline check 7 should start nothing and exit 3 (rc=$rc): $out"
fi

make_script_tests deadline-mid 'sleep 6; exit 0'
printf -v now '%(%s)T' -1
rc=0
out="$(PLUGIN_TEST_DEADLINE=$((now + 5)) run deadline-mid 2>&1)" || rc=$?
if [[ $rc -eq 3 && -f "$TMP/deadline-mid.a.ran" && ! -e "$TMP/deadline-mid.b.ran" ]] &&
  grep -qxF "$(b_skip_line deadline-mid)" <<<"$out" && grep -q 'script test passed: scripts/a.test.sh' <<<"$out"; then
  pass "check 7 stops launching when the deadline passes between two script tests"
else
  fail "check 7 should stop launching at the deadline (rc=$rc): $out"
fi

make_script_tests deadline-fail 'sleep 6; exit 1'
printf -v now '%(%s)T' -1
rc=0
out="$(PLUGIN_TEST_DEADLINE=$((now + 5)) run deadline-fail 2>&1)" || rc=$?
if [[ $rc -eq 1 ]] && grep -q 'script test failed: scripts/a.test.sh' <<<"$out" &&
  grep -qxF "$(b_skip_line deadline-fail)" <<<"$out" && grep -q 'CHECK-SKILL deadline-fail: FAIL' <<<"$out"; then
  pass "a script test that failed fails a run that left another"
else
  fail "a failed script test should fail the run past its deadline (rc=$rc): $out"
fi

make_script_tests deadline-inherit '[[ -z "${PLUGIN_TEST_DEADLINE+x}" ]]'
printf -v now '%(%s)T' -1
rc=0
out="$(PLUGIN_TEST_DEADLINE=$((now + 600)) run deadline-inherit 2>&1)" || rc=$?
if [[ $rc -eq 0 ]] && grep -q 'script test passed: scripts/a.test.sh' <<<"$out" &&
  grep -q 'CHECK-SKILL deadline-inherit: PASS' <<<"$out"; then
  pass "a script test does not inherit the deadline, and a run inside it passes"
else
  fail "a script test should not inherit the deadline (rc=$rc): $out"
fi

rc=0
out="$(PLUGIN_TEST_DEADLINE=soon run deadline-inherit 2>&1)" || rc=$?
if [[ $rc -eq 2 ]] && grep -q "PLUGIN_TEST_DEADLINE must be epoch seconds (got 'soon')" <<<"$out"; then
  pass "a deadline that is not epoch seconds is an environment error"
else
  fail "a bad deadline should exit 2 (rc=$rc): $out"
fi

deadline_root="$TMP/deadline-root"
mkdir -p "$deadline_root/root-skill/scripts"
printf '%s' "${good_body//good-skill/root-skill}" >"$deadline_root/root-skill/SKILL.md"
printf '#!/usr/bin/env bash\nexit 0\n' >"$deadline_root/root-skill/scripts/a.test.sh"
git -C "$TMP" add "$deadline_root/root-skill/scripts/a.test.sh"
rc=0
out="$(PLUGIN_TEST_DEADLINE=1 run_roots "$deadline_root" 2>&1)" || rc=$?
if [[ $rc -eq 3 ]] && grep -qx '0 passed, 0 failed' <<<"$out" &&
  grep -q '1 skill(s) left script tests to CI, counted in neither tally above' <<<"$out"; then
  pass "root form reads a skill that left script tests as neither pass nor failure"
else
  fail "root form should exit 3 for a skill that left script tests (rc=$rc): $out"
fi

SCOPE_TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP" "$WALK_TMP" "$NOGIT_TMP" "$XREPO" "$SCOPE_TMP"' EXIT
for scope_r in other nogit; do
  mkdir -p "$SCOPE_TMP/$scope_r/skills/good-skill/scripts"
  printf '%s' "$good_body" >"$SCOPE_TMP/$scope_r/skills/good-skill/SKILL.md"
  printf '#!/usr/bin/env bash\ntouch %q\nexit 1\n' "$SCOPE_TMP/$scope_r.ran" \
    >"$SCOPE_TMP/$scope_r/skills/good-skill/scripts/x.test.sh"
done
git -C "$SCOPE_TMP/other" init -q
git -C "$SCOPE_TMP/other" add skills
mkdir -p "$SCOPE_TMP/plaincwd"
scope_case() {
  rm -f "$4"
  local out rc
  if [[ "$5" == single ]]; then
    out="$(cd "$2" && env -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_INVOKING_TOPLEVEL \
      CHECK_SKILL_SKILLS_ROOT="$3" CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" good-skill 2>&1)"
  else
    out="$(cd "$2" && env -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_SKILLS_ROOT -u CHECK_SKILL_INVOKING_TOPLEVEL \
      CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" "$3" 2>&1)"
  fi
  rc=$?
  if [[ "$6" == run ]]; then
    if [[ -f "$4" && $rc -eq 1 ]] && grep -q 'script test failed: scripts/x.test.sh' <<<"$out"; then
      pass "check 7 $1"
    else
      fail "check 7 $1: the test should run (rc=$rc): $out"
    fi
  elif [[ ! -f "$4" && $rc -eq 0 ]] &&
    grep -q "${7:-script tests skipped: the skill is outside the current repository}" <<<"$out"; then
    pass "check 7 $1"
  else
    fail "check 7 $1: the test should be skipped with the note (rc=$rc): $out"
  fi
}
scope_case "runs a test in the invoking repo (root mode)" "$SCOPE_TMP/other" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" root run
scope_case "runs a test in the invoking repo from a subdirectory (single mode)" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" single run
scope_case "skips a test in another repo (single mode)" "$TMP" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" single skip
scope_case "skips a test in another repo (root mode)" "$TMP" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" root skip
scope_case "skips a test in no repo (single mode)" "$TMP" \
  "$SCOPE_TMP/nogit/skills" "$SCOPE_TMP/nogit.ran" single skip
scope_case "skips a test in no repo (root mode)" "$TMP" \
  "$SCOPE_TMP/nogit/skills" "$SCOPE_TMP/nogit.ran" root skip
scope_case "skips a repo's test from a cwd in no repo (single mode)" "$SCOPE_TMP/plaincwd" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" single skip
scope_case "skips a repo's test from a cwd in no repo (root mode)" "$SCOPE_TMP/plaincwd" \
  "$SCOPE_TMP/other/skills" "$SCOPE_TMP/other.ran" root skip
mkdir -p "$SCOPE_TMP/home/cache/skills/good-skill/scripts"
git -C "$SCOPE_TMP/home" init -q
printf '%s' "$good_body" >"$SCOPE_TMP/home/cache/skills/good-skill/SKILL.md"
printf '#!/usr/bin/env bash\ntouch %q\nexit 1\n' "$SCOPE_TMP/home.ran" \
  >"$SCOPE_TMP/home/cache/skills/good-skill/scripts/x.test.sh"
scope_case "skips an untracked test under the invoking work tree (single mode)" "$SCOPE_TMP/home" \
  "$SCOPE_TMP/home/cache/skills" "$SCOPE_TMP/home.ran" single skip \
  'script test skipped: scripts/x.test.sh is not committed in the current repository yet'
scope_case "skips an untracked test under the invoking work tree (root mode)" "$SCOPE_TMP/home" \
  "$SCOPE_TMP/home/cache/skills" "$SCOPE_TMP/home.ran" root skip \
  'script test skipped: scripts/x.test.sh is not committed in the current repository yet'

mkdir -p "$SCOPE_TMP/other/skills/nested-skill/scripts/inner"
printf '%s' "$good_body" >"$SCOPE_TMP/other/skills/nested-skill/SKILL.md"
printf '#!/usr/bin/env bash\ntouch %q\nexit 1\n' "$SCOPE_TMP/nested.ran" \
  >"$SCOPE_TMP/other/skills/nested-skill/scripts/inner/x.test.sh"
git -C "$SCOPE_TMP/other/skills/nested-skill/scripts/inner" init -q
git -C "$SCOPE_TMP/other/skills/nested-skill/scripts/inner" add x.test.sh
git -C "$SCOPE_TMP/other/skills/nested-skill/scripts/inner" \
  -c user.email=test@example.com -c user.name=test commit -qm fixture
git -C "$SCOPE_TMP/other" add skills/nested-skill/SKILL.md
rm -f "$SCOPE_TMP/nested.ran"
out="$(cd "$SCOPE_TMP/other" && env -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_INVOKING_TOPLEVEL \
  CHECK_SKILL_SKILLS_ROOT="$SCOPE_TMP/other/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" nested-skill 2>&1)"
if [[ ! -f "$SCOPE_TMP/nested.ran" ]] &&
  grep -q 'script test skipped: scripts/inner/x.test.sh is not tracked in the current repository' <<<"$out"; then
  pass "check 7 skips a test only a nested repository tracks"
else
  fail "check 7 should skip a test a nested repository vouches for: $out"
fi

scope_file() {
  mkdir -p "$1/$2/scripts"
  printf '%s' "$good_body" >"$1/$2/SKILL.md"
  printf '#!/usr/bin/env bash\ntouch %q\nexit 1\n' "$3" >"$1/$2/scripts/x.test.sh"
}
scope_single() {
  rm -f "$4"
  local out
  out="$(cd "$SCOPE_TMP/other" && env -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_INVOKING_TOPLEVEL \
    CHECK_SKILL_SKILLS_ROOT="$2" CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$SUT" "$3" 2>&1)"
  if [[ "$5" == run ]]; then
    if [[ -f "$4" ]] && grep -q 'script test failed: scripts/x.test.sh' <<<"$out"; then
      pass "check 7 $1"
    else
      fail "check 7 $1: the test should run: $out"
    fi
  elif [[ ! -f "$4" ]] && grep -q "$6" <<<"$out"; then
    pass "check 7 $1"
  else
    fail "check 7 $1: the test should be skipped with the note: $out"
  fi
}
scope_file "$SCOPE_TMP/other/skills" lane-skill "$SCOPE_TMP/lane.ran"
scope_single "runs an untracked test in a skills root with tracked files" \
  "$SCOPE_TMP/other/skills" lane-skill "$SCOPE_TMP/lane.ran" run
scope_file "$SCOPE_TMP/other/fresh/skills" fresh-skill "$SCOPE_TMP/fresh.ran"
scope_single "skips an untracked test in a brand-new skills root" \
  "$SCOPE_TMP/other/fresh/skills" fresh-skill "$SCOPE_TMP/fresh.ran" skip \
  'script test skipped: scripts/x.test.sh is not committed in the current repository yet'
scope_file "$SCOPE_TMP/other/skills" ignored-skill "$SCOPE_TMP/ignored.ran"
printf 'skills/ignored-skill/scripts/\n' >"$SCOPE_TMP/other/.gitignore"
scope_single "skips an ignored test" \
  "$SCOPE_TMP/other/skills" ignored-skill "$SCOPE_TMP/ignored.ran" skip \
  'script test skipped: scripts/x.test.sh is not tracked in the current repository'

rm -f "$SCOPE_TMP/other.ran"
out="$(cd "$TMP" && env -u CLAUDE_PROJECT_DIR -u CHECK_SKILL_INVOKING_TOPLEVEL \
  GIT_DIR="$SCOPE_TMP/other/.git" GIT_WORK_TREE="$SCOPE_TMP/other" \
  CHECK_SKILL_SKILLS_ROOT="$SCOPE_TMP/other/skills" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  bash "$SUT" good-skill 2>&1)"
if [[ ! -f "$SCOPE_TMP/other.ran" ]] &&
  grep -q 'script tests skipped: the skill is outside the current repository' <<<"$out"; then
  pass "check 7 ignores an exported GIT_DIR and GIT_WORK_TREE"
else
  fail "check 7 should skip a test an exported GIT_DIR points at: $out"
fi

out="$(run_roots 2>&1)"
if ! grep -q 'line [0-9]*:' <<<"$out" && grep -q 'run with --help' <<<"$out"; then
  pass "no positionals prints a clean usage line that points at --help"
else
  fail "usage error should be clean and point at --help: $out"
fi
if grep -q 'CHECK_SKILL_SKIP_MARKDOWNLINT' < <(run_roots --help 2>&1); then
  pass "--help documents CHECK_SKILL_SKIP_MARKDOWNLINT"
else
  fail "--help should document CHECK_SKILL_SKIP_MARKDOWNLINT"
fi

make_skill meta-registered '---
description: "Do a thing. Use when: '"'"'a thing'"'"' is needed."
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Do a thing
---

## Purpose

A skill whose metadata keys are all registered.

## Gotchas

None known.
'
out="$(run meta-registered 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'INFO: every metadata key is in the registry' <<<"$out" &&
  ! grep -q 'not in the metadata registry' <<<"$out"; then
  pass "check 28 stays quiet on registered metadata keys"
else
  fail "check 28 should report registered keys as INFO only (rc=$rc): $out"
fi
make_skill meta-unregistered '---
description: "Do a thing. Use when: '"'"'a thing'"'"' is needed."
disable-model-invocation: false
metadata:
  summary: Do a thing
  favorite-color: blue
---

## Purpose

A skill carrying a metadata key nothing reads.

## Gotchas

None known.
'
out="$(run meta-unregistered 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: metadata key 'favorite-color' is not in the metadata registry" <<<"$out" &&
  ! grep -q "metadata key 'summary' is not in" <<<"$out"; then
  pass "check 28 WARNs (exit 0) on an unregistered metadata key, naming only that key"
else
  fail "check 28 should WARN on favorite-color only, exit 0 (rc=$rc): $out"
fi

hist_case() {
  local body
  body="$(cat)"
  make_skill "$1" '---
description: "Do a thing. Use when: '"'"'a thing'"'"' is needed."
disable-model-invocation: false
---

## Purpose

'"$body"'

## Gotchas

None known.
'
  out="$(run "$1" 2>&1)"
  rc=$?
  if [[ "$2" == warn ]]; then
    if [[ $rc -eq 0 ]] && grep -q "WARN: SKILL.md body cites this repository's history" <<<"$out"; then
      pass "$3"
    else
      fail "$3 (want WARN at exit 0, rc=$rc): $out"
    fi
  elif [[ $rc -eq 0 ]] && grep -q "INFO: no history references in the SKILL.md body" <<<"$out" &&
    ! grep -q "cites this repository's history" <<<"$out"; then
    pass "$3"
  else
    fail "$3 (want quiet, rc=$rc): $out"
  fi
}
hist_case hist-pr warn "check 29 WARNs on a bare 'See PR #1234' line" <<'EOF'
See PR #1234 for the background.
EOF
hist_case hist-todo warn "check 29 WARNs on a TODO(#9) in the body" <<'EOF'
TODO(#9): tighten this step.
EOF
hist_case hist-pointer-block quiet "check 29 stays quiet inside a multi-line pointer-record block" <<'EOF'
`compare` treats `claude_code.cost.usage` and `claude_code.token.usage` as the total of record over `api_request` events; when a session's events fall short, `compare` names [anthropics/claude-code#98193](https://github.com/anthropics/claude-code/issues/98193), the open upstream report on missing `api_request` events. Events above the metric are flagged, never clamped, since that report does not cover them. `compare` sums data points only for delta temporality, so a non-delta token or cost metric exits 2.

- **Pointer**: for missing `api_request` events, see anthropics/claude-code#98193; for the metrics and their attributes, `effort` included, see <https://code.claude.com/docs/en/monitoring-usage#cost-counter> and <https://code.claude.com/docs/en/monitoring-usage#token-counter>; for the event, see <https://code.claude.com/docs/en/monitoring-usage#api-request-event>; for the temporality default, see <https://code.claude.com/docs/en/monitoring-usage#common-configuration-variables>. No docs section covers which requests skip `api_request` as of this date.
- **As of**: 2026-10-01; #98193 open.
- **Recheck trigger**: #98193 closes or changes state, the monitoring page documents which requests skip `api_request`, or `compare` reports `events short` on a store recorded after a fix shipped.
EOF
hist_case hist-pointer-unstamped quiet "check 29 stays quiet on a bare #N its unstamped pointer record cites upstream" <<'EOF'
- **Pointer**: for missing `api_request` events, see anthropics/claude-code#98193; when #98193 closes, read <https://code.claude.com/docs/en/monitoring-usage#api-request-event>.
EOF
hist_case hist-pointer-url quiet "check 29 stays quiet on a bare #N its block cites by issue URL" <<'EOF'
- **Pointer**: [the missing-events report](https://github.com/anthropics/claude-code/issues/98193); when #98193 closes, recheck `compare`.
EOF
hist_case hist-pointer-own warn "check 29 WARNs on a bare #N its unstamped block does not cite upstream" <<'EOF'
- **Pointer**: see anthropics/claude-code#98193; this rule came from #1234.
EOF
hist_case hist-code-span quiet "check 29 stays quiet on #N inside a code span" <<'EOF'
The add-side is `/code-tidying:tidy #14`.
EOF
hist_case hist-cross-repo quiet "check 29 stays quiet on a cross-repo owner/repo#N" <<'EOF'
Upstream bug anthropics/claude-code#8961 leaves the deny rule inert.
EOF
hist_case hist-fenced quiet "check 29 stays quiet on #N inside a fenced code block" <<'EOF'
Run this:

```bash
gh pr view #1234
```
EOF
hist_case hist-anchor quiet "check 29 stays quiet on a link anchor and a heading" <<'EOF'
See [the steps](#1-setup) and <https://example.com/page#42>.
EOF
make_skill hist-frontmatter '---
description: "Do a thing (#77). Use when: '"'"'a thing'"'"' is needed."
disable-model-invocation: false
---

## Purpose

No history in the body.

## Gotchas

None known.
'
out="$(run hist-frontmatter 2>&1)"
if grep -q "INFO: no history references in the SKILL.md body" <<<"$out" &&
  ! grep -q "cites this repository's history" <<<"$out"; then
  pass "check 29 reads the body only, never the frontmatter"
else
  fail "check 29 should not read the frontmatter: $out"
fi

size_skill() {
  local desc body i
  desc="Do a thing. Use when: 'a thing' is needed."
  while ((${#desc} < $2)); do desc+="x"; done
  body=""
  for ((i = 1; i <= $3; i++)); do body+="line $i"$'\n'; done
  mkdir -p "$SKILLS/$1"
  printf -- '---\ndescription: "%s"\ndisable-model-invocation: false\n---\n%s' "$desc" "$body" >"$SKILLS/$1/SKILL.md"
}
size_skill sz-at-max 419 160
out="$(run sz-at-max 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q "Pocock's measured max" <<<"$out" && ! grep -q 'WARN: description is' <<<"$out" &&
  grep -q 'INFO: size: description 419 chars, body 160 lines (Pocock medians 130 chars, 70 lines; max 419, 160)' <<<"$out"; then
  pass "check 30 stays quiet at exactly 419 chars and 160 body lines, printing the medians as INFO"
else
  fail "check 30 should be quiet at the max and print the INFO line (rc=$rc): $out"
fi
size_skill sz-over-desc 420 10
out="$(run sz-over-desc 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: description is 420 chars, above the description_warn setting 419 from default" <<<"$out"; then
  pass "check 30 WARNs (exit 0) on a 420-char description"
else
  fail "check 30 should WARN on 420 chars, exit 0 (rc=$rc): $out"
fi
size_skill sz-setting 300 10
out="$(run sz-setting 2>&1)"
if grep -q 'INFO: description settings: target 250 (default), warn above 419 (default), fail above 1024 (fixed)' <<<"$out" &&
  grep -q 'INFO: description is 300 chars, above the description_target setting 250 from default' <<<"$out" &&
  ! grep -q 'WARN: description is' <<<"$out"; then
  pass "check 30 prints the default description settings and an INFO above the target"
else
  fail "check 30 should print the default settings and an INFO above the target: $out"
fi
mkdir -p "$TMP/docs/conventions"
printf 'description_warn: 280\n' >"$TMP/docs/conventions/skill-quality.yaml"
out="$(run sz-setting 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: description is 300 chars, above the description_warn setting 280 from docs/conventions/skill-quality.yaml' <<<"$out"; then
  pass "check 30 moves the description warning to the team layer's description_warn"
else
  fail "check 30 should WARN at the team layer's description_warn 280, exit 0 (rc=$rc): $out"
fi
printf 'description_warn: 350\ndescription_target: 320\n' >"$TMP/docs/conventions/skill-quality.local.yaml"
out="$(run sz-setting 2>&1)"
if ! grep -q 'WARN: description is' <<<"$out" &&
  grep -q 'INFO: description settings: target 320 (docs/conventions/skill-quality.local.yaml), warn above 350 (docs/conventions/skill-quality.local.yaml)' <<<"$out"; then
  pass "check 30 lets the personal layer override the team layer key by key"
else
  fail "check 30 should take the personal layer's description settings: $out"
fi
printf 'description_warn: 2000\n' >"$TMP/docs/conventions/skill-quality.local.yaml"
out="$(run sz-setting 2>&1)"
if grep -q "WARN: docs/conventions/skill-quality.local.yaml: description_warn is '2000', not a whole number from 1 to 1024" <<<"$out" &&
  grep -q 'warn above 419 (default)' <<<"$out" && ! grep -q 'WARN: description is' <<<"$out"; then
  pass "check 30 drops an out-of-range description_warn and resolves to the default, not the team value"
else
  fail "check 30 should name the invalid value and fall back to the default 419: $out"
fi
rm -f "$TMP/docs/conventions/skill-quality.local.yaml"
printf 'description_warn: 280\n' >"$TMP/docs/conventions/skill-quality.yaml"
mkdir -p "$TMP/team-conv"
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `team-conv`.\n<!-- END GENERATED: convention-home -->\n' >"$TMP/AGENTS.md"
out="$(run sz-setting 2>&1)"
if grep -q 'warn above 419 (default)' <<<"$out" && ! grep -q 'WARN: description is' <<<"$out" &&
  ! grep -q 'docs/conventions' <<<"$out"; then
  pass "check 30 ignores docs/conventions when the pointer region binds another home"
else
  fail "check 30 should read no docs/conventions layer when the region binds team-conv: $out"
fi
printf 'description_warn: 290\n' >"$TMP/team-conv/skill-quality.yaml"
out="$(run sz-setting 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: description is 300 chars, above the description_warn setting 290 from team-conv/skill-quality.yaml' <<<"$out" &&
  ! grep -q 'docs/conventions' <<<"$out"; then
  pass "check 30 reads the description settings from the bound convention home"
else
  fail "check 30 should WARN at team-conv's description_warn 290, exit 0 (rc=$rc): $out"
fi
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `team-conv`.\nAlso `docs/conventions`.\n<!-- END GENERATED: convention-home -->\n' >"$TMP/AGENTS.md"
out="$(run sz-setting 2>&1)"
if grep -q 'WARN: the convention-home pointer region does not resolve' <<<"$out" &&
  grep -q 'warn above 419 (default)' <<<"$out" && ! grep -q 'WARN: description is' <<<"$out"; then
  pass "check 30 WARNs on an unresolvable pointer region and uses the default settings"
else
  fail "check 30 should WARN on two pointer lines and fall back to the defaults: $out"
fi
rm -rf "$TMP/AGENTS.md" "$TMP/team-conv"
rm -rf "$TMP/docs"
size_skill sz-setting-cap 1025 10
out="$(run sz-setting-cap 2>&1)"
rc=$?
if [[ $rc -ne 0 ]] && grep -q 'FAIL: description alone is 1025 codepoints' <<<"$out"; then
  pass "check 2b still FAILs a description above the fixed 1024 maximum"
else
  fail "check 2b should FAIL at 1025 codepoints (rc=$rc): $out"
fi
rm -rf "$SKILLS/sz-setting" "$SKILLS/sz-setting-cap"
size_skill sz-over-body 100 161
out="$(run sz-over-body 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q "WARN: SKILL.md body is 161 lines, above Pocock's measured max 160" <<<"$out"; then
  pass "check 30 WARNs (exit 0) on a 161-line body"
else
  fail "check 30 should WARN on 161 body lines, exit 0 (rc=$rc): $out"
fi
if grep -q 'INFO: no base ref for the size-growth comparison' <<<"$out"; then
  pass "check 30 skips growth with an INFO when no base ref resolves"
else
  fail "check 30 should name the missing base ref: $out"
fi
size_skill sz-grow 100 20
git -C "$TMP" add -A && git -C "$TMP" commit -qm 'add sz-grow' >/dev/null
size_skill sz-grow 150 25
out="$( (cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  CHECK_SKILL_BASE_REF=HEAD bash "$SUT" sz-grow) 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: description grew vs HEAD: 100 -> 150 chars' <<<"$out" &&
  grep -q 'WARN: SKILL.md body grew vs HEAD: 20 -> 25 lines' <<<"$out"; then
  pass "check 30 WARNs (exit 0) on description and body growth vs the base ref"
else
  fail "check 30 should WARN on growth vs HEAD, exit 0 (rc=$rc): $out"
fi
size_skill sz-grow 90 18
out="$( (cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  CHECK_SKILL_BASE_REF=HEAD bash "$SUT" sz-grow) 2>&1)"
if ! grep -q 'grew vs' <<<"$out" && grep -q 'INFO: size: description 90 chars, body 18 lines' <<<"$out"; then
  pass "check 30 stays quiet when the skill shrank vs the base ref"
else
  fail "check 30 should not WARN on a shrink: $out"
fi
size_skill sz-new 100 20
out="$( (cd "$TMP" && CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
  CHECK_SKILL_BASE_REF=HEAD bash "$SUT" sz-new) 2>&1)"
if grep -q 'INFO: no HEAD version (new skill): size growth skipped' <<<"$out" && ! grep -q 'grew vs' <<<"$out"; then
  pass "check 30 skips growth with an INFO for a skill new at the base ref"
else
  fail "check 30 should skip growth for a new skill: $out"
fi
router_skill() {
  local md pad
  md=$'---\ndescription: "Do a thing. Use when: \'a thing\' is needed."\ndisable-model-invocation: false\n---\n'
  printf -v pad '%*s' "$(($2 - ${#md}))" ''
  mkdir -p "$SKILLS/$1"
  printf '%s' "$md${pad// /x}" >"$SKILLS/$1/SKILL.md"
}
router_skill sz-router-at 20000
out="$(run sz-router-at 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'above the router cap' <<<"$out" &&
  grep -q 'INFO: SKILL.md about 5000/5000 tokens (router cap)' <<<"$out"; then
  pass "check 30 stays quiet on a SKILL.md at exactly 5000 estimated tokens"
else
  fail "check 30 should be quiet at the router cap (rc=$rc): $out"
fi
router_skill sz-router-over 20001
out="$(run sz-router-over 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: SKILL.md is about 5001 tokens (20001 chars / 4), above the router cap of 5000' <<<"$out"; then
  pass "check 30 WARNs (exit 0) on a SKILL.md above 5000 estimated tokens"
else
  fail "check 30 should WARN above the router cap, exit 0 (rc=$rc): $out"
fi

st_skill() {
  make_skill "$1" "---
name: $1
description: \"Do a thing. Use when: 'a thing' is needed.\"
---

## Purpose

$2

## Gotchas

None known.
"
}
run_st() {
  (cd "$TMP" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      CHECK_SKILL_SETTINGS_TOKEN_BASELINE="$1" bash "$SUT" "$2")
}
ST_EMPTY="$TMP/st-baseline-empty.txt"
: >"$ST_EMPTY"

st_skill st-misread 'When `${user_config.x}` is true, prefix each line with a marker.'
out="$(run_st "$ST_EMPTY" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: settings token used as the subject of a condition with no inline fallback at SKILL.md:8 (x)' <<<"$out"; then
  pass "check 31 FAILs the misread shape 'When \${user_config.x} is true' with its line and key"
else
  fail "check 31 should FAIL the misread shape at SKILL.md:8 (rc=$rc): $out"
fi

st_skill st-unless 'Pass the flag unless `${user_config.y}` is `false`. If `${user_config.z}` is on, add a note.'
out="$(run_st "$ST_EMPTY" st-unless 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'at SKILL.md:8 (y), SKILL.md:8 (z)' <<<"$out"; then
  pass "check 31 FAILs 'unless ... is \`false\`' and 'If ... is on' in one paragraph"
else
  fail "check 31 should FAIL both unless/is-false and if/is-on (rc=$rc): $out"
fi

st_skill st-tidy-form 'HARD path exclusions: `${user_config.hard_exclusions}` (unexpanded, empty, or any value outside `enforce` and `advisory` means `enforce`).

When `${user_config.x}` is true (unexpanded, empty, or any other value means `false`), prefix each line.'
out="$(run_st "$ST_EMPTY" st-tidy-form 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'INFO: no settings token used as a condition without a fallback' <<<"$out"; then
  pass "check 31 passes the code-tidying fallback form, also inside a condition"
else
  fail "check 31 should pass the unexpanded ... means fallback (rc=$rc): $out"
fi

st_skill st-abbrev 'When `${user_config.x}` is true (e.g. on CI; unexpanded or empty means `false`), prefix lines.

When `${user_config.y}` is true, prefix lines, i.e. mark them (unset means false).'
out="$(run_st "$ST_EMPTY" st-abbrev 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'INFO: no settings token used as a condition without a fallback' <<<"$out"; then
  pass "check 31 keeps a sentence whole across e.g. and i.e., so its fallback counts"
else
  fail "check 31 should not split a sentence at e.g. or i.e. (rc=$rc): $out"
fi

st_skill st-subst-verb 'When `${user_config.x}` is true, substitute tabs for spaces.'
out="$(run_st "$ST_EMPTY" st-subst-verb 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'at SKILL.md:8 (x)' <<<"$out"; then
  pass "check 31 FAILs a misread whose only substitution word is about the task, not the token"
else
  fail "check 31 should FAIL 'substitute tabs' as a misread (rc=$rc): $out"
fi

st_skill st-else-form 'Use the rendered `${user_config.active_profile}` value when non-empty, else the root `default`.

When `${user_config.x}` is substituted, Claude Code replaces it before the model reads it.'
out="$(run_st "$ST_EMPTY" st-else-form 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'INFO: no settings token used as a condition without a fallback' <<<"$out"; then
  pass "check 31 passes the 'when non-empty, else the root default' form and substitution prose"
else
  fail "check 31 should pass the non-empty/else form and substitution prose (rc=$rc): $out"
fi

st_skill st-fenced 'Run this:

```bash
# When ${user_config.x} is true, the hook runs.
```

When `enabled` is true, say so.'
out="$(run_st "$ST_EMPTY" st-fenced 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'INFO: no settings token used as a condition without a fallback' <<<"$out"; then
  pass "check 31 skips a token inside a fenced shell block and a non-token code span"
else
  fail "check 31 should skip fenced blocks and non-token code spans (rc=$rc): $out"
fi

st_skill st-long-fence 'Example:

````markdown
```text
When `${user_config.x}` is true, do it.
```
````

When `${user_config.y}` is true, do it.'
out="$(run_st "$ST_EMPTY" st-long-fence 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'fallback at SKILL.md:16 (y)' <<<"$out" && ! grep -q 'SKILL.md:12' <<<"$out"; then
  pass "check 31 keeps a four-backtick fence open across an inner triple-backtick block"
else
  fail "check 31 should skip the nested example and flag only SKILL.md:16 (rc=$rc): $out"
fi

st_skill st-quoted-fence 'Example:

> ```text
> When `${user_config.x}` is true, do it.
> ```

When `${user_config.y}` is true, do it.'
out="$(run_st "$ST_EMPTY" st-quoted-fence 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'fallback at SKILL.md:14 (y)' <<<"$out" && ! grep -q 'SKILL.md:11' <<<"$out"; then
  pass "check 31 skips a fenced block inside a blockquote"
else
  fail "check 31 should skip the quoted fence and flag only SKILL.md:14 (rc=$rc): $out"
fi

st_skill st-quoted-unclosed 'Example:

> ```text
> example

When `${user_config.y}` is true, do it.'
out="$(run_st "$ST_EMPTY" st-quoted-unclosed 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'fallback at SKILL.md:13 (y)' <<<"$out"; then
  pass "check 31 ends a quoted fence when its blockquote ends"
else
  fail "check 31 should end an unclosed quoted fence with its quote and flag SKILL.md:13 (rc=$rc): $out"
fi

st_skill st-spoke 'See `reference/notes.md`.'
mkdir -p "$SKILLS/st-spoke/reference" "$SKILLS/st-spoke/evals"
printf 'Intro.\n\nIf the\n`${user_config.x}` is false, stop.\n' >"$SKILLS/st-spoke/reference/notes.md"
printf 'When `${user_config.x}` is true, do it.\n' >"$SKILLS/st-spoke/evals/case.md"
out="$(run_st "$ST_EMPTY" st-spoke 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'at reference/notes.md:4 (x)' <<<"$out" && ! grep -q 'evals/case.md' <<<"$out"; then
  pass "check 31 reads spoke .md files across wrapped lines and never evals/"
else
  fail "check 31 should flag reference/notes.md:4 and skip evals/ (rc=$rc): $out"
fi

ST_BASE="$TMP/st-baseline.txt"
printf '# fixture\n.claude/skills/st-misread/SKILL.md 1 # pre-existing\n' >"$ST_BASE"
out="$(run_st "$ST_BASE" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: settings token used as a condition with no inline fallback at SKILL.md:8 (x)' <<<"$out"; then
  pass "check 31 WARNs, exit 0, on a baselined file whose count holds"
else
  fail "check 31 should WARN on a baselined file (rc=$rc): $out"
fi
out="$(run_st "$ST_BASE" st-unless 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: settings token used as the subject' <<<"$out"; then
  pass "check 31 FAILs a new skill not in the baseline"
else
  fail "check 31 should FAIL an unlisted skill (rc=$rc): $out"
fi
printf '.claude/skills/st-misread/SKILL.md 2\n' >"$ST_BASE"
out="$(run_st "$ST_BASE" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'now has 1 hit(s), not 2 — lower the row' <<<"$out"; then
  pass "check 31 FAILs a baseline row whose count is now lower"
else
  fail "check 31 should FAIL a row above the live count (rc=$rc): $out"
fi
printf '.claude/skills/st-unless/SKILL.md 1\n' >"$ST_BASE"
out="$(run_st "$ST_BASE" st-unless 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'rose from the baseline.s 1 to 2' <<<"$out"; then
  pass "check 31 FAILs a new hit in a baselined file"
else
  fail "check 31 should FAIL a count rise (rc=$rc): $out"
fi
printf '.claude/skills/st-tidy-form/SKILL.md 1\n.claude/skills/st-tidy-form/reference/gone.md 1\n' >"$ST_BASE"
out="$(run_st "$ST_BASE" st-tidy-form 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'st-tidy-form/SKILL.md now has no hits — remove the row' <<<"$out" &&
  grep -q 'st-tidy-form/reference/gone.md no longer exists — remove the row' <<<"$out"; then
  pass "check 31 FAILs stale rows: a file with no hits and a file that is gone"
else
  fail "check 31 should FAIL zero-hit and missing-file rows (rc=$rc): $out"
fi
# shellcheck disable=SC2016  # the command substitution is the literal payload under test
printf '.claude/skills/st-misread/SKILL.md x[$(touch${IFS}%s)]\n' "$TMP/st-injected" >"$ST_BASE"
out="$(run_st "$ST_BASE" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && [[ ! -e "$TMP/st-injected" ]] && grep -q 'has a non-numeric count — fix the row' <<<"$out"; then
  pass "check 31 FAILs a non-numeric baseline count without evaluating it"
else
  fail "check 31 should FAIL a non-numeric count and never evaluate it (rc=$rc): $out"
fi
out="$(run_st "$TMP/no-such-baseline.txt" st-tidy-form 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'CHECK_SKILL_SETTINGS_TOKEN_BASELINE=.*does not exist' <<<"$out"; then
  pass "check 31 FAILs a named baseline that does not exist"
else
  fail "check 31 should FAIL a missing named baseline (rc=$rc): $out"
fi

run_st_default() {
  (cd "$1" && env -u CHECK_SKILL_SETTINGS_TOKEN_BASELINE \
    CHECK_SKILL_SKILLS_ROOT="$3" CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "$2" "$4")
}
out="$(run_st_default "$TMP" "$SUT" "$SKILLS" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: settings token used as a condition with no inline fallback at SKILL.md:8 (x)' <<<"$out" &&
  grep -q 'no settings-token baseline applies to this run' <<<"$out" && ! grep -q 'FAIL: settings token' <<<"$out"; then
  pass "check 31 WARNs, exit 0, in a consumer git repo with no baseline of its own"
else
  fail "check 31 should WARN in a consumer repo with no baseline (rc=$rc): $out"
fi

ST_PLAIN="$(mktemp -d)"
trap 'rm -rf "$TMP" "$CACHE_TMP" "$WALK_TMP" "$NOGIT_TMP" "$XREPO" "$SCOPE_TMP" "$ST_PLAIN"' EXIT
mkdir -p "$ST_PLAIN/skills"
cp -R "$SKILLS/st-misread" "$ST_PLAIN/skills/"
out="$(GIT_CEILING_DIRECTORIES="$ST_PLAIN" run_st_default "$ST_PLAIN" "$SUT" "$ST_PLAIN/skills" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'WARN: settings token used as a condition with no inline fallback at SKILL.md:8 (x)' <<<"$out" &&
  grep -q 'no settings-token baseline applies to this run' <<<"$out"; then
  pass "check 31 WARNs, exit 0, on a plain tree such as a plugin-cache install"
else
  fail "check 31 should WARN on a plain tree (rc=$rc): $out"
fi

ST_TOOL="$TMP/tools/skill-quality"
mkdir -p "$ST_TOOL"
cp "$SCRIPT_DIR/check-skill.sh" "$SCRIPT_DIR/skill-frontmatter.sh" "$SCRIPT_DIR/metadata-registry.txt" "$ST_TOOL/"
: >"$ST_TOOL/settings-token-baseline.txt"
out="$(run_st_default "$TMP" "$ST_TOOL/check-skill.sh" "$SKILLS" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -q 'FAIL: settings token used as the subject of a condition with no inline fallback at SKILL.md:8 (x)' <<<"$out"; then
  pass "check 31 FAILs an unlisted hit when the checker's own repository is checked"
else
  fail "check 31 should FAIL an unlisted hit in the checker's own repository (rc=$rc): $out"
fi
printf '.claude/skills/st-misread/SKILL.md 1\n' >"$ST_TOOL/settings-token-baseline.txt"
out="$(run_st_default "$TMP" "$ST_TOOL/check-skill.sh" "$SKILLS" st-misread 2>&1)"
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'recorded in scripts/settings-token-baseline.txt' <<<"$out"; then
  pass "check 31 WARNs on a row of the default baseline in the checker's own repository"
else
  fail "check 31 should WARN on a default-baseline row in its own repository (rc=$rc): $out"
fi

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
