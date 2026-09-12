#!/usr/bin/env bash
# Unit tests for check-changed-skills.sh. Each scenario builds a throwaway git
# repo, commits a base tree of skills, applies working-tree changes, and runs
# the script with the base commit as <base-ref>. The skill checker is stubbed
# (CHECK_SKILL_BIN) so the tests exercise the orchestrator — changed-skill
# detection, vendor-subtree mapping, dedupe, deletion filtering, env
# passthrough, and pass/fail aggregation — not check-skill.sh itself.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-changed-skills.sh"

# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
r=""

# A stub checker shared by every scenario: records each invocation (skill name +
# forwarded env) to $CHECK_LOG, and FAILs iff the skill is named "bad".
STUB="$(mktemp)"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s root=%s base=%s descbaseline=[%s]\n' "$*" "$CHECK_SKILL_SKILLS_ROOT" "$CHECK_SKILL_BASE_REF" "${CHECK_SKILL_DESC_FIELD_BASELINE-}" >>"$CHECK_LOG"
for arg in "$@"; do
  [[ "$arg" == "bad" ]] && exit 1
done
exit 0
EOF
chmod +x "$STUB"

# mk_repo <out-var>. A fixture runs a COPY of the gate, so the builder stages
# scripts/lib/ with it: without those, the copy dies on a missing source at
# line 1 and every assertion below turns into the same opaque failure.
mk_repo() {
  fixture_tree::build "$1" --sut "$SCRIPT" --git
}

# add_skill <repo> <plugin> <skill> [relpath]  — write a file in a skill dir.
add_skill() {
  local repo="$1" plugin="$2" skill="$3" rel="${4:-SKILL.md}"
  local path="$repo/plugins/$plugin/skills/$skill/$rel"
  mkdir -p "$(dirname "$path")"
  printf 'content %s\n' "$RANDOM" >"$path"
}

commit_all() { git_test_config "$1" add -A && git_test_config "$1" commit -qm "$2"; }
base_sha() { git -C "$1" rev-parse HEAD; }

# run <repo> <base>  — invoke the script from the repo root, stub as checker.
run() (
  cd "$1" && CHECK_SKILL_BIN="$STUB" CHECK_LOG="$1/checklog" \
    bash scripts/check-changed-skills.sh "$2"
)

# stage_checker <repo> — copy the REAL skill-quality checker into a fixture,
# for the integration cases that run it instead of the stub.
stage_checker() {
  mkdir -p "$1/plugins/skill-quality/scripts"
  cp "$SELF_DIR/../plugins/skill-quality/scripts/check-skill.sh" \
    "$SELF_DIR/../plugins/skill-quality/scripts/skill-frontmatter.sh" \
    "$1/plugins/skill-quality/scripts/"
  chmod +x "$1/plugins/skill-quality/scripts/"*.sh
}

# --- no changed skills passes (nothing to gate) ----------------------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf 'unrelated\n' >"$r/README.md" # non-skill change
if out="$(run "$r" "$b" 2>&1)"; then
  if echo "$out" | grep -q "nothing to gate" && [[ "$out" != *"unbound variable"* ]]; then
    ok "no changed skills passes"
  else
    fail "expected nothing-to-gate message without unbound-variable, got: $out"
  fi
else
  fail "no changed skills should pass, got: $out"
fi
rm -rf "$r"

# --- one changed skill, checker passes -------------------------------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md # modify
if out="$(run "$r" "$b" 2>&1)"; then
  if echo "$out" | grep -q "1 skill(s) checked, 0 failed"; then
    ok "one passing skill passes"
  else
    fail "expected 1 checked 0 failed, got: $out"
  fi
else
  fail "passing skill should pass, got: $out"
fi
rm -rf "$r"

# --- a failing checker fails the gate --------------------------------------
mk_repo r
add_skill "$r" p1 bad
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 bad SKILL.md
if run "$r" "$b" >/dev/null 2>&1; then
  fail "a failing skill checker should fail the gate"
else
  ok "failing skill checker fails the gate"
fi
rm -rf "$r"

