#!/usr/bin/env bash
# Tests for scripts/run-test-file.sh in a throwaway checkout: the test's git
# config and the signals the runner forwards to the test it starts.
# The fixture suites hold shell source as literal data on purpose.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
c="$TMP_ROOT/checkout"
mkdir -p "$c/scripts/lib" "$c/tests"
cp "$SELF_DIR/run-test-file.sh" "$c/scripts/"
cp "$SELF_DIR/lib/checkout-path.sh" "$SELF_DIR/lib/pytest-python.sh" "$SELF_DIR/lib/test-git-env.sh" "$c/scripts/lib/"

# A host global config that signs every commit through a failing program.
hostile="$TMP_ROOT/hostile.gitconfig"
printf '[user]\n\tname = host\n\temail = host@example.invalid\n[commit]\n\tgpgsign = true\n[gpg]\n\tprogram = /bin/false\n' >"$hostile"
printf '%s\n' 'd=$(mktemp -d) && trap "rm -rf \"$d\"" EXIT && git init -q "$d" && git -C "$d" commit -q --allow-empty -m x && git -C "$d" log -1 --format=%ae' \
  >"$c/tests/commit.test.sh"
out=$(cd "$c" && GIT_CONFIG_GLOBAL="$hostile" bash scripts/run-test-file.sh tests/commit.test.sh 2>&1)
rc=$?
if ((rc == 0)) && [[ $out == t@t.test ]]; then
  ok "a fixture commit succeeds under a signing host config, as the test identity"
else
  fail "fixture commit under a signing host config: rc=$rc output: $out"
fi

# `timeout --foreground` signals only its direct child, the runner (without it,
# timeout signals its whole process group), so the runner must forward the
# signal to the test it started rather than leave it running.
printf '%s\n' 'echo $$ >"$(dirname "$0")/sleep.pid"' 'exec sleep 30' >"$c/tests/sleep.test.sh"
for sig in TERM INT HUP; do
  rm -f "$c/tests/sleep.pid"
  start=$SECONDS
  (cd "$c" && timeout --foreground --preserve-status -s "$sig" 2 bash scripts/run-test-file.sh tests/sleep.test.sh >/dev/null 2>&1)
  rc=$?
  pid=$(cat "$c/tests/sleep.pid" 2>/dev/null)
  if [[ -z $pid ]]; then
    fail "SIG$sig: the fixture never recorded its pid"
  elif kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    fail "SIG$sig: the test process $pid outlived the runner"
  else
    ok "SIG$sig to the runner ends the test it started"
  fi
  want=$((128 + $(kill -l "$sig")))
  if ((rc == want && SECONDS - start < 10)); then
    ok "SIG$sig: the runner exits $want, the test's status, within 10 s"
  else
    fail "SIG$sig: expected rc=$want within 10 s, got rc=$rc after $((SECONDS - start)) s"
  fi
done

test_harness::report
