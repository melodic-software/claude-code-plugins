#!/usr/bin/env bash
# Unit tests for check-skill-precompute-compose.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-skill-precompute-compose.sh"

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

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins/demo/skills/sample"
  cp "$SCRIPT" "$dir/scripts/check-skill-precompute-compose.sh"
  chmod +x "$dir/scripts/check-skill-precompute-compose.sh"
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

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
