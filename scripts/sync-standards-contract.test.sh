#!/usr/bin/env bash
# Unit tests for sync-standards-contract.sh. Builds a tiny synthetic repo tree
# per scenario in a temp dir (git-initialized where --check-bump needs a base
# ref) and invokes the script against it directly -- the script's own
# `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it operates on the fixture tree.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/sync-standards-contract.sh"

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

CANONICAL="docs/conventions/standards/README.md"
CHANGELOG="docs/conventions/standards/CHANGELOG.md"
SCHEMA="docs/conventions/standards/standards.schema.json"

canonical_v1() {
  printf -- '---\nstandards-contract: 1.0.0\n---\n\n# Standards Convention\n\ncontract body v1\n'
}
canonical_v1_edited() {
  printf -- '---\nstandards-contract: 1.0.0\n---\n\n# Standards Convention\n\ncontract body v1 EDITED without a version change\n'
}
canonical_v1_1() {
  printf -- '---\nstandards-contract: 1.1.0\n---\n\n# Standards Convention\n\ncontract body v1.1\n'
}
changelog_v1() {
  printf -- '# Changelog\n\n## 1.0.0 — 2026-07-17\n\n- initial\n'
}
changelog_v1_1() {
  printf -- '# Changelog\n\n## 1.1.0 — 2026-07-18\n\n- additive\n\n## 1.0.0 — 2026-07-17\n\n- initial\n'
}

# new_fixture → fresh tree with the script copied in; callers populate content.
new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/docs/conventions/standards" "$dir/plugins"
  cp "$SCRIPT" "$dir/scripts/sync-standards-contract.sh"
  chmod +x "$dir/scripts/sync-standards-contract.sh"
  printf '%s' "$dir"
}

# carrying_plugin <fixture> <plugin> <copy-content> <version>
carrying_plugin() {
  local fixture="$1" plugin="$2" content="$3" version="$4"
  mkdir -p "$fixture/plugins/$plugin/reference" "$fixture/plugins/$plugin/.claude-plugin"
  # %s\n restores the single trailing newline the callers' $(...) stripped,
  # keeping "identical" fixtures byte-identical to the canonical file.
  printf '%s\n' "$content" >"$fixture/plugins/$plugin/reference/standards-contract.md"
  printf '{"name":"%s","version":"%s"}\n' "$plugin" "$version" \
    >"$fixture/plugins/$plugin/.claude-plugin/plugin.json"
}

# git_fixture <fixture> → init repo + commit everything as the base ref; prints base sha
git_fixture() {
  local fixture="$1"
  git -C "$fixture" init -q
  git -C "$fixture" config core.autocrlf false
  git -C "$fixture" config user.email test@example.com
  git -C "$fixture" config user.name test
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm base
  git -C "$fixture" rev-parse HEAD
}

run_mode() (
  local fixture="$1"
  shift
  cd "$fixture" && bash scripts/sync-standards-contract.sh "$@"
)

# --- sync copies the canonical into every carrying plugin -------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "stale copy" 0.1.0
carrying_plugin "$f" review "another stale copy" 0.1.0
if out="$(run_mode "$f" 2>&1)" &&
  cmp -s "$f/$CANONICAL" "$f/plugins/planning/reference/standards-contract.md" &&
  cmp -s "$f/$CANONICAL" "$f/plugins/review/reference/standards-contract.md"; then
  ok "sync makes every carrying copy byte-identical to the canonical"
else
  fail "sync should copy the canonical into both plugins, got: $out"
fi
rm -rf "$f"

# --- sync with no carrying plugins errors ----------------------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
if out="$(run_mode "$f" 2>&1)"; then
  fail "sync with zero carrying plugins should error, got success: $out"
else
  ok "sync with zero carrying plugins errors"
fi
rm -rf "$f"

# --- --check passes when identical -----------------------------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
if out="$(run_mode "$f" --check 2>&1)"; then
  ok "--check passes when all copies match"
else
  fail "--check should pass on identical copies, got: $out"
fi
rm -rf "$f"

# --- --check fails on a drifted copy ---------------------------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "drifted copy" 0.1.0
if out="$(run_mode "$f" --check 2>&1)"; then
  fail "--check should fail on a drifted copy, got success: $out"
