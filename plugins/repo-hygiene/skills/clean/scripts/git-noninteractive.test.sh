#!/usr/bin/env bash
# Networked git stays non-interactive and keeps the configured ssh command.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

PRUNE="$SCRIPT_DIR/git-prune.sh"
RESET="$SCRIPT_DIR/git-tree-reset.sh"
AUDIT="$SCRIPT_DIR/git-branch-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

# run_bounded <seconds> <command...> — stdout+stderr of the command.
# Exit 124 when it is still running after <seconds> (the command is killed).
run_bounded() {
  local seconds="$1"
  shift
  local outfile pid ticks=0 limit status
  outfile="$TEST_TMPDIR/bounded-out"
  : >"$outfile"
  set -m
  "$@" >"$outfile" 2>&1 &
  pid=$!
  set +m
  limit=$((seconds * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if ((ticks >= limit)); then
      kill -TERM -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$outfile"
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
  status=$?
  cat "$outfile"
  return "$status"
}

init_repo() {
  local dir="$1"
  git init -q -b main "$dir"
  git -C "$dir" config user.email "t@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  echo a >"$dir/a"
  git -C "$dir" add a
  git -C "$dir" commit -qm init
}

# Shim stands in for core.sshCommand. It records its arguments and, when those
# arguments omit BatchMode=yes, sleeps: a helper that drops the configured
# command or forgets BatchMode fails the bounded run.
SSH_LOG="$TEST_TMPDIR/ssh.log"
mkdir -p "$TEST_TMPDIR/shim"
SSH_SHIM="$TEST_TMPDIR/shim/ssh"
cat >"$SSH_SHIM" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$SSH_LOG"
case " \$* " in
*" BatchMode=yes "*) exit 1 ;;
esac
sleep 60
exit 1
EOF
chmod +x "$SSH_SHIM"
CFG="$TEST_TMPDIR/gitconfig"
git config --file "$CFG" core.sshCommand "$SSH_SHIM"
got="$(GIT_CONFIG_GLOBAL="$CFG" git config --get core.sshCommand || true)"
assert_contains "test config publishes the shim as core.sshCommand" "$got" "$SSH_SHIM"

run_shimmed() {
  rm -f "$SSH_LOG"
  run_bounded 15 env -u GIT_SSH_COMMAND GIT_CONFIG_GLOBAL="$CFG" "$@"
}

# --- file:// remotes are contacted and do not invoke ssh ---
BARE="$TEST_TMPDIR/origin.git"
WORK="$TEST_TMPDIR/prune-work"
git init -q --bare "$BARE"
init_repo "$WORK"
git -C "$WORK" remote add origin "file://$BARE"
git -C "$WORK" push -q origin main
git -C "$WORK" update-ref refs/remotes/origin/gone HEAD
rc=0
out="$(run_shimmed bash -c "cd '$WORK' && bash '$PRUNE' --apply")" || rc=$?
assert_exit "file:// prune finishes" 0 "$rc"
assert_not_contains "file:// prune is reachable" "$out" "remote unreachable"
assert_file_absent "file:// prune starts no ssh" "$SSH_LOG"
if git -C "$WORK" rev-parse --verify --quiet refs/remotes/origin/gone >/dev/null; then
  fail "file:// prune removes the stale tracking ref" "absent" "present"
else
  pass "file:// prune removes the stale tracking ref"
fi

SEED="$TEST_TMPDIR/seed"
BARE2="$TEST_TMPDIR/reset-origin.git"
WORK2="$TEST_TMPDIR/reset-work"
git init -q --bare "$BARE2"
init_repo "$SEED"
git -C "$SEED" remote add origin "file://$BARE2"
git -C "$SEED" push -q origin main
git -C "$BARE2" symbolic-ref HEAD refs/heads/main
git clone -q -b main "file://$BARE2" "$WORK2"
git -C "$WORK2" config user.email "t@example.com"
git -C "$WORK2" config user.name "Test"
git -C "$WORK2" config commit.gpgsign false
git -C "$WORK2" checkout -q -b feat
git -C "$WORK2" branch -u origin/main >/dev/null
echo more >>"$SEED/a"
git -C "$SEED" add a
git -C "$SEED" commit -qm more
git -C "$SEED" push -q origin main
NEW="$(git -C "$SEED" rev-parse HEAD)"
echo dirty >"$WORK2/dirty.txt"
rc=0
out="$(run_shimmed bash -c "cd '$WORK2' && bash '$RESET' --apply")" || rc=$?
assert_exit "file:// tree reset finishes" 0 "$rc"
assert_not_contains "file:// fetch is reachable" "$out" "remote unreachable"
assert_contains "file:// tree reset applies" "$out" "AppliedReset: git reset --hard"
assert_file_absent "file:// fetch starts no ssh" "$SSH_LOG"
assert_file_absent "file:// tree reset cleans the untracked file" "$WORK2/dirty.txt"
if [[ "$(git -C "$WORK2" rev-parse HEAD)" == "$NEW" ]]; then
  pass "file:// fetch moved HEAD to the remote tip"
else
  fail "file:// fetch moved HEAD to the remote tip" "$NEW" "$(git -C "$WORK2" rev-parse HEAD)"
fi

# --- unreachable ssh: the configured command runs, with BatchMode, and returns ---
make_unreachable() {
  local dir="$1" track="${2:-}"
  init_repo "$dir"
  git -C "$dir" remote add origin git@unknown-host.invalid:owner/repo.git
  git -C "$dir" update-ref refs/remotes/origin/main HEAD
  git -C "$dir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  if [[ -n "$track" ]]; then
    git -C "$dir" checkout -q -b feat
    git -C "$dir" branch -u origin/main >/dev/null
  fi
}

assert_shim_ran() {
  local label="$1" log=""
  [[ -f "$SSH_LOG" ]] && log="$(cat "$SSH_LOG")"
  assert_contains "$label: configured core.sshCommand ran" "$log" "$SSH_SHIM"
  assert_contains "$label: BatchMode=yes is in the ssh arguments" "$log" "BatchMode=yes"
  assert_contains "$label: ConnectTimeout=5 is in the ssh arguments" "$log" "ConnectTimeout=5"
  assert_contains "$label: the unreachable host is the target" "$log" "unknown-host.invalid"
}

UNREACH_AUDIT="$TEST_TMPDIR/unreach-audit"
make_unreachable "$UNREACH_AUDIT"
rc=0
out="$(run_shimmed bash -c "cd '$UNREACH_AUDIT' && bash '$AUDIT' --remote")" || rc=$?
assert_exit "unreachable ssh audit finishes (no hang)" 0 "$rc"
assert_contains "unreachable ssh audit reports remote unreachable" "$out" "RemoteError: git ls-remote --heads origin failed (remote unreachable)"
assert_shim_ran "unreachable ssh audit"

UNREACH_PRUNE="$TEST_TMPDIR/unreach-prune"
make_unreachable "$UNREACH_PRUNE"
rc=0
out="$(run_shimmed bash -c "cd '$UNREACH_PRUNE' && bash '$PRUNE' --apply")" || rc=$?
assert_exit "unreachable ssh prune finishes (no hang)" 0 "$rc"
assert_contains "unreachable ssh prune reports remote unreachable" "$out" "RemoteUnreachable: remote unreachable (git remote prune origin)"
assert_contains "unreachable ssh prune still runs local gc" "$out" "Running: git gc --auto --quiet"
assert_shim_ran "unreachable ssh prune"

UNREACH_RESET="$TEST_TMPDIR/unreach-reset"
make_unreachable "$UNREACH_RESET" track
rc=0
out="$(run_shimmed bash -c "cd '$UNREACH_RESET' && bash '$RESET' --apply")" || rc=$?
assert_exit "unreachable ssh tree reset finishes (no hang)" 0 "$rc"
assert_contains "unreachable ssh tree reset reports remote unreachable" "$out" "RemoteUnreachable: remote unreachable (git fetch origin)"
assert_contains "unreachable ssh tree reset still resets" "$out" "AppliedReset: git reset --hard"
assert_shim_ran "unreachable ssh tree reset"

# --- ssh variants: git's own resolution decides which options the command takes ---
# make_recorder <path> <openssh|plain> — records each call ("$0 $*") as one line
# of <path>.log. openssh: -G succeeds, and the first BatchMode value wins, as in
# ssh_config(5); a value other than yes waits the way a prompt would. plain: any
# -o is rejected (exit 2), as Plink and a simple wrapper reject it.
make_recorder() {
  local path="$1" kind="$2"
  mkdir -p "$(dirname "$path")"
  if [[ "$kind" == openssh ]]; then
    cat >"$path" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$path.log"
batch=""
prev=""
for a in "\$@"; do
  [ "\$a" = -G ] && exit 0
  if [ "\$prev" = -o ] && [ -z "\$batch" ]; then
    case "\$a" in BatchMode=*) batch="\${a#BatchMode=}" ;; esac
  fi
  prev="\$a"
done
[ "\$batch" = yes ] && exit 1
sleep 60
exit 1
EOF
  else
    cat >"$path" <<EOF
#!/bin/sh
printf '%s\n' "\$0 \$*" >> "$path.log"
for a in "\$@"; do
  [ "\$a" = -o ] && exit 2
done
exit 1
EOF
  fi
  chmod +x "$path"
}