# --- vendor-subtree change maps to the owning skill, deduped ---------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md # touch two paths in one skill
add_skill "$r" p1 alpha vendor/tool/SKILL.md
run "$r" "$b" >/dev/null 2>&1
n="$(grep -c "args=.*alpha" "$r/checklog" 2>/dev/null || echo 0)"
if [[ "$n" == "1" ]]; then
  ok "vendor subtree maps to owning skill, checked once"
else
  fail "expected alpha checked exactly once, got $n"
fi
rm -rf "$r"

# --- env passthrough: skills root and base ref reach the checker -----------
mk_repo r
add_skill "$r" p2 beta
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p2 beta SKILL.md
run "$r" "$b" >/dev/null 2>&1
if grep -q "args=--require-evals beta root=$r/plugins/p2/skills base=$b" "$r/checklog" 2>/dev/null; then
  ok "checker receives skill name, skills root, base ref, and --require-evals on SKILL.md change"
else
  fail "env passthrough wrong, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- a deleted skill is filtered, not gated --------------------------------
mk_repo r
add_skill "$r" p1 alpha
add_skill "$r" p1 gone
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
rm -rf "$r/plugins/p1/skills/gone"
if out="$(run "$r" "$b" 2>&1)"; then
  if echo "$out" | grep -q "nothing to gate"; then
    ok "deleted skill is filtered out"
  else
    fail "deleted-only change should gate nothing, got: $out"
  fi
else
  fail "deleting a skill should not fail the gate, got: $out"
fi
rm -rf "$r"

# --- an invalid base ref fails closed (env error) --------------------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
run "$r" "does-not-exist" >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2, got $rc"
fi
rm -rf "$r"

# --- a missing checker fails closed ----------------------------------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md
(cd "$r" && CHECK_SKILL_BIN="$r/nope.sh" CHECK_LOG="$r/l" \
  bash scripts/check-changed-skills.sh "$b") >/dev/null 2>&1
rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "missing checker exits 2 (fail closed)"
else
  fail "missing checker should exit 2, got $rc"
fi
rm -rf "$r"

# --- SKILL.md change forwards --require-evals to the checker ----------------
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md
run "$r" "$b" >/dev/null 2>&1
if grep -q 'args=--require-evals alpha ' "$r/checklog" 2>/dev/null; then
  ok "SKILL.md change forwards --require-evals"
else
  fail "SKILL.md change should forward --require-evals, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- a non-SKILL.md touch does not forward --require-evals ------------------
mk_repo r
add_skill "$r" p1 alpha
add_skill "$r" p1 alpha context/note.md
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf 'updated\n' >"$r/plugins/p1/skills/alpha/context/note.md"
out="$(run "$r" "$b" 2>&1)"
if grep -q 'args=alpha ' "$r/checklog" 2>/dev/null &&
  ! grep -q 'args=--require-evals alpha ' "$r/checklog" 2>/dev/null &&
  [[ "$out" != *"unbound variable"* ]]; then
  ok "non-SKILL.md touch does not forward --require-evals"
else
  fail "context-only change should not forward --require-evals, got: $(cat "$r/checklog" 2>/dev/null) out=$out"
fi
rm -rf "$r"

# --- integration: a new skill without evals fails the gate ------------------
mk_repo r
stage_checker "$r"
printf 'base\n' >"$r/README.md"
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
mkdir -p "$r/plugins/p1/skills/newbie"
cat >"$r/plugins/p1/skills/newbie/SKILL.md" <<'EOF'
---
description: "A new skill. Use when: 'testing the evals ratchet'."
disable-model-invocation: false
---

## Purpose

Fixture for the evals-presence ratchet.

## Gotchas

None known.
EOF
git -C "$r" add plugins/p1/skills/newbie/SKILL.md
if (cd "$r" && CHECK_SKILL_BIN="$r/plugins/skill-quality/scripts/check-skill.sh" \
  bash scripts/check-changed-skills.sh "$b") >/dev/null 2>&1; then
  fail "new skill without evals should fail the changed-skill gate"
else
  ok "new skill without evals fails the changed-skill gate"
fi
rm -rf "$r"

