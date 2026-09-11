#!/usr/bin/env bash
# Unit tests for check-skill-precompute-compose.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-skill-precompute-compose.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
f=""

new_fixture() { # <out-var>
  fixture_tree::build "$1" --sut "$SCRIPT" --plugins || return 1
  mkdir -p "${!1}/plugins/demo/skills/sample"
}

# Git-backed fixture for <base-ref> / --strict <base-ref> parser paths. Those
# invocations drain the while-loop via the *) fall-through (no --all/--paths
# break), so they assert the $# -gt 0 termination the --paths suite never hits.
new_git_fixture() { # <out-var>
  new_fixture "$1" || return 1
  git_init_safe "${!1}"
}

skill_md() {
  local fixture="$1" content="$2"
  printf '%s\n' "$content" >"$fixture/plugins/demo/skills/sample/SKILL.md"
}

run_check() (
  cd "$1" && shift
  bash scripts/check-skill-precompute-compose.sh "$@"
)

# --- single git precompute line passes ---------------------------------------
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nBranch: !`git branch --show-current`\n\n## Body\n'
if out="$(run_check "$f" --paths "plugins/demo/skills/sample/SKILL.md" 2>&1)"; then
  if echo "$out" | grep -q '0 violation'; then
    ok "single git precompute line passes"
  else
    fail "single git precompute should pass cleanly: $out"
  fi
else
  fail "single git precompute should exit 0: $out"
fi
rm -rf "$f"

# --- two precompute lines without git passes ---------------------------------
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`date`\nB: !`pwd`\n\n## Body\n'
if out="$(run_check "$f" --paths "plugins/demo/skills/sample/SKILL.md" 2>&1)"; then
  if echo "$out" | grep -q '0 violation'; then
    ok "two non-git precompute lines pass"
  else
    fail "two non-git lines should pass: $out"
  fi
else
  fail "two non-git lines should exit 0: $out"
fi
rm -rf "$f"

# --- two precompute lines with git warns by default --------------------------
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`git branch --show-current`\nB: !`git status --porcelain`\n\n## Body\n'
if out="$(run_check "$f" --paths "plugins/demo/skills/sample/SKILL.md" 2>&1)"; then
  if echo "$out" | grep -q 'VIOLATION:' && echo "$out" | grep -q 'Warn-only'; then
    ok "git + multi-line warns in default mode"
  else
    fail "expected violation + warn-only: $out"
  fi
else
  fail "default mode should exit 0 on violation: $out"
fi
rm -rf "$f"

# --- strict mode fails -------------------------------------------------------
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`git branch --show-current`\nB: !`git status --porcelain`\n\n## Body\n'
if out="$(run_check "$f" --strict --paths "plugins/demo/skills/sample/SKILL.md" 2>&1)"; then
  fail "strict mode should fail on violation"
else
  if echo "$out" | grep -q 'Strict mode: failing'; then
    ok "strict mode fails on violation"
  else
    fail "strict mode message missing: $out"
  fi
fi
rm -rf "$f"

# --- no precompute section passes --------------------------------------------
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Body\n\nNo precompute here.\n'
if out="$(run_check "$f" --paths "plugins/demo/skills/sample/SKILL.md" 2>&1)"; then
  ok "missing precompute section passes"
else
  fail "missing section should pass: $out"
fi
rm -rf "$f"

# =============================================================================
# Argument parser coverage (#2708).
#
# Every case above enters via --paths (or --strict --paths), which break-s out
# of the while-loop before $# reaches 0. Mutating -gt 0 to -ge 0 therefore
# survived the suite: once $# hits 0 the loop body still ran and case "$1"
# unbound-variable-exited under set -u — but only for invocations that drain
# through *) or leave POSITIONAL empty after consuming --strict/--help.
# =============================================================================

# --- no args -> usage, exit 2 ------------------------------------------------
new_fixture f
out="$(run_check "$f" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "no args prints usage and exits 2"
else
  fail "no args should usage/exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- --help / -h -> usage, exit 2 --------------------------------------------
new_fixture f
out="$(run_check "$f" --help 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "--help prints usage and exits 2"
else
  fail "--help should usage/exit 2 (rc=$rc): $out"
fi
out="$(run_check "$f" -h 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "-h prints usage and exits 2"
else
  fail "-h should usage/exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- --strict alone -> usage, exit 2 (drains via --strict then empty) --------
new_fixture f
out="$(run_check "$f" --strict 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "--strict alone prints usage and exits 2"
else
  fail "--strict alone should usage/exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- bare <base-ref> reaches scan via *) drain (no --all/--paths break) ------
