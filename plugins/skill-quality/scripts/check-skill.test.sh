#!/usr/bin/env bash
# Black-box contract test for check-skill.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repo with fixture
# skills, runs the checker, and asserts on exit code + output. Mutates only its
# own mktemp dir. markdownlint (check 6) is skipped via the documented test seam
# so the suite needs no Node/npx.
#
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
  (cd "$TMP" &&
    CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
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

# 4a. Missing bare-name skill hints at CHECK_SKILL_SKILLS_ROOT.
out="$(run does-not-exist 2>&1)"
if grep -q 'CHECK_SKILL_SKILLS_ROOT' <<<"$out"; then
  pass "missing bare-name skill hints at CHECK_SKILL_SKILLS_ROOT"
else
  fail "missing bare-name skill should hint at CHECK_SKILL_SKILLS_ROOT: $out"
fi

# 4b. A plugin:skill name gets targeted installed-skill guidance (exit 1, no
#     cache-layout reverse-engineering — the checker points the operator at the
#     root instead).
out="$(run source-control:setup 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] &&
  grep -q 'plugin:skill name' <<<"$out" &&
  grep -q 'CHECK_SKILL_SKILLS_ROOT=~/.claude/plugins/cache' <<<"$out" &&
  grep -q 'setup' <<<"$out"; then
  pass "plugin:skill name gets installed-skill resolution guidance"
else
  fail "plugin:skill name should get installed-skill guidance (rc=$rc): $out"
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

# 5b. A dropped trigger phrase that reappears verbatim in a SIBLING skill's
#     description is a trigger MOVE: warns, names the host, and passes — the
#     listing still routes the phrase (check 3's move exception).
make_skill mover-src '---
name: mover-src
description: "Move fixture. Use when: '"'"'gamma trigger'"'"', '"'"'delta trigger'"'"'."
---

## Purpose

Committed baseline carrying the phrase that will move.
'
git -C "$TMP" add -A
git -C "$TMP" commit -qm 'add mover-src'
# Working tree: mover-src drops delta; sibling mover-dst now carries it.
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

# 5c. Coincidental overlap is NOT a move: when the sibling already carried the
#     phrase at the base ref, dropping it here is a real trigger loss for this
#     skill's routing and still fails (the move exception's base-ref condition).
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
if [[ $rc -eq 1 ]] && grep -q 'dropped trigger keyword' <<<"$out" && ! grep -q 'moved to sibling skill' <<<"$out"; then
  pass "phrase the sibling carried at base is coincidental overlap — still fails"
else
  fail "pre-existing sibling overlap should not count as a move (rc=$rc): $out"
fi

# 6. A relative skills root resolves against CLAUDE_PROJECT_DIR, not the cwd,
#    even when invoked from a subdirectory.
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
out_base="$(cd "$TMP" &&
  CHECK_SKILL_SKILLS_ROOT="$SKILLS" CHECK_SKILL_SKIP_MARKDOWNLINT=1 CHECK_SKILL_BASE_REF=HEAD^ \
    bash "$SUT" baseref-skill 2>&1)"
rc_base=$?
if [[ $rc_head -eq 0 ]] && [[ $rc_base -eq 1 ]] && grep -q 'ref beta' <<<"$out_base"; then
  pass "post-commit base ref catches a committed trigger drop that HEAD misses"
else
  fail "base-ref audit should catch a committed drop HEAD misses (rc_head=$rc_head rc_base=$rc_base): $out_base"
fi

# 11. A block header with the chomp indicator BEFORE the indent indicator
#     (`|-2`, a legal YAML order) is still recognized and unfolded.
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
if [[ $rc -eq 1 ]] && grep -q 'order beta' <<<"$out"; then
  pass "sign-first block header (|-2) is recognized and unfolded"
else
  fail "sign-first block header should be unfolded (rc=$rc): $out"
fi

# 12. A block header with a trailing `# comment` (legal YAML) is still
#     recognized and unfolded.
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
if [[ $rc -eq 1 ]] && grep -q 'comment beta' <<<"$out"; then
  pass "commented block header (| # ...) is recognized and unfolded"
else
  fail "commented block header should be unfolded (rc=$rc): $out"
fi

# 13. A block whose first content line is MORE indented than a later line
#     (e.g. under an explicit `|2`) still captures the later line's triggers —
#     the column-0 boundary is used, not the first line's indent.
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
if [[ $rc -eq 1 ]] && grep -q 'indent beta' <<<"$out"; then
  pass "block content past a more-indented first line is captured (indent indicator honored)"
else
  fail "trigger on a less-indented block line should be tracked (rc=$rc): $out"
