#!/usr/bin/env bash
# Tests for git-tree-reset.sh — default-preserve semantics, reparse-point
# data-loss guard, opt-in flags, unpushed-commit + default-branch blocks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

RESET="$SCRIPT_DIR/git-tree-reset.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0
R="$TEST_TMPDIR/repo"

git init "$R" >/dev/null 2>&1
git -C "$R" config user.email "t@example.com"
git -C "$R" config user.name "Test"
echo tracked >"$R/tracked.txt"
mkdir -p "$R/shared"
echo keep >"$R/shared/keep.txt"
git -C "$R" add -A
git -C "$R" commit -m "init" >/dev/null
git -C "$R" branch -M main
git -C "$R" checkout -b feat/test >/dev/null 2>&1
git -C "$R" branch -u main >/dev/null 2>&1

run_reset() { bash -c "cd '$R' && bash '$RESET' $*"; }

# Create a reparse point at $1 pointing to dir $2 (junction on Windows, symlink
# on Unix). Echoes kind, or nothing when no primitive is available.
make_reparse() {
  local link="$1" target="$2"
  if command -v cygpath >/dev/null 2>&1 &&
    cmd //c "mklink /J \"$(cygpath -w "$link")\" \"$(cygpath -w "$target")\"" >/dev/null 2>&1; then
    echo junction
  elif ln -s "$target" "$link" 2>/dev/null; then
    echo symlink
  fi
}

# --- 1. --help ---
rc=0
bash "$RESET" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# --- 2. dry-run surfaces new labels ---
out="$(run_reset 2>&1)" || true
assert_contains "dry-run lists upstream" "$out" "Upstream:"
assert_contains "dry-run plans clean" "$out" "PlannedClean: git clean -fdx"
assert_contains "dry-run preserves secrets by default" "$out" "PreserveSecrets: yes"
assert_contains "dry-run preserves deps by default" "$out" "PreserveDeps: yes"

# --- 3. default apply preserves secrets + deps, removes plain untracked ---
echo ignored >"$R/.env"
echo direnv >"$R/.envrc"
mkdir -p "$R/node_modules"
echo dep >"$R/node_modules/x.js"
echo untracked >"$R/scratch.txt"
echo dirty >>"$R/tracked.txt"
out="$(run_reset --apply 2>&1)" || true
assert_contains "apply reports reset" "$out" "AppliedReset:"
assert_contains "apply reports restored count" "$out" "RestoredTracked:"
assert_file_exists "default preserves .env" "$R/.env"
assert_file_exists "default preserves .envrc" "$R/.envrc"
assert_file_exists "default preserves node_modules" "$R/node_modules/x.js"
assert_file_absent "default removes plain untracked" "$R/scratch.txt"

# --- 4. reparse point into tracked dir, default preserve (node_modules not traversed) ---
rm -rf "$R/pkg"
mkdir -p "$R/pkg/node_modules"
kind="$(make_reparse "$R/pkg/node_modules/link" "$R/shared")"
if [[ -z "$kind" ]]; then
  skip_case "no reparse-point primitive (mklink/ln -s unavailable)"
else
  out="$(run_reset --apply 2>&1)" || true
  assert_file_exists "tracked file survives reparse traversal (default)" "$R/shared/keep.txt"
  assert_contains "restore guard reports zero on default path" "$out" "RestoredTracked: 0"

  # --- 5. --include-deps traverses node_modules; restore guard recovers ---
  rm -rf "$R/pkg"
  mkdir -p "$R/pkg/node_modules"
  make_reparse "$R/pkg/node_modules/link" "$R/shared" >/dev/null
  run_reset --apply --include-deps >/dev/null 2>&1 || true
  assert_file_exists "tracked file survives --include-deps (guard recovers)" "$R/shared/keep.txt"
  assert_file_absent "include-deps removes node_modules" "$R/node_modules/x.js"
fi

# --- 6. --include-secrets removes .env ---
echo ignored >"$R/.env"
run_reset --apply --include-secrets >/dev/null 2>&1 || true
assert_file_absent "include-secrets removes .env" "$R/.env"

# --- 7. unpushed commit blocks apply (exit 4) unless --allow-unpushed ---
echo ahead >"$R/ahead.txt"
git -C "$R" add ahead.txt
git -C "$R" commit -m "ahead" >/dev/null
rc=0
out="$(run_reset --apply 2>&1)" || rc=$?
assert_exit "unpushed commit blocks apply" 4 "$rc"
assert_contains "unpushed block reason" "$out" "unpushed-commits"
rc=0
run_reset --apply --allow-unpushed >/dev/null 2>&1 || rc=$?
assert_exit "allow-unpushed proceeds" 0 "$rc"

# --- 8. default branch blocked (exit 3) ---
git -C "$R" checkout main >/dev/null 2>&1
git -C "$R" config branch.main.remote .
git -C "$R" config branch.main.merge refs/heads/main
rc=0
out="$(run_reset 2>&1)" || rc=$?
assert_exit "blocks default branch" 3 "$rc"
assert_contains "blocked reason" "$out" "default-branch"

# --- 9. reset --hard failure aborts before clean (no partial destructive op) ---
# Force git reset --hard to fail via a PATH shim that intercepts only `reset`
# and delegates every other subcommand to the real git. A failed reset must not
# fall through to git clean -fdx, so an untracked file clean would have removed
# must survive, and no AppliedClean success line may be emitted.
REAL_GIT="$(command -v git)"
R2="$TEST_TMPDIR/repo-reset-fail"
git init "$R2" >/dev/null 2>&1
git -C "$R2" config user.email "t@example.com"
git -C "$R2" config user.name "Test"
echo tracked >"$R2/tracked.txt"
git -C "$R2" add -A
git -C "$R2" commit -m "init" >/dev/null
git -C "$R2" branch -M main
git -C "$R2" checkout -b feat/reset-fail >/dev/null 2>&1
git -C "$R2" branch -u main >/dev/null 2>&1
echo untracked >"$R2/scratch.txt"

SHIM="$TEST_TMPDIR/git-shim"
mkdir -p "$SHIM"
cat >"$SHIM/git" <<SHIMEOF
#!/usr/bin/env bash
if [[ "\$1" == "reset" ]]; then
  echo "fatal: simulated reset --hard failure" >&2
  exit 1
fi
exec "$REAL_GIT" "\$@"
SHIMEOF
chmod +x "$SHIM/git"

rc=0
out="$(PATH="$SHIM:$PATH" bash -c "cd '$R2' && bash '$RESET' --apply" 2>&1)" || rc=$?
assert_exit "reset failure exits 5" 5 "$rc"
assert_contains "reset failure reports failure" "$out" "FAILED: git reset --hard"
assert_not_contains "reset failure emits no clean success line" "$out" "AppliedClean: git clean"
assert_file_exists "reset failure skips clean (untracked survives)" "$R2/scratch.txt"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-tree-reset.sh tests passed"
