#!/usr/bin/env bash
# Unit tests for check-changed-skills.sh. Each scenario builds a throwaway git
# repo, commits a base tree of skills, applies working-tree changes, and runs
# the script with the base commit as <base-ref>. The skill checker is stubbed
# (CHECK_SKILL_BIN) so the tests exercise the orchestrator — changed-skill
# detection, vendor-subtree mapping, dedupe, deletion filtering, env
# passthrough, and pass/fail aggregation — not check-skill.sh itself.
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

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
# forwarded env) to $CHECK_LOG, and FAILs iff the skill is named "broken".
STUB="$(mktemp "$TMP_ROOT/f.XXXXXX")"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s root=%s base=%s\n' "$*" "$CHECK_SKILL_SKILLS_ROOT" "$CHECK_SKILL_BASE_REF" >>"$CHECK_LOG"
for arg in "$@"; do
  [[ "$arg" == "broken" ]] && exit 1
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
  if grep -q "nothing to gate" <<<"$out" && [[ "$out" != *"unbound variable"* ]]; then
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
  if grep -q "1 skill(s) checked, 0 failed" <<<"$out"; then
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
add_skill "$r" p1 broken
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 broken SKILL.md
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
  if grep -q "nothing to gate" <<<"$out"; then
    ok "deleted skill is filtered out"
  else
    fail "deleted-only change should gate nothing, got: $out"
  fi
else
  fail "deleting a skill should not fail the gate, got: $out"
fi
rm -rf "$r"

# --- a branch behind its base is judged on its own changes (#7014) ----------
# main moves on after the branch point and touches skill "broken" (the stub's
# failing skill); the branch touches only "alpha". Against main's TIP a two-dot
# diff would select "broken" too and fail the gate; against the merge base only
# "alpha" is checked, and the checker is handed the merge base as its base ref.
mk_repo r
add_skill "$r" p1 alpha
add_skill "$r" p1 broken
commit_all "$r" base >/dev/null
fork="$(base_sha "$r")"
git -C "$r" checkout -q -b feature
add_skill "$r" p1 alpha SKILL.md
commit_all "$r" "branch touches alpha" >/dev/null
git -C "$r" checkout -q -b main-moved "$fork"
add_skill "$r" p1 broken SKILL.md
commit_all "$r" "main touches broken" >/dev/null
tip="$(base_sha "$r")"
git -C "$r" checkout -q feature
if out="$(run "$r" "$tip" 2>&1)"; then
  if grep -q "1 skill(s) checked, 0 failed" <<<"$out" &&
    grep -q "args=--require-evals alpha root=.* base=$fork" "$r/checklog" 2>/dev/null &&
    ! grep -q 'broken' "$r/checklog" 2>/dev/null; then
    ok "a stale branch is judged against the merge base, not the base tip"
  else
    fail "stale branch should check only alpha against the merge base, got: $out log: $(cat "$r/checklog" 2>/dev/null)"
  fi
else
  fail "a skill only the base changed must not fail a stale branch, got: $out"
fi
rm -rf "$r"

# --- no merge base: the ref is used as given, with a warning ----------------
# Unrelated history (an orphan branch) has no merge base with the ref; the gate
# warns and diffs against the ref itself rather than skipping the check.
mk_repo r
printf 'base\n' >"$r/README.md"
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
git -C "$r" checkout -q --orphan unrelated
add_skill "$r" p1 alpha
commit_all "$r" "unrelated history" >/dev/null
out="$(run "$r" "$b" 2>&1)"
if grep -q "Warning: no merge base for $b and HEAD" <<<"$out" &&
  grep -q "args=--require-evals alpha root=.* base=$b" "$r/checklog" 2>/dev/null; then
  ok "no merge base warns and checks against the ref as given"
else
  fail "no merge base should warn and pass the ref through, got: $out log: $(cat "$r/checklog" 2>/dev/null)"
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

# --- integration: an over-cap description fails the gate --------------------
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

# --- --merge-base: the lane form -------------------------------------------
# The tool tree holds the gate and its checker; the data tree is the checkout
# the lane judges, with a decoy checker that must never run.
# shellcheck disable=SC2016  # the stub expands these when it runs
LANE_STUB='#!/usr/bin/env bash
printf "self=%s args=%s skip=%s md=%s st=%s base=%s\n" "$0" "$*" "${CHECK_SKILL_SKIP_SCRIPT_TESTS-}" \
  "${CHECK_SKILL_SKIP_MARKDOWNLINT-}" "${CHECK_SKILL_SETTINGS_TOKEN_BASELINE-}" "$CHECK_SKILL_BASE_REF" >>"$CHECK_LOG"
for arg in "$@"; do [[ "$arg" == broken ]] && exit 1; done
exit 0'

# mk_lane_pair <tool-var> <data-var>: a tool tree with the stub checker, and a
# data repo with a committed skill, a decoy checker and a settings baseline.
mk_lane_pair() {
  mk_repo "$1" || return 1
  mk_repo "$2" || return 1
  local tool="${!1}" data="${!2}"
  mkdir -p "$tool/plugins/skill-quality/scripts" "$data/plugins/skill-quality/scripts"
  printf '%s\n' "$LANE_STUB" >"$tool/plugins/skill-quality/scripts/check-skill.sh"
  printf '#!/usr/bin/env bash\ntouch "%s/decoy-ran"\n' "$data" >"$data/plugins/skill-quality/scripts/check-skill.sh"
  : >"$data/plugins/skill-quality/scripts/settings-token-baseline.txt"
  add_skill "$data" p1 alpha
  commit_all "$data" base >/dev/null
}

