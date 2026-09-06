#!/usr/bin/env bash
# Regression tests for python-resolve.sh: the resolver sets PY as an array,
# honours the floor read from report.py, and returns 1 when nothing resolves.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/python-resolve.sh"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# 1. Resolves on this machine and PY runs the floor probe.
# shellcheck source=python-resolve.sh
source "$SCRIPT"
cm_resolve_python
assert_eq "resolves an interpreter" 0 "$?"
assert_eq "floor read from report.py" "3.9" "$CM_PYTHON_FLOOR"
"${PY[@]}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'
assert_eq "PY runs and satisfies the floor" 0 "$?"

# 2. A two-word launcher is kept as two array elements: a fake `py` on an
#    otherwise interpreter-free PATH.
stubs="$(mktemp -d)"
trap 'rm -rf "$stubs"' EXIT
real_python="$(command -v python3 || command -v python)"
cat >"$stubs/py" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == "-3" ]] || exit 9
shift
exec "$real_python" "\$@"
EOF
chmod +x "$stubs/py"
for tool in bash sed tr command; do
  p="$(command -v "$tool" 2>/dev/null)" && [[ -f "$p" ]] && ln -s "$p" "$stubs/$tool"
done
out="$(PATH="$stubs" bash -c 'source "$1"; cm_resolve_python && printf "%s|" "${PY[@]}"' _ "$SCRIPT")"
assert_eq "py -3 resolves as two array elements" "py|-3|" "$out"

# 3. Nothing resolves: returns 1 and PY is empty (a PATH with the shell
#    tools but no interpreter and no launcher).
bare="$(mktemp -d)"
for tool in bash sed tr command; do
  p="$(command -v "$tool" 2>/dev/null)" && [[ -f "$p" ]] && ln -s "$p" "$bare/$tool"
done
out="$(PATH="$bare" bash -c 'source "$1"; cm_resolve_python; printf "%s:%s" "$?" "${#PY[@]}"' _ "$SCRIPT")"
rm -rf "$bare"
assert_eq "no interpreter returns 1 with an empty PY" "1:0" "$out"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