else
  if echo "$out" | grep -q "DRIFT"; then
    ok "--check fails on a drifted copy with DRIFT"
  else
    fail "expected DRIFT in output, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: canonical unchanged vs base → pass ----------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  ok "--check-bump passes when the canonical is unchanged"
else
  fail "--check-bump should pass when canonical unchanged, got: $out"
fi
rm -rf "$f"

# --- --check-bump: change + frontmatter bump + changelog heading + manifest bumps → pass
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1_1)" 0.2.0
carrying_plugin "$f" review "$(canonical_v1_1)" 0.2.0
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  ok "--check-bump passes on a fully-bumped contract change"
else
  fail "--check-bump should pass when frontmatter, changelog, and manifests all moved, got: $out"
fi
rm -rf "$f"

# --- --check-bump: carrying plugin manifest not bumped → fail ---------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1_1)" 0.2.0
carrying_plugin "$f" review "$(canonical_v1_1)" 0.1.0 # not bumped
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  fail "--check-bump should fail when a carrying plugin kept its version, got success: $out"
else
  if echo "$out" | grep -q "STALE VERSION"; then
    ok "--check-bump fails an unbumped carrying plugin with STALE VERSION"
  else
    fail "expected STALE VERSION in output, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: content changed but frontmatter semver did not → fail ----
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_edited >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1_edited)" 0.2.0
carrying_plugin "$f" review "$(canonical_v1_edited)" 0.2.0
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  fail "--check-bump should fail when the standards-contract semver did not change, got success: $out"
else
  if echo "$out" | grep -q "STALE CONTRACT VERSION"; then
    ok "--check-bump fails an unbumped standards-contract frontmatter with STALE CONTRACT VERSION"
  else
    fail "expected STALE CONTRACT VERSION in output, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: content changed but changelog gained no new heading → fail
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
# changelog untouched
carrying_plugin "$f" planning "$(canonical_v1_1)" 0.2.0
carrying_plugin "$f" review "$(canonical_v1_1)" 0.2.0
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  fail "--check-bump should fail when the changelog gained no new heading, got success: $out"
else
  if echo "$out" | grep -q "STALE CHANGELOG"; then
    ok "--check-bump fails a heading-less changelog with STALE CHANGELOG"
  else
    fail "expected STALE CHANGELOG in output, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: compound failure — all three stale conditions report ----
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_edited >"$f/$CANONICAL"       # content moved, frontmatter did not
printf -- '# Changelog\n' >"$f/$CHANGELOG" # entry for the head version removed
# manifests untouched
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  fail "--check-bump should fail when every bump is missing, got success: $out"
else
  if echo "$out" | grep -q "STALE CONTRACT VERSION" &&
    echo "$out" | grep -q "STALE CHANGELOG" &&
    echo "$out" | grep -q "STALE VERSION"; then
    ok "--check-bump reports all three stale conditions before exiting"
  else
    fail "expected all three STALE messages in one run, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: schema-only change still requires the bumps --------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
printf '{"title":"standards concern file v1"}\n' >"$f/$SCHEMA"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
carrying_plugin "$f" review "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
printf '{"title":"standards concern file v1","description":"schema-only change"}\n' >"$f/$SCHEMA"
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  fail "--check-bump should fail on an unbumped schema-only change, got success: $out"
else
  if echo "$out" | grep -q "STALE CONTRACT VERSION"; then
    ok "--check-bump treats the schema as contract surface (schema-only change needs bumps)"
  else
    fail "expected STALE CONTRACT VERSION on schema-only change, got: $out"
  fi
fi
rm -rf "$f"

# --- --check-bump: plugin absent at base is new — skipped, not stale --------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1)" 0.1.0
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
carrying_plugin "$f" planning "$(canonical_v1_1)" 0.2.0
carrying_plugin "$f" review "$(canonical_v1_1)" 0.1.0 # new plugin, absent at base
if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
  ok "--check-bump skips a plugin that did not exist at the base ref"
else
  fail "--check-bump should skip a base-absent plugin, got: $out"
fi
rm -rf "$f"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
