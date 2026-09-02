#!/usr/bin/env bash
# Unit tests for sync-unwrap-before-compose.sh. Builds a tiny synthetic repo
# tree per scenario in a temp dir and invokes the script against it directly.
# The load-bearing case is "--check discriminates": a drift gate that reports
# clean whether or not the copies match is worse than no gate.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/sync-unwrap-before-compose.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

CANONICAL="plugins/context-guard/skills/setup/reference/unwrap-before-compose.md"
COPY="plugins/rate-limit-guard/skills/setup/reference/unwrap-before-compose.md"

canonical_v1() {
  printf '# Unwrap before you compose\n\nshared spoke v1\n'
}
canonical_v2() {
  printf '# Unwrap before you compose\n\nshared spoke v2\n'
}

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts/lib" \
    "$dir/plugins/context-guard/skills/setup/reference" \
    "$dir/plugins/context-guard/.claude-plugin" \
    "$dir/plugins/rate-limit-guard/skills/setup/reference" \
    "$dir/plugins/rate-limit-guard/.claude-plugin"
  cp "$SCRIPT" "$dir/scripts/sync-unwrap-before-compose.sh"
  cp "$SELF_DIR/lib/sync-cluster.sh" "$dir/scripts/lib/sync-cluster.sh"
  chmod +x "$dir/scripts/sync-unwrap-before-compose.sh"
  printf '%s' "$dir"
}

manifest() {
  printf '{"name":"%s","version":"%s"}\n' "$2" "$3" >"$1/plugins/$2/.claude-plugin/plugin.json"
}

base_fixture() {
  local dir
  dir="$(new_fixture)"
  canonical_v1 >"$dir/$CANONICAL"
  canonical_v1 >"$dir/$COPY"
  manifest "$dir" context-guard 0.1.0
  manifest "$dir" rate-limit-guard 0.1.0
  printf '%s' "$dir"
}

git_fixture() {
  local fixture="$1"
  git_init_test_repo "$fixture" || return 1
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm base
  git -C "$fixture" rev-parse HEAD
}

run_mode() (
  local fixture="$1"
  shift
  cd "$fixture" && bash scripts/sync-unwrap-before-compose.sh "$@"
)

f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
printf '# drifted\n' >"$f/$COPY"
manifest "$f" context-guard 0.1.0
manifest "$f" rate-limit-guard 0.1.0
if out="$(run_mode "$f" 2>&1)" && cmp -s "$f/$CANONICAL" "$f/$COPY"; then
  ok "sync makes the carrying copy byte-identical to the canonical"
else
  fail "sync should copy the canonical into rate-limit-guard, got: $out"
fi
rm -rf "$f"

f="$(base_fixture)"
if run_mode "$f" --check >/dev/null 2>&1; then
  clean_verdict=pass
else
  clean_verdict=fail
fi
printf '# drifted\n' >"$f/$COPY"
if run_mode "$f" --check >/dev/null 2>&1; then
  drifted_verdict=pass
else
  drifted_verdict=fail
fi
if [[ "$clean_verdict" != "$drifted_verdict" ]]; then
  ok "--check discriminates: matching copies '$clean_verdict', drifted copies '$drifted_verdict'"
else
  fail "--check returned '$clean_verdict' for BOTH matching and drifted copies"
fi
if [[ "$clean_verdict" == pass && "$drifted_verdict" == fail ]]; then
  ok "--check passes on a matching cluster and fails on a drifted one"
else
  fail "expected clean=pass drifted=fail, got clean=$clean_verdict drifted=$drifted_verdict"
fi
rm -rf "$f"

f="$(base_fixture)"
printf '# drifted\n' >"$f/$COPY"
out="$(run_mode "$f" --check 2>&1)" || true
if [[ "$out" == *"$COPY"* && "$out" == *"$CANONICAL"* ]]; then
  ok "the drift message names both the drifted copy and the canonical"
else
  fail "drift message should name both paths, got: $out"
fi
rm -rf "$f"

f="$(base_fixture)"
out="$(run_mode "$f" --print-manifest 2>&1)"
if [[ "$out" == *"src"*"$CANONICAL"* && "$out" == *"copy"*"$COPY"* ]]; then
  ok "--print-manifest publishes src and copy, so affected-tests can derive the fan-out"
else
  fail "--print-manifest should publish src and copy, got: $out"
fi
rm -rf "$f"

f="$(base_fixture)"
if base="$(git_fixture "$f")"; then
  canonical_v2 >"$f/$CANONICAL"
  canonical_v2 >"$f/$COPY"
  if run_mode "$f" --check-bump "$base" >/dev/null 2>&1; then
    fail "--check-bump should fail when the canonical changed but no carrier version moved"
  else
    ok "--check-bump fails when the canonical changed but no carrier version moved"
  fi
  manifest "$f" rate-limit-guard 0.2.0
  manifest "$f" context-guard 0.2.0
  if run_mode "$f" --check-bump "$base" >/dev/null 2>&1; then
    ok "--check-bump passes once the carrying plugins bumped"
  else
    fail "--check-bump should pass after both carriers bumped"
  fi
else
  fail "could not init a git fixture; --check-bump arms did not run"
fi
rm -rf "$f"

test_harness::report