# --- integration: a touched legacy skill without evals fails the gate --------
mk_repo r
stage_checker "$r"
mkdir -p "$r/plugins/p1/skills/legacy"
cat >"$r/plugins/p1/skills/legacy/SKILL.md" <<'EOF'
---
description: "A legacy skill. Use when: 'testing the evals ratchet'."
disable-model-invocation: false
---

## Purpose

Fixture for the evals-presence ratchet.

## Gotchas

None known.
EOF
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf '\n## Notes\n\nTouched for the ratchet test.\n' >>"$r/plugins/p1/skills/legacy/SKILL.md"
if (cd "$r" && CHECK_SKILL_BIN="$r/plugins/skill-quality/scripts/check-skill.sh" \
  bash scripts/check-changed-skills.sh "$b") >/dev/null 2>&1; then
  fail "touched legacy skill without evals should fail the changed-skill gate"
else
  ok "touched legacy skill without evals fails the changed-skill gate"
fi
rm -rf "$r"

# --- integration: a touched legacy skill with evals passes the gate --------
mk_repo r
stage_checker "$r"
mkdir -p "$r/plugins/p1/skills/legacy/evals"
cat >"$r/plugins/p1/skills/legacy/SKILL.md" <<'EOF'
---
description: "A legacy skill. Use when: 'testing the evals ratchet'."
disable-model-invocation: false
---

## Purpose

Fixture for the evals-presence ratchet.

## Gotchas

None known.
EOF
cat >"$r/plugins/p1/skills/legacy/evals/evals.json" <<'EOF'
{
  "skill_name": "legacy",
  "evals": [
    {
      "id": "1",
      "name": "happy-path",
      "prompt": "run legacy",
      "expected_output": "Runs the legacy skill.",
      "expectations": ["Output routes to the legacy skill"]
    }
  ]
}
EOF
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf '\n## Notes\n\nTouched for the ratchet test.\n' >>"$r/plugins/p1/skills/legacy/SKILL.md"
if (cd "$r" && CHECK_SKILL_BIN="$r/plugins/skill-quality/scripts/check-skill.sh" \
  bash scripts/check-changed-skills.sh "$b") >/dev/null 2>&1; then
  ok "touched legacy skill with evals passes the changed-skill gate"
else
  fail "touched legacy skill with evals should pass the changed-skill gate"
fi
rm -rf "$r"

# --- recorded warrant skip is not passed --require-evals (#3135) -----------
mk_repo r
add_skill "$r" p1 skipme
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 skipme SKILL.md
printf '%s\n' 'plugins/p1/skills/skipme  # test skip' >"$r/scripts/evals-warrant-exemptions.txt"
run "$r" "$b" >/dev/null 2>&1
if grep -q "args=skipme " "$r/checklog" 2>/dev/null &&
  ! grep -q "args=--require-evals skipme" "$r/checklog" 2>/dev/null; then
  ok "recorded warrant skip is not passed --require-evals"
else
  fail "exempted skill should not receive --require-evals, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- stale exemption (skill now ships evals) fails -------------------------
mk_repo r
add_skill "$r" p1 skipme
mkdir -p "$r/plugins/p1/skills/skipme/evals"
printf '{}\n' >"$r/plugins/p1/skills/skipme/evals/evals.json"
printf '%s\n' 'plugins/p1/skills/skipme  # stale' >"$r/scripts/evals-warrant-exemptions.txt"
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 skipme SKILL.md
out="$(run "$r" "$b" 2>&1)"
rc=$?
if [[ $rc -ne 0 ]]; then
  ok "stale evals exemption (skill ships evals) fails"
else
  fail "stale evals exemption (skill ships evals) should fail"
fi
if [[ "$out" == *"STALE BASELINE: "*"'plugins/p1/skills/skipme' names a skill that now ships evals"* ]]; then
  ok "the stale exemption carries the shared STALE BASELINE prefix"
else
  fail "expected the shared STALE BASELINE diagnostic, got: $out"
fi
rm -rf "$r"

