#!/usr/bin/env bash
# Tests for scan.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

SCAN="$SCRIPT_DIR/scan.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

# The fixture's git env is exported the way a hook chain would export it, so the
# scan must resolve the fixture repo and not the checkout this suite runs from.
run_scan() {
  GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && bash '$SCAN'"
}

rc=0
bash "$SCAN" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
mkdir -p "$TEST_TMPDIR/repo/.pytest_cache"
echo x >"$TEST_TMPDIR/repo/.pytest_cache/x"
git -C "$TEST_TMPDIR/repo" add .pytest_cache/x
git -C "$TEST_TMPDIR/repo" commit -m "tracked cache" >/dev/null
mkdir -p "$TEST_TMPDIR/repo/node_modules/pkg"
echo junk >"$TEST_TMPDIR/repo/node_modules/pkg/j"

out="$(run_scan)"
assert_not_contains "protected node_modules not inventoried" "$out" "node_modules"

git -C "$TEST_TMPDIR/repo" rm -r --cached .pytest_cache >/dev/null 2>&1
mkdir -p "$TEST_TMPDIR/repo/.ruff_cache"
echo y >"$TEST_TMPDIR/repo/.ruff_cache/y"

out="$(run_scan)"
assert_contains "finds untracked cache" "$out" ".ruff_cache"
assert_contains "emits category" "$out" "Category:"
assert_contains "emits total" "$out" "Total reclaimable:"

# Single pruned-walk engine: a build dir NESTED inside a pruned tree
# (node_modules) is never descended into, while a top-level build dir still
# enumerates. This proves the walk prunes rather than merely filters output.
mkdir -p "$TEST_TMPDIR/repo/node_modules/pkg/bin"
echo z >"$TEST_TMPDIR/repo/node_modules/pkg/bin/z"
mkdir -p "$TEST_TMPDIR/repo/src/bin"
echo z >"$TEST_TMPDIR/repo/src/bin/z"
out="$(run_scan)"
assert_contains "top-level build dir inventoried" "$out" "src/bin"
assert_not_contains "build dir under pruned node_modules skipped" "$out" "node_modules/pkg/bin"

# An unreachable SSH origin must not start ssh, askpass, or a credential helper.
# The recorders sit on GIT_SSH_COMMAND and on a test-only global config (system
# config hidden) so a host sshCommand or credential helper cannot run instead.
OFF="$TEST_TMPDIR/offline"
git init -q -b main "$OFF"
git -C "$OFF" config user.email "t@example.com"
git -C "$OFF" config user.name "Test"
git -C "$OFF" config commit.gpgsign false
echo a >"$OFF/a"
git -C "$OFF" add a
git -C "$OFF" commit -qm init
git -C "$OFF" remote add origin git@unknown-host.invalid:owner/repo.git
REC="$TEST_TMPDIR/scan-record"
mkdir -p "$REC"
cat >"$REC/ssh" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$REC/ssh.log"
exit 1
EOF
cat >"$REC/askpass" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$REC/askpass.log"
exit 1
EOF
cat >"$REC/cred" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$REC/cred.log"
cat >/dev/null
exit 1
EOF
chmod +x "$REC/ssh" "$REC/askpass" "$REC/cred"
git config --file "$REC/gitconfig" core.sshCommand "$REC/ssh"
git config --file "$REC/gitconfig" credential.helper ""
git config --file "$REC/gitconfig" --add credential.helper "!$REC/cred"
rc=0
out="$(
  GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL="$REC/gitconfig" \
    GIT_SSH_COMMAND="$REC/ssh" \
    GIT_ASKPASS="$REC/askpass" \
    SSH_ASKPASS="$REC/askpass" \
    bash -c "cd '$OFF' && bash '$SCAN'"
)" || rc=$?
assert_exit "unreachable origin scan exits 0" 0 "$rc"
assert_contains "stale-refs line does not contact the remote" "$out" "Git stale refs dry-run: remote prune not measured"
assert_file_absent "scan starts no ssh" "$REC/ssh.log"
assert_file_absent "scan starts no askpass" "$REC/askpass.log"
assert_file_absent "scan starts no credential helper" "$REC/cred.log"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: scan.sh tests passed"