fi

# 14. Frontmatter name diverging from the skill directory fails (check 1). The
#     directory name is what the skill is namespaced by, so a mismatch silently
#     relocates the invocation the doctrine says the skill has.
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

# 15. A matching name does not trip the gate — guards the false-positive
#     direction, and proves a quoted value reaches the comparison unquoted.
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

# 16. A trailing YAML comment is not part of the scalar, so a correctly named
#     skill carrying one must not trip the gate (false-positive direction).
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

# 16b. A YAML escape sequence is reported as the name defect it is, rather than
#      surfacing as a confusing directory mismatch. Constraining the accepted
#      syntax is the alternative to decoding YAML in bash.
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

# 17. Comment stripping must not mask a real mismatch.
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

# 18a. A fenced shell block of read-only context-gathering commands, with no `!`
#      injection anywhere, warns (precompute opportunity) but passes.
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

# 18b. A skill that already injects context with inline `!` is silent even when
#      it also carries a qualifying shell block (the whole-file gate).
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

# 18c. A shell block that builds / runs a script is not a read-only context
#      block, so it is not flagged.
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

# 18d. A git block with write subcommands is disqualified by the write-token
#      denylist even though `git` leads every line.
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

# 18e. A mutating git subcommand outside the read-only allowlist (git stash /
#      git clean) is not classified read-only, so no injection is suggested.
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

# 18f. A non-shell fenced block (json) is never scanned, so it is not flagged.
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

# 18g. A read-only gh subcommand nested after the object (gh pr diff, gh run
#      list) is a valid candidate — the object/verb allowlist, not a flat token.
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

# 18h. A read-only head piped into a mutating sink (`git status | tee f`) is NOT
#      a candidate — the first token is read-only but the pipeline sink writes.
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

# 18i. A logical `|| echo` fallback (our recommended defensive form) is not a
#      pipe, so a read-only block using it is still a candidate.
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

# 18j. A command-launching primary (`find -exec`) is not read-only — it runs an
#      arbitrary command — so a block using it is not a candidate.
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

# 18k. A shell continuation after a read-only command (`&&`, `;`) chains a
#      mutation, so the line fails closed.
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

# 18l. A command substitution (`$(...)`) executes during expansion, so a line
#      carrying one is not read-only.
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

# 18m. A file-output option on an allowlisted git reader (`git diff --output`)
#      writes a file, bypassing the redirection guard, so it fails closed.
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

# 18n. An external-program diff option (`git diff --ext-diff`) can run a
#      configured diff.external helper, so it fails closed.
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

# 18o. Only `|| echo` is a sanctioned continuation; a `||` into any other command
#      (`|| bash x`) is a real operator that fails closed.
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

# 18p. find's null-separated file-output primary (`-fprint0`) writes a file, like
#      -fprint/-fprintf, so it fails closed.
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

# 19. vendor/ diff paired with an upstream-version bump is a legitimate sync
#     (check 8's exception, exercised via the maintainer-run `update` flow) —
#     passes rather than tripping the byte-identical guarantee.
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

# 20. vendor/ diff WITHOUT an upstream-version bump still fails — regression
#     guard for the original hand-edit protection check 8 exists for.
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

# 21. A `!` injection with a `shell:` declaration is silent — the author has
#     taken explicit responsibility for the shell (check 19).
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

# 22. A `!` injection with bash-only syntax (/dev/null) and NO `shell:` fails
#     (check 19 — the census regression this gate exists for).
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

# 23. A `!` injection whose commands look portable, with no `shell:`, WARNs
#     (portability is not statically provable) but passes (check 19).
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

# 24. A ```! FENCED injection with bash-only syntax (| head) and no `shell:`
#     fails — exercises the fenced-block extraction feeding check 19.
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

# 25. The over-reach guard: a bash-only token in a PLAIN ```bash block (not an
#     injection) must NOT flag check 19/20 — the scan is scoped to injected text.
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

# 26. An injected command with no `|| <fallback>` warns (check 20), isolated
#     from check 19 by a `shell:` declaration.
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

# 27. A `|| printf` fallback satisfies check 20 — the gate matches the `||`
#     continuation, not the literal `echo`.
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

# 28. Anchor guard: a mid-token `!`` in prose (an inline `#!` code span) is NOT
#     an injection, so a no-shell skill carrying one is not scanned (checks 19/20
#     stay silent). The inline form is recognized only at start / after space.
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

if [[ $fails -ne 0 ]]; then
  printf '%d assertion(s) failed\n' "$fails" >&2
  exit 1
fi
printf 'all assertions passed\n'