# --- a final exemption row with no trailing newline is still loaded --------
# The hand-rolled reader this replaced kept such a row only because it carried
# the `|| [[ -n "$raw" ]]` tail by hand; the shared reader owns that now, and
# dropping the row would silently hand the skill --require-evals.
mk_repo r
add_skill "$r" p1 skipme
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 skipme SKILL.md
printf '%s' 'plugins/p1/skills/skipme' >"$r/scripts/evals-warrant-exemptions.txt"
run "$r" "$b" >/dev/null 2>&1
if ! grep -q "args=--require-evals skipme" "$r/checklog" 2>/dev/null; then
  ok "a final exemption row with no trailing newline is loaded"
else
  fail "unterminated final exemption row was dropped: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- description field-cap baseline is handed to the checker (#3845) -------
# The gate owns WHERE the recorded pre-existing breaches live; check-skill.sh owns
# what a row means. These two cases pin the handoff: present file goes through as
# an absolute path, absent file goes through EMPTY rather than as a path that is
# not there — empty means "no downgrades", which is the strict direction.
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md
printf '%s\n' 'plugins/p1/skills/alpha' >"$r/scripts/skill-description-cap-baseline.txt"
run "$r" "$b" >/dev/null 2>&1
if grep -q "descbaseline=\[$r/scripts/skill-description-cap-baseline.txt\]" "$r/checklog" 2>/dev/null; then
  ok "the recorded description-cap baseline is passed to the checker"
else
  fail "expected the baseline path in the checker env, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md
run "$r" "$b" >/dev/null 2>&1
if grep -q 'descbaseline=\[\]' "$r/checklog" 2>/dev/null; then
  ok "no baseline file means an empty setting (no downgrades), not a missing path"
else
  fail "expected an empty baseline setting, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- integration: an over-cap description fails the gate, baselined passes --
# End to end through the real checker, because the acceptance this covers is
# that a breach fails in the repository's NORMAL validation path, not that a
# constant somewhere reads 1024.
mk_over_cap_repo() { # <out-var>
  local repo desc
  mk_repo "$1" || return 1
  repo="${!1}"
  stage_checker "$repo"
  desc="$(printf 'd%.0s' $(seq 1 1025))"
  mkdir -p "$repo/plugins/p1/skills/wordy/evals"
  {
    printf -- '---\n'
    printf 'description: "%s"\n' "$desc"
    printf 'disable-model-invocation: false\n'
    printf -- '---\n\n## Purpose\n\nFixture: 1025-codepoint description, one over the spec field maximum.\n\n## Gotchas\n\nNone known.\n'
  } >"$repo/plugins/p1/skills/wordy/SKILL.md"
  cat >"$repo/plugins/p1/skills/wordy/evals/evals.json" <<'EOF'
{
  "skill_name": "wordy",
  "evals": [
    {
      "id": "1",
      "name": "happy-path",
      "prompt": "run wordy",
      "expected_output": "Runs the wordy skill.",
      "expectations": ["Output routes to the wordy skill"]
    }
  ]
}
EOF
}

mk_over_cap_repo r
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf '\n## Notes\n\nTouched.\n' >>"$r/plugins/p1/skills/wordy/SKILL.md"
if out="$( (cd "$r" && CHECK_SKILL_BIN="$r/plugins/skill-quality/scripts/check-skill.sh" \
  bash scripts/check-changed-skills.sh "$b") 2>&1)"; then
  fail "an over-cap description should fail the changed-skill gate, got: $out"
else
  if grep -q 'description alone is 1025 codepoints' <<<"$out"; then
    ok "an over-cap description fails the changed-skill gate, naming the count"
  else
    fail "gate failed but not on the field cap: $out"
  fi
fi
rm -rf "$r"

mk_over_cap_repo r
printf '%s\n' 'plugins/p1/skills/wordy' >"$r/scripts/skill-description-cap-baseline.txt"
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf '\n## Notes\n\nTouched.\n' >>"$r/plugins/p1/skills/wordy/SKILL.md"
if (cd "$r" && CHECK_SKILL_BIN="$r/plugins/skill-quality/scripts/check-skill.sh" \
  bash scripts/check-changed-skills.sh "$b") >/dev/null 2>&1; then
  ok "a recorded pre-existing breach passes the changed-skill gate"
else
  fail "a baselined over-cap description should pass the changed-skill gate"
fi
rm -rf "$r"

rm -f "$STUB"
test_harness::report
