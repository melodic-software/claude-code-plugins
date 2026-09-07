#!/usr/bin/env bash
# Unit tests for sync-context-zone.sh. Builds a tiny synthetic repo tree per
# scenario in a temp dir and invokes the script against it directly. The
# load-bearing case is "--check discriminates": a drift gate that reports clean
# whether or not the copies match is worse than no gate.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/sync-context-zone.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

CANONICAL="plugins/context-guard/scripts/context-zone.sh"
COPY="plugins/plugin-quality/scripts/context-zone.sh"

canonical_v1() {
  printf '#!/usr/bin/env bash\n# smart <= 50 < acceptable <= 75 < dumb\n'
}
canonical_v2() {
  printf '#!/usr/bin/env bash\n# smart <= 40 < acceptable <= 70 < dumb\n'
}

new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts/lib" \
    "$dir/plugins/context-guard/scripts" \
    "$dir/plugins/context-guard/.claude-plugin" \
    "$dir/plugins/plugin-quality/scripts" \
    "$dir/plugins/plugin-quality/.claude-plugin"
  cp "$SCRIPT" "$dir/scripts/sync-context-zone.sh"
  cp "$SELF_DIR/lib/sync-cluster.sh" "$dir/scripts/lib/sync-cluster.sh"
  chmod +x "$dir/scripts/sync-context-zone.sh"
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
  manifest "$dir" plugin-quality 0.1.0
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
  cd "$fixture" && bash scripts/sync-context-zone.sh "$@"
)

f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
printf '# drifted\n' >"$f/$COPY"
manifest "$f" context-guard 0.1.0
manifest "$f" plugin-quality 0.1.0
if out="$(run_mode "$f" 2>&1)" && cmp -s "$f/$CANONICAL" "$f/$COPY"; then
  ok "sync makes the carrying copy byte-identical to the canonical"
else
  fail "sync should copy the canonical into plugin-quality, got: $out"
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
out="$(run_mode "$f" --bogus-flag 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"usage: sync-context-zone.sh"* ]]; then
  ok "an unknown flag exits 2 with a usage line naming this gate"
else
  fail "expected exit 2 and a usage line, got rc=$rc out: $out"
fi
rm -rf "$f"

f="$(base_fixture)"
if base="$(git_fixture "$f")"; then
  if out="$(run_mode "$f" --check-bump "$base" 2>&1)"; then
    ok "--check-bump passes when the canonical is unchanged vs the base ref"
  else
    fail "--check-bump should pass on an unchanged canonical, got: $out"
  fi
  canonical_v2 >"$f/$CANONICAL"
  canonical_v2 >"$f/$COPY"
  if run_mode "$f" --check-bump "$base" >/dev/null 2>&1; then
    fail "--check-bump should fail when the canonical changed but no carrier version moved"
  else
    ok "--check-bump fails when the canonical changed but no carrier version moved"
  fi
  manifest "$f" plugin-quality 0.2.0
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
