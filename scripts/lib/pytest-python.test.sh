#!/usr/bin/env bash
# Tests for scripts/lib/pytest-python.sh through scripts/run-test-file.sh, in
# a throwaway checkout and a linked worktree of it. python3, the venv's python
# and scripts/setup-env.sh are stubs that log what they were asked to run.
# The stubs and the checks hold shell source as literal data on purpose.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SELF_DIR/.." && pwd)"
# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
log="$TMP_ROOT/calls.log"
stubs="$TMP_ROOT/stubs"
mkdir -p "$stubs"

# A python3 without pytest unless PY3_PYTEST=1; a pytest run exits 5.
cat >"$stubs/python3" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == -I ]]; then [[ ${PY3_PYTEST:-} == 1 ]]; exit; fi
echo "python3 $*"
exit 5
EOF
chmod +x "$stubs/python3"

# venv_python <venv>: a venv python that imports pytest and logs its runs.
venv_python() {
  mkdir -p "$1/bin"
  printf '%s\n' '#!/usr/bin/env bash' '[[ $1 == -I ]] && exit 0' "echo \"venv $1 \$*\"" >"$1/bin/python"
  chmod +x "$1/bin/python"
}

c="$TMP_ROOT/checkout"
mkdir -p "$c/scripts/lib" "$c/tests" "$c/.github"
cp "$SCRIPTS_DIR/run-test-file.sh" "$c/scripts/"
cp "$SCRIPTS_DIR/lib/checkout-path.sh" "$SCRIPTS_DIR/lib/pytest-python.sh" "$c/scripts/lib/"
cat >"$c/scripts/setup-env.sh" <<EOF
#!/usr/bin/env bash
echo "setup-env \$* SETUP_ENV_VENV=\$SETUP_ENV_VENV" >>"$log"
[[ \${SETUP_STUB_FAIL:-} == 1 ]] && exit 1
mkdir -p "\$SETUP_ENV_VENV/bin"
printf '%s\n' '#!/usr/bin/env bash' '[[ \$1 == -I ]] && exit 0' 'echo "built \$*"' >"\$SETUP_ENV_VENV/bin/python"
chmod +x "\$SETUP_ENV_VENV/bin/python"
EOF
echo 3.99 >"$c/.python-version"
echo 'pytest==9 --hash=sha256:aa' >"$c/.github/requirements-ci.txt"
echo 'def test_a(): pass' >"$c/tests/test_a.py"
echo .work/ >"$c/.gitignore"
git init -q "$c"
git -C "$c" add -A
git -C "$c" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm base
w="$TMP_ROOT/worktree"
git -C "$c" worktree add -q --detach "$w"

# run_in <dir> [VAR=value...]: run-test-file on tests/test_a.py; sets OUT, ERR, RC.
run_in() {
  local dir=$1
  shift
  : >"$log"
  RC=0
  OUT="$(cd "$dir" && env -u CI -u GITHUB_ACTIONS -u SETUP_ENV_VENV PATH="$stubs:$PATH" "$@" \
    bash scripts/run-test-file.sh tests/test_a.py 2>"$TMP_ROOT/err")" || RC=$?
  ERR="$(cat "$TMP_ROOT/err")"
}

check() {
  if eval "$2"; then ok "$1"; else fail "$1: rc=$RC out=[$OUT] err=[$ERR] calls=[$(cat "$log")]"; fi
}

venv_python "$c/.work/venv"
run_in "$c"
check "python3 lacks pytest and the checkout's venv has it: the venv runs the suite" \
  '[[ $RC == 0 && $OUT == "venv $c/.work/venv -m pytest -q -p no:cacheprovider -- tests/test_a.py" && ! -s $log ]]'

run_in "$w"
check "a linked worktree uses the main checkout's venv" \
  '[[ $RC == 0 && $OUT == "venv $c/.work/venv -m pytest -q -p no:cacheprovider -- tests/test_a.py" ]]'

venv_python "$TMP_ROOT/elsewhere"
run_in "$w" SETUP_ENV_VENV="$TMP_ROOT/elsewhere"
check "SETUP_ENV_VENV comes first" \
  '[[ $RC == 0 && $OUT == "venv $TMP_ROOT/elsewhere -m pytest -q -p no:cacheprovider -- tests/test_a.py" ]]'

rm -rf "$c/.work"
run_in "$c" PY3_PYTEST=1
check "with no venv, a python3 that imports pytest runs the suite and setup-env does not run" \
  '[[ $RC == 5 && $OUT == "python3 -m pytest -q -p no:cacheprovider -- tests/test_a.py" && ! -s $log ]]'

run_in "$w"
check "with neither, setup-env runs once from the worktree, building the main checkout's venv, which runs the suite" \
  '[[ $RC == 0 && $(cat "$log") == "setup-env --root $w SETUP_ENV_VENV=$c/.work/venv" && $OUT == "built -m pytest -q -p no:cacheprovider -- tests/test_a.py" && $ERR == *"python3 has no pytest; building $c/.work/venv"* ]]'

run_in "$w"
check "the next run finds that venv and runs no setup-env" \
  '[[ $RC == 0 && $OUT == "built -m pytest -q -p no:cacheprovider -- tests/test_a.py" && ! -s $log ]]'

rm -rf "$c/.work"
for ci in CI=true GITHUB_ACTIONS=true; do
  run_in "$c" "$ci"
  check "under $ci, setup-env never runs and python3 runs the suite" \
    '[[ $RC == 5 && $OUT == "python3 -m pytest -q -p no:cacheprovider -- tests/test_a.py" && ! -s $log ]]'
done

run_in "$c" SETUP_STUB_FAIL=1
check "a failed setup-env falls back to python3, saying so" \
  '[[ $RC == 5 && $OUT == "python3 -m pytest -q -p no:cacheprovider -- tests/test_a.py" && $(cat "$log") == "setup-env --root $c SETUP_ENV_VENV=$c/.work/venv" && $ERR == *"setup-env did not leave pytest"* ]]'

test_harness::report
