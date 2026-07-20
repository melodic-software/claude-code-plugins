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

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# A stub checker shared by every scenario: records each invocation (skill name +
# forwarded env) to $CHECK_LOG, and FAILs iff the skill is named "bad".
STUB="$(mktemp)"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'name=%s root=%s base=%s\n' "$1" "$CHECK_SKILL_SKILLS_ROOT" "$CHECK_SKILL_BASE_REF" >>"$CHECK_LOG"
[[ "$1" == "bad" ]] && exit 1
exit 0
EOF
chmod +x "$STUB"

mk_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name test
  git -C "$dir" config commit.gpgsign false
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-changed-skills.sh"
  printf '%s' "$dir"
}

# add_skill <repo> <plugin> <skill> [relpath]  — write a file in a skill dir.
add_skill() {
  local repo="$1" plugin="$2" skill="$3" rel="${4:-SKILL.md}"
  local path="$repo/plugins/$plugin/skills/$skill/$rel"
  mkdir -p "$(dirname "$path")"
  printf 'content %s\n' "$RANDOM" >"$path"
}

commit_all() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
base_sha() { git -C "$1" rev-parse HEAD; }

# run <repo> <base>  — invoke the script from the repo root, stub as checker.
run() (
  cd "$1" && CHECK_SKILL_BIN="$STUB" CHECK_LOG="$1/checklog" \
    bash scripts/check-changed-skills.sh "$2"
)

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
n="$(grep -c "name=alpha" "$r/checklog" 2>/dev/null || echo 0)"
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
if grep -q "name=beta root=$r/plugins/p2/skills base=$b" "$r/checklog" 2>/dev/null; then
  ok "checker receives skill name, skills root, and base ref"
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

rm -f "$STUB"
echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