# run_lane <tool> <data> [args...]: run the tool tree's gate from outside both.
run_lane() (
  local tool="$1" data="$2"
  shift 2
  cd "$TMP_ROOT" && CHECK_DATA_ROOT="$data" CHECK_SKILL_BIN="$data/plugins/skill-quality/scripts/check-skill.sh" \
    CHECK_LOG="$data/checklog" bash "$tool/scripts/check-changed-skills.sh" "$@"
)

t="" d=""
mk_lane_pair t d
b="$(base_sha "$d")"
git_test_config "$d" update-ref refs/remotes/origin/main "$b"
add_skill "$d" p1 alpha SKILL.md # tracked change
add_skill "$d" p2 fresh          # untracked new skill
if out="$(run_lane "$t" "$d" --merge-base 2>&1)" && grep -q "2 skill(s) checked, 0 failed" <<<"$out"; then
  ok "--merge-base checks the data tree's tracked and untracked changed skills"
else
  fail "--merge-base should check alpha and fresh, got: $out"
fi
log="$(cat "$d/checklog" 2>/dev/null)"
want_self="$t/scripts/../plugins/skill-quality/scripts/check-skill.sh"
if grep -qxF "self=$want_self args=--require-evals alpha skip=1 md=1 st=$d/plugins/skill-quality/scripts/settings-token-baseline.txt base=$b" <<<"$log" &&
  grep -qF "self=$want_self args=--require-evals fresh skip=1 md=1" <<<"$log"; then
  ok "--merge-base runs the tool tree's checker with script tests skipped and the data tree's settings baseline"
else
  fail "unexpected checker invocations: $log"
fi
if [[ ! -e "$d/decoy-ran" ]]; then
  ok "--merge-base never runs the data tree's checker, even when CHECK_SKILL_BIN names it"
else
  fail "the data tree's checker ran"
fi
rm -rf "$t" "$d"

mk_lane_pair t d
git_test_config "$d" branch -q -m lanework # no origin/main, origin/master, main or master
add_skill "$d" p1 alpha SKILL.md
out="$(run_lane "$t" "$d" --merge-base 2>&1)"
rc=$?
if ((rc == 0)) && grep -q "diffing against HEAD" <<<"$out" &&
  grep -q "args=--require-evals alpha .* base=$(base_sha "$d")$" "$d/checklog" 2>/dev/null; then
  ok "--merge-base falls back to HEAD, with a warning, when no default branch resolves"
else
  fail "expected the HEAD fallback, rc=$rc, got: $out / $(cat "$d/checklog" 2>/dev/null)"
fi
rm -rf "$t" "$d"

mk_lane_pair t d
if out="$(run_lane "$t" "$d" --merge-base HEAD 2>&1)"; then
  fail "--merge-base with a ref should be a usage error, got: $out"
elif [[ $? -eq 2 ]] && grep -q "usage:" <<<"$out"; then
  ok "--merge-base takes no ref"
else
  fail "expected exit 2 with usage, got: $out"
fi
rm -rf "$t" "$d"

# The positional form keeps checking its own tree and honoring CHECK_SKILL_BIN,
# whatever CHECK_DATA_ROOT says, and leaves script tests to the checker.
mk_repo r
add_skill "$r" p1 alpha
commit_all "$r" base >/dev/null
b="$(base_sha "$r")"
add_skill "$r" p1 alpha SKILL.md
lane_stub="$TMP_ROOT/lane-stub.sh"
printf '%s\n' "$LANE_STUB" >"$lane_stub"
if out="$( (cd "$r" && CHECK_DATA_ROOT=/nonexistent CHECK_SKILL_BIN="$lane_stub" CHECK_LOG="$r/checklog" \
  bash scripts/check-changed-skills.sh "$b") 2>&1)" &&
  grep -qxF "self=$lane_stub args=--require-evals alpha skip= md=1 st= base=$b" "$r/checklog"; then
  ok "the positional form ignores CHECK_DATA_ROOT and keeps its checker and environment"
else
  fail "positional form changed, got: $out / $(cat "$r/checklog" 2>/dev/null)"
fi
rm -rf "$r" "$lane_stub"

# End to end through the real checker: a new, untracked skill with no evals
# fails the lane form, as it fails CI once committed.
mk_lane_pair t d
stage_checker "$t"
git_test_config "$d" update-ref refs/remotes/origin/main "$(base_sha "$d")"
mkdir -p "$d/plugins/p3/skills/newbie"
printf -- '---\ndescription: "Fixture skill. Use when: '"'"'run newbie'"'"'."\n---\n\n## Purpose\n\nFixture.\n\n## Gotchas\n\nNone known.\n' \
  >"$d/plugins/p3/skills/newbie/SKILL.md"
if out="$(run_lane "$t" "$d" --merge-base 2>&1)"; then
  fail "an untracked skill with no evals should fail the lane form, got: $out"
elif grep -q 'skill ships no evals/evals.json' <<<"$out" && [[ ! -e "$d/decoy-ran" ]]; then
  ok "an untracked skill with no evals fails the lane form through the tool tree's real checker"
else
  fail "lane form failed, but not on the missing evals: $out"
fi
rm -rf "$t" "$d"

rm -f "$STUB"
test_harness::report