LIB="$SCRIPT_DIR/lib/git-noninteractive.sh"
VAR_REPO="$TEST_TMPDIR/variant-repo"
make_unreachable "$VAR_REPO"
VAR_DIR="$TEST_TMPDIR/variants dir"

# run_variant <gitconfig> [VAR=value...] — the helper's ls-remote on VAR_REPO,
# with only the given ssh settings in effect.
run_variant() {
  local cfg="$1"
  shift
  [[ -f "$cfg" ]] || : >"$cfg"
  # shellcheck disable=SC2016 # the inner bash expands its own positional parameters
  run_bounded 15 env -u GIT_SSH_COMMAND -u GIT_SSH -u GIT_SSH_VARIANT \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$cfg" "$@" \
    bash -c 'source "$1" && clean_git_noninteractive -C "$2" ls-remote --heads origin' _ "$LIB" "$VAR_REPO"
}

assert_not_exit() {
  local label="$1" unwanted="$2" actual="$3"
  if [[ "$actual" == "$unwanted" ]]; then
    fail "$label" "exit other than $unwanted" "$actual"
  else
    pass "$label"
  fi
}

log_of() {
  [[ -f "$1.log" ]] && cat "$1.log"
  return 0
}

# Configured OpenSSH options come after the enforced ones, so they cannot win.
OSSH="$VAR_DIR/openssh/ssh"
make_recorder "$OSSH" openssh
git config --file "$VAR_DIR/first.cfg" core.sshCommand "'$OSSH' -o BatchMode=no -o ConnectTimeout=30"
rc=0
run_variant "$VAR_DIR/first.cfg" >/dev/null || rc=$?
log="$(log_of "$OSSH")"
assert_not_exit "configured BatchMode=no does not reach a prompt" 124 "$rc"
assert_contains "enforced options precede the configured ones" "$log" "-o BatchMode=yes -o ConnectTimeout=5 -o BatchMode=no -o ConnectTimeout=30"

