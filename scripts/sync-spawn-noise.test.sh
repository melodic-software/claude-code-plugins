#!/usr/bin/env bash
# Unit tests for sync-spawn-noise.sh. Builds a tiny synthetic repo tree per
# scenario in a temp dir and invokes the script against it directly -- the
# script's own `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it operates on the fixture tree.
#
# The load-bearing case is "--check discriminates": a drift gate that reports
# clean whether or not the copies match is worse than no gate, because it
# reports success. Both arms run and the suite asserts they DIFFER.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/sync-spawn-noise.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

CANONICAL="plugins/claude-ops/lib/spawn_noise.py"
COPY="plugins/performance/lib/spawn_noise.py"

canonical_v1() {
  printf 'BIMODAL_SPREAD_RATIO = 3.0\nSLOW_SPAWN_FLOOR_MS = 500.0\n'
}
canonical_v2() {
  printf 'BIMODAL_SPREAD_RATIO = 3.0\nSLOW_SPAWN_FLOOR_MS = 500.0\n\ndef is_measurable(s):\n    return True\n'
}

# new_fixture -> fresh tree with the script and its shared engine copied in.
new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts/lib" \
    "$dir/plugins/claude-ops/lib" "$dir/plugins/claude-ops/.claude-plugin" \
    "$dir/plugins/performance/lib" "$dir/plugins/performance/.claude-plugin"
  cp "$SCRIPT" "$dir/scripts/sync-spawn-noise.sh"
  cp "$SELF_DIR/lib/sync-cluster.sh" "$dir/scripts/lib/sync-cluster.sh"
  chmod +x "$dir/scripts/sync-spawn-noise.sh"
  printf '%s' "$dir"
}

# manifest <fixture> <plugin> <version>
manifest() {
  printf '{"name":"%s","version":"%s"}\n' "$2" "$3" >"$1/plugins/$2/.claude-plugin/plugin.json"
}

# base_fixture -> canonical + a matching copy, both plugins at 0.1.0.
base_fixture() {
  local dir
  dir="$(new_fixture)"
  canonical_v1 >"$dir/$CANONICAL"
  canonical_v1 >"$dir/$COPY"
  manifest "$dir" claude-ops 0.1.0
  manifest "$dir" performance 0.1.0
  printf '%s' "$dir"
}

git_fixture() {
  local fixture="$1"
  # On refusal (e.g. TMPDIR inside the checkout) stop before add/commit can
  # resolve to the enclosing real repository.
  git_init_test_repo "$fixture" || return 1
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm base
  git -C "$fixture" rev-parse HEAD
}

run_mode() (
  local fixture="$1"
  shift
  cd "$fixture" && bash scripts/sync-spawn-noise.sh "$@"
)

# --- sync copies the canonical into the carrying plugin ---------------------
f="$(new_fixture)"
canonical_v1 >"$f/$CANONICAL"
printf 'BIMODAL_SPREAD_RATIO = 9.0\n' >"$f/$COPY"
manifest "$f" claude-ops 0.1.0
manifest "$f" performance 0.1.0
if out="$(run_mode "$f" 2>&1)" && cmp -s "$f/$CANONICAL" "$f/$COPY"; then
  ok "sync makes the carrying copy byte-identical to the canonical"
else
  fail "sync should copy the canonical into performance, got: $out"
fi
rm -rf "$f"

# --- --check DISCRIMINATES --------------------------------------------------
# discriminating-skip-required: a gate whose arms agree proves nothing.
# The threshold is the whole point of this cluster: claude-ops and performance
# disagreeing about what counts as an unmeasurable host is the failure it
# prevents. So drift a copy and assert the verdict FLIPS, rather than asserting
# only that each arm printed its own expected string.
f="$(base_fixture)"
if run_mode "$f" --check >/dev/null 2>&1; then
  clean_verdict=pass
else
  clean_verdict=fail
fi
printf 'BIMODAL_SPREAD_RATIO = 9.0\n' >"$f/$COPY"
if run_mode "$f" --check >/dev/null 2>&1; then
  drifted_verdict=pass
else
  drifted_verdict=fail
fi
if [[ "$clean_verdict" != "$drifted_verdict" ]]; then
  ok "--check discriminates: matching copies '$clean_verdict', drifted copies '$drifted_verdict'"
else
  fail "--check returned '$clean_verdict' for BOTH matching and drifted copies — it would report clean whether or not the threshold agrees"
fi
if [[ "$clean_verdict" == pass && "$drifted_verdict" == fail ]]; then
  ok "--check passes on a matching cluster and fails on a drifted one"
else
  fail "expected clean=pass drifted=fail, got clean=$clean_verdict drifted=$drifted_verdict"
fi
rm -rf "$f"

# --- a drift message names the file to fix ----------------------------------
f="$(base_fixture)"
printf 'BIMODAL_SPREAD_RATIO = 9.0\n' >"$f/$COPY"
out="$(run_mode "$f" --check 2>&1)" || true
if [[ "$out" == *"$COPY"* && "$out" == *"$CANONICAL"* ]]; then
  ok "the drift message names both the drifted copy and the canonical"
else
  fail "drift message should name both paths, got: $out"
fi
rm -rf "$f"

# --- --print-manifest publishes src and copies ------------------------------
f="$(base_fixture)"
out="$(run_mode "$f" --print-manifest 2>&1)"
if [[ "$out" == *"src"*"$CANONICAL"* && "$out" == *"copy"*"$COPY"* ]]; then
  ok "--print-manifest publishes src and copy, so affected-tests can derive the fan-out"
else
  fail "--print-manifest should publish src and copy, got: $out"
fi
rm -rf "$f"

# --- --check-bump requires a carrier version bump when canonical changed -----
f="$(base_fixture)"
if base="$(git_fixture "$f")"; then
  canonical_v2 >"$f/$CANONICAL"
  canonical_v2 >"$f/$COPY"
  if run_mode "$f" --check-bump "$base" >/dev/null 2>&1; then
    fail "--check-bump should fail when the canonical changed but no carrier version moved"
  else
    ok "--check-bump fails when the canonical changed but no carrier version moved"
  fi
  manifest "$f" performance 0.2.0
  manifest "$f" claude-ops 0.2.0
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
