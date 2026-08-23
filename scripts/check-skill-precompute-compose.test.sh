#!/usr/bin/env bash
# Unit tests for check-skill-precompute-compose.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-skill-precompute-compose.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins/demo/skills/sample"
  cp "$SCRIPT" "$dir/scripts/check-skill-precompute-compose.sh"
  chmod +x "$dir/scripts/check-skill-precompute-compose.sh"
  printf '%s' "$dir"
}

# Git-backed fixture for <base-ref> / --strict <base-ref> parser paths. Those
# invocations drain the while-loop via the *) fall-through (no --all/--paths
# break), so they assert the $# -gt 0 termination the --paths suite never hits.
new_git_fixture() {
  local dir
  dir="$(new_fixture)"
  git_init_safe "$dir"
  printf '%s' "$dir"
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
f="$(new_fixture)"
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

# --- two precompute lines without git passes ---------------------------------
f="$(new_fixture)"
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

# --- two precompute lines with git warns by default --------------------------
f="$(new_fixture)"
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

# --- strict mode fails -------------------------------------------------------
f="$(new_fixture)"
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

# --- no precompute section passes --------------------------------------------
f="$(new_fixture)"
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
f="$(new_fixture)"
out="$(run_check "$f" 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "no args prints usage and exits 2"
else
  fail "no args should usage/exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- --help / -h -> usage, exit 2 --------------------------------------------
f="$(new_fixture)"
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
f="$(new_fixture)"
out="$(run_check "$f" --strict 2>&1)" && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] && echo "$out" | grep -q '^usage:'; then
  ok "--strict alone prints usage and exits 2"
else
  fail "--strict alone should usage/exit 2 (rc=$rc): $out"
fi
rm -rf "$f"

# --- bare <base-ref> reaches scan via *) drain (no --all/--paths break) ------
f="$(new_git_fixture)"
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
f="$(new_git_fixture)"
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

test_harness::report