new_git_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nBranch: !`git branch --show-current`\n\n## Body\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm base >/dev/null
base="$(git -C "$f" rev-parse HEAD)"
# Empty tip commit so diff vs base is empty — parser must still complete.
git_test_config "$f" commit --allow-empty -qm tip >/dev/null
if out="$(run_check "$f" "$base" 2>&1)"; then
  if echo "$out" | grep -q 'nothing to gate'; then
    ok "bare base-ref drains parser and reaches scan"
  else
    fail "bare base-ref should reach scan (nothing to gate): $out"
  fi
else
  fail "bare base-ref should exit 0 after parse: $out"
fi
rm -rf "$f"

# --- --strict <base-ref> drains --strict then *) and reaches scan ------------
new_git_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`git branch --show-current`\nB: !`git status --porcelain`\n\n## Body\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm base >/dev/null
base="$(git -C "$f" rev-parse HEAD)"
# Change the skill after base so diff-mode actually scans it.
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`git branch --show-current`\nB: !`git status --porcelain`\nC: !`pwd`\n\n## Body\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm change >/dev/null
if out="$(run_check "$f" --strict "$base" 2>&1)"; then
  fail "strict + base-ref should fail on violation after parse"
else
  if echo "$out" | grep -q 'VIOLATION:' && echo "$out" | grep -q 'Strict mode: failing'; then
    ok "--strict base-ref drains parser, scans, and fails closed"
  else
    fail "expected violation + strict fail after --strict base-ref: $out"
  fi
fi
rm -rf "$f"

# --- an invalid base ref exits 2, not a silent "nothing to gate" (#3377) -----
#
# Target discovery runs inside `mapfile -t targets < <( ... )`, and the
# base-ref branch's `exit 2` terminated only that process-substitution
# subshell. `mapfile`'s own status reflects the READ, and a process
# substitution's exit code is not propagated, so the parent saw nothing but an
# empty `targets`, scanned zero files and exited 0. A typo'd branch or a
# shallow clone missing the ref therefore read as "nothing to gate": the error
# text went to stderr, but the exit code CI gates on said success, in exactly
# the case this validation exists to catch.
new_git_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Body\n\nNo precompute here.\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm base >/dev/null
out="$(run_check "$f" no-such-ref-deadbeef 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q 'not a valid commit'; then
  ok "an invalid base ref exits 2"
elif [[ "$rc" -eq 0 ]]; then
  fail "an invalid base ref passed SILENTLY (rc=0), the #3377 shape: $out"
else
  fail "an invalid base ref should exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- a git diff that fails AFTER ref validation exits non-zero ---------------
#
# Validating the ref only covers the ref. Every other way a diff can fail -- a
# shallow clone missing an object, a corrupt pack, an unreadable index --
# resolves the base fine and then dies inside `git diff`, and the hand-rolled
# `mapfile -t targets < <(git diff ...)` this replaced could not see it: the
# parent read an empty `targets`, scanned zero files and exited 0, having
# gated nothing. The fixture reproduces that class exactly by deleting the base
# commit's `plugins` tree object: `<base>^{commit}` still resolves (the commit
# object is intact), and `git diff <base>` cannot read the tree.
new_git_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Body\n\nNo precompute here.\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm base >/dev/null
base="$(git -C "$f" rev-parse HEAD)"
skill_md "$f" $'---\ndescription: test\n---\n\n## Body\n\nStill no precompute.\n'
git_test_config "$f" add -A >/dev/null
git_test_config "$f" commit -qm tip >/dev/null
subtree="$(git -C "$f" rev-parse "$base:plugins")"
rm -f "$f/.git/objects/${subtree:0:2}/${subtree:2}"
if git -C "$f" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  ok "the fixture's base ref still validates (the failure is in the diff, not the ref)"
else
  fail "fixture setup: the base ref stopped resolving, so this asserts the wrong thing"
fi
out="$(run_check "$f" "$base" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  fail "a failed git diff passed SILENTLY (rc=0): $out"
elif echo "$out" | grep -q 'refusing to report an empty change set'; then
  ok "a git diff failure after ref validation exits non-zero"
else
  fail "expected the changed-files refusal diagnostic (rc=$rc): $out"
fi
rm -rf "$f"

# --- --all still scans the tree, and is never base-ref validated -------------
#
# The #3377 fix hoists `git rev-parse` into the parent, so the mode dispatch
# that keeps --all and --paths out of that check is now load-bearing: a fixture
# with no git repository at all must still scan.
new_fixture f
skill_md "$f" $'---\ndescription: test\n---\n\n## Pre-computed context\n\nA: !`git branch --show-current`\nB: !`git status --porcelain`\n\n## Body\n'
out="$(run_check "$f" --all 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q '1 skill(s) scanned, 1 violation'; then
  ok "--all scans the tree with no base-ref validation"
else
  fail "--all should scan the fixture and report its violation (rc=$rc): $out"
fi
rm -rf "$f"

test_harness::report
