#!/usr/bin/env bash
# Regression tests for scripts/test-git-helpers.sh — specifically the fixture
# ISOLATION property (#2840), which is the one property of that harness a
# reviewer cannot check by reading it.
#
# WHAT IS BEING PROVEN. `git -C <fixture>` is a readability guard, not an
# isolation guarantee. `-C` does chdir; what an exported ABSOLUTE GIT_DIR
# overrides is repository DISCOVERY, and `git config` writes its default
# --local scope to whatever `--git-dir` finally resolves to. So under an
# exported absolute GIT_DIR, `git -C <fixture> config user.email X` writes the
# CALLER's config and leaves the fixture with no `.git` at all — and the
# caller's next commit is authored as the fixture identity. (The RELATIVE form
# `GIT_DIR=.git` is safe: `-C` chdirs first and `.git` then resolves against
# the new cwd. The absolute form is the footgun, not the mere presence of
# GIT_DIR.)
#
# A poisoned user.email silently re-authors commits. Such a commit fails this
# repo's required_signatures rule with `no_user` and CANNOT be force-pushed
# over — the branch has to be abandoned and the tree rebuilt. That is what
# happened to #2827 -> #2830.
#
# FOUR SCENARIOS, all live in this repo:
#   A  plain caller repo, absolute GIT_DIR exported
#   B  GIT_DIR pointing at a LINKED WORKTREE's gitdir — a config write there
#      lands in the MAIN clone's SHARED .git/config, because git creates no
#      config.worktree of its own. This repo runs dozens of linked worktrees.
#   C  fixture target NESTED inside the caller repo — repository discovery
#      walks upward out of a non-repo directory.
#   D  exported GIT_CONFIG — not a discovery variable at all. It replaces the
#      file the `git config` subcommand reads and writes, so the identity write
#      follows it past `-C`, past a cleared GIT_DIR, and past the cwd.
#
# EVERY assertion reads the caller's identity with `config --local --get`. A
# plain `--get` falls through to ~/.gitconfig and returns rc=0, which would
# mask the very leak these tests measure — the read/write asymmetry that makes
# this bug quiet in the first place.
#
# Each scenario exports GIT_DIR inside its OWN subshell, so the harness can
# never poison the shell that runs it.
#
# fixture-isolation-scope: this suite is the counter-fixture for
# scripts/check-fixture-git-isolation.sh — it must EXPORT GIT_DIR to prove the
# harness survives it, so it cannot itself clear the environment the gate
# normally requires. Every export is subshell-local (see above).
#
# TEST_GIT_HELPERS_UNDER_TEST overrides which harness copy is exercised. It
# exists so the fail/pass discrimination of these tests can be re-run against a
# pre-fix copy without editing a tracked file; it defaults to the shipped
# harness, which is what CI exercises.
#
# SC2030/SC2031 ("modification of GIT_DIR is local to the subshell", "might be
# lost") describe exactly the property being relied on, not a defect: each
# export MUST stay inside its own subshell so this suite cannot poison the
# shell that runs it. Losing the value on the way out is the safety guarantee.
# shellcheck disable=SC2030,SC2031
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${TEST_GIT_HELPERS_UNDER_TEST:-$SELF_DIR/test-git-helpers.sh}"

if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: harness under test not found: $HELPER" >&2
  exit 1
fi

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

SENTINEL="sentinel@example.invalid"

# A throwaway caller repo carrying a known LOCAL identity — the thing a leak
# would overwrite.
new_caller() {
  local d
  d="$(mktemp -d)"
  git -c init.defaultBranch=main init -q "$d"
  git -C "$d" config --local user.email "$SENTINEL"
  git -C "$d" config --local user.name sentinel
  printf '%s' "$d"
}

caller_email() {
  git -C "$1" config --local --get user.email 2>/dev/null || printf '<unset>'
}

# assert_isolated <label> <caller-dir> <fixture-dir> <email-before>
# The two halves are asserted separately on purpose: an unchanged caller alone
# does not prove isolation, because the fixture can still have been skipped
# entirely. A real leak shows BOTH — caller rewritten AND fixture left with no
# .git — so both are checked.
assert_isolated() {
  local label="$1" caller="$2" fixture="$3" before="$4"
  local after
  after="$(caller_email "$caller")"
  if [[ "$after" == "$SENTINEL" ]]; then
    ok "$label: caller identity intact ($after)"
  else
    fail "$label: caller identity POISONED (before=$before after=$after)"
  fi
  if [[ -e "$fixture/.git" ]]; then
    ok "$label: fixture owns its own .git"
  else
    fail "$label: fixture has NO .git — the work went to the caller instead"
  fi
}

