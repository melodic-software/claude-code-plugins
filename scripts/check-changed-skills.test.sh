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

# A fixture runs a COPY of the gate, so it must also carry the shared
# libraries that copy sources (scripts/lib/*.sh). Staging them here keeps the
# fixture a faithful copy; without it the copied gate dies on a missing
# source at line 1 and every assertion below turns into the same opaque
# failure. See #2914.
stage_libs() {
  mkdir -p "$1/lib"
  cp "$SELF_DIR/lib/changed-files.sh" "$1/lib/"
}
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# A stub checker shared by every scenario: records each invocation (skill name +
# forwarded env) to $CHECK_LOG, and FAILs iff the skill is named "bad".
STUB="$(mktemp)"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s root=%s base=%s\n' "$*" "$CHECK_SKILL_SKILLS_ROOT" "$CHECK_SKILL_BASE_REF" >>"$CHECK_LOG"
for arg in "$@"; do
  [[ "$arg" == "bad" ]] && exit 1
done
exit 0
EOF
chmod +x "$STUB"

mk_repo() {
  local dir
  dir="$(mktemp -d)"
  git_init_safe "$dir"
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-changed-skills.sh"
  stage_libs "$dir/scripts"
  printf '%s' "$dir"
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
r="$(mk_repo)"
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf 'unrelated\n' >"$r/README.md" # non-skill change
if out="$(run "$r" "$b" 2>&1)"; then
  if echo "$out" | grep -q "nothing to gate"; then
    ok "no changed skills passes"
  else
    fail "expected nothing-to-gate message, got: $out"
  fi
else
  fail "no changed skills should pass, got: $out"
fi
rm -rf "$r"

# --- one changed skill, checker passes -------------------------------------
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
add_skill "$r" p1 alpha
add_skill "$r" p1 alpha context/note.md
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
printf 'updated\n' >"$r/plugins/p1/skills/alpha/context/note.md"
run "$r" "$b" >/dev/null 2>&1
if grep -q 'args=alpha ' "$r/checklog" 2>/dev/null &&
  ! grep -q 'args=--require-evals alpha ' "$r/checklog" 2>/dev/null; then
  ok "non-SKILL.md touch does not forward --require-evals"
else
  fail "context-only change should not forward --require-evals, got: $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r"

# --- integration: a new skill without evals fails the gate ------------------
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
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
r="$(mk_repo)"
add_skill "$r" p1 skipme
mkdir -p "$r/plugins/p1/skills/skipme/evals"
printf '{}\n' >"$r/plugins/p1/skills/skipme/evals/evals.json"
printf '%s\n' 'plugins/p1/skills/skipme  # stale' >"$r/scripts/evals-warrant-exemptions.txt"
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 skipme SKILL.md
if run "$r" "$b" >/dev/null 2>&1; then
  fail "stale evals exemption (skill ships evals) should fail"
else
  ok "stale evals exemption (skill ships evals) fails"
fi
rm -rf "$r"

rm -f "$STUB"
test_harness::report