# plink (by basename, or GIT_SSH naming plink.exe): -batch, never -o.
PLINK="$VAR_DIR/plink/plink"
make_recorder "$PLINK" plain
git config --file "$VAR_DIR/plink.cfg" core.sshCommand "'$PLINK'"
rc=0
run_variant "$VAR_DIR/plink.cfg" >/dev/null || rc=$?
log="$(log_of "$PLINK")"
assert_contains "plink core.sshCommand runs" "$log" "$PLINK"
assert_contains "plink gets -batch" "$log" " -batch "
assert_not_contains "plink gets no OpenSSH option" "$log" " -o "

PLINK_EXE="$VAR_DIR/putty/plink.exe"
make_recorder "$PLINK_EXE" plain
rc=0
run_variant "$VAR_DIR/none.cfg" GIT_SSH="$PLINK_EXE" >/dev/null || rc=$?
log="$(log_of "$PLINK_EXE")"
assert_contains "GIT_SSH plink.exe still runs" "$log" "$PLINK_EXE"
assert_contains "GIT_SSH plink.exe gets -batch" "$log" " -batch "
assert_not_contains "GIT_SSH plink.exe gets no OpenSSH option" "$log" " -o "

# tortoiseplink: git passes -batch itself; nothing is added.
TPLINK="$VAR_DIR/tortoise/TortoisePlink.exe"
make_recorder "$TPLINK" plain
git config --file "$VAR_DIR/tortoise.cfg" core.sshCommand "'$TPLINK'"
rc=0
run_variant "$VAR_DIR/tortoise.cfg" >/dev/null || rc=$?
log="$(log_of "$TPLINK")"
assert_contains "tortoiseplink runs with git's -batch" "$log" " -batch "
assert_not_contains "tortoiseplink gets no OpenSSH option" "$log" " -o "