# ---------------------------------------------------------------- scenario A
scenario_a() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$(mktemp -d)/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d)" || exit 1
    export GIT_DIR="$caller/.git"
    export GIT_WORK_TREE="$caller"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_init_test_repo "$fixture"
  ) >/dev/null 2>&1
  assert_isolated "A absolute GIT_DIR" "$caller" "$fixture" "$before"
}

# ---------------------------------------------------------------- scenario B
scenario_b() {
  local caller wt lgd fixture before
  caller="$(new_caller)"
  git -C "$caller" -c user.email="$SENTINEL" -c user.name=sentinel \
    -c commit.gpgsign=false commit -q --allow-empty -m seed
  wt="$(mktemp -d)/lw"
  if ! git -C "$caller" worktree add -q -b lw "$wt" >/dev/null 2>&1; then
    fail "B linked worktree: could not create the linked worktree fixture"
    return
  fi
  # A linked worktree's `.git` is a FILE pointing at the real gitdir; resolve
  # it rather than assuming a layout.
  lgd="$(git -C "$wt" rev-parse --absolute-git-dir)"
  fixture="$(mktemp -d)/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d)" || exit 1
    export GIT_DIR="$lgd"
    export GIT_WORK_TREE="$wt"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_init_test_repo "$fixture"
  ) >/dev/null 2>&1
  assert_isolated "B linked worktree" "$caller" "$fixture" "$before"
  git -C "$caller" worktree remove --force "$wt" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- scenario C
scenario_c() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$caller/nested/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d)" || exit 1
    export GIT_DIR="$caller/.git"
    export GIT_WORK_TREE="$caller"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    # git_init_safe refuses a path inside the CURRENT repository, which it
    # resolves from the cwd; with the cwd outside any repo it sees none, so
    # this exercises the raw init+config path a suite would take.
    git_test_config "$fixture" init -q
    git_test_config "$fixture" config user.email nested@example.invalid
  ) >/dev/null 2>&1
  assert_isolated "C nested non-repo dir" "$caller" "$fixture" "$before"
}

# ---------------------------------------------------------------- scenario D
# GIT_CONFIG is a SECOND leak path, not another spelling of the first. It does
# not redirect discovery at all: it replaces the file the `git config`
# subcommand itself reads and writes, so `git -C <fixture> config user.email X`
# lands in whatever file it names even when GIT_DIR is unset, the cwd is
# elsewhere, and `-C` points squarely at the fixture. Clearing the six
# discovery variables therefore does not close it, which is why the harness
# clears GIT_CONFIG too. Verified against the unpatched harness: this scenario
# rewrites the caller's identity and the six-variable clear does not stop it.
scenario_d() {
  local caller fixture before
  caller="$(new_caller)"
  fixture="$(mktemp -d)/fx"
  mkdir -p "$fixture"
  before="$(caller_email "$caller")"
  (
    cd "$(mktemp -d)" || exit 1
    export GIT_CONFIG="$caller/.git/config"
    # shellcheck source=test-git-helpers.sh
    . "$HELPER"
    git_test_config "$fixture" init -q
    git_test_config "$fixture" config user.email gitconfig@example.invalid
  ) >/dev/null 2>&1
  assert_isolated "D exported GIT_CONFIG" "$caller" "$fixture" "$before"
}

# The harness must clear every variable that can redirect a fixture write, not
# just the two the reproduction happens to use — GIT_INDEX_FILE and
# GIT_OBJECT_DIRECTORY redirect writes the same way, and GIT_CONFIG redirects
# the `git config` subcommand outright.
scenario_declares_full_env_clear() {
  local v missing=()
  for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG; do
    grep -Eq "^[[:space:]]*unset([[:space:]]+[A-Z_]+)*[[:space:]]+$v([[:space:]]|$)" "$HELPER" ||
      missing+=("$v")
  done
  if ((${#missing[@]} == 0)); then
    ok "harness clears every discovery-redirecting variable"
  else
    fail "harness does not clear: ${missing[*]}"
  fi
}

echo "harness under test: $HELPER"
scenario_a
scenario_b
scenario_c
scenario_d
scenario_declares_full_env_clear

test_harness::report