# simple, from ssh.variant or GIT_SSH_VARIANT: nothing is added, even to an ssh basename.
WRAP="$VAR_DIR/wrap/ssh-wrap"
make_recorder "$WRAP" plain
git config --file "$VAR_DIR/simple.cfg" core.sshCommand "'$WRAP'"
git config --file "$VAR_DIR/simple.cfg" ssh.variant simple
rc=0
run_variant "$VAR_DIR/simple.cfg" >/dev/null || rc=$?
log="$(log_of "$WRAP")"
assert_contains "ssh.variant=simple wrapper runs" "$log" "$WRAP"
assert_not_contains "ssh.variant=simple wrapper gets no OpenSSH option" "$log" " -o "

PLAIN_SSH="$VAR_DIR/plain/ssh"
make_recorder "$PLAIN_SSH" plain
git config --file "$VAR_DIR/plain-ssh.cfg" core.sshCommand "'$PLAIN_SSH'"
rc=0
run_variant "$VAR_DIR/plain-ssh.cfg" GIT_SSH_VARIANT=simple >/dev/null || rc=$?
log="$(log_of "$PLAIN_SSH")"
assert_contains "GIT_SSH_VARIANT=simple command runs" "$log" "$PLAIN_SSH"
assert_not_contains "GIT_SSH_VARIANT=simple command gets no OpenSSH option" "$log" " -o "

# An unrecognized basename gets OpenSSH options only when it passes git's -G probe with them.
AUTO_NO="$VAR_DIR/auto-no/my-transport"
make_recorder "$AUTO_NO" plain
git config --file "$VAR_DIR/auto-no.cfg" core.sshCommand "'$AUTO_NO'"
rc=0
run_variant "$VAR_DIR/auto-no.cfg" >/dev/null || rc=$?
log="$(log_of "$AUTO_NO" | grep 'git-upload-pack' || true)"
assert_contains "auto non-OpenSSH wrapper connects" "$log" "$AUTO_NO"
assert_not_contains "auto non-OpenSSH wrapper connects without BatchMode" "$log" "BatchMode"

AUTO_YES="$VAR_DIR/auto-yes/my-ssh-wrapper"
make_recorder "$AUTO_YES" openssh
git config --file "$VAR_DIR/auto-yes.cfg" core.sshCommand "'$AUTO_YES' -o BatchMode=no"
rc=0
run_variant "$VAR_DIR/auto-yes.cfg" >/dev/null || rc=$?
log="$(log_of "$AUTO_YES")"
assert_not_exit "auto OpenSSH wrapper does not reach a prompt" 124 "$rc"
assert_contains "auto OpenSSH wrapper gets the enforced options first" "$log" "-o BatchMode=yes -o ConnectTimeout=5 -o BatchMode=no"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git noninteractive tests passed"
