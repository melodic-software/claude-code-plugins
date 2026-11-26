#!/usr/bin/env bash
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

# shellcheck source=python-resolve.sh
source "$SCRIPT"
cm_resolve_python
assert_eq "resolves an interpreter" 0 "$?"
assert_eq "floor read from report.py" "3.9" "$CM_PYTHON_FLOOR"
"${PY[@]}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'
assert_eq "PY runs and satisfies the floor" 0 "$?"

stubs="$(mktemp -d)"
trap 'rm -rf "$stubs"' EXIT
real_python="$(command -v python3 || command -v python)"
for name in python3 python; do
  cat >"$stubs/$name" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$stubs/$name"
done
cat >"$stubs/py" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == "-3" ]] || exit 9
shift
exec "$real_python" "\$@"
EOF
chmod +x "$stubs/py"
out="$(PATH="$stubs:$PATH" bash -c 'source "$1"; cm_resolve_python && printf "%s|" "${CM_PY_NATIVE[@]}"' _ "$SCRIPT")"
assert_eq "py -3 resolves as two array elements" "py|-3|" "$out"

cp "$stubs/python3" "$stubs/py"
out="$(PATH="$stubs:$PATH" bash -c 'source "$1"; cm_resolve_python; printf "%s:%s" "$?" "${#PY[@]}"' _ "$SCRIPT")"
assert_eq "no interpreter returns 1 with an empty PY" "1:0" "$out"

out="$("${PY[@]}" -c 'print("a"); print("b")' | od -An -c | tr -s ' \n' ' ')"
assert_eq "PY output carries no CR on this machine" " a \n b \n " "$out"

crlf="$(mktemp -d)"
cat >"$crlf/python3" <<EOF
#!/usr/bin/env bash
"$real_python" "\$@" | sed 's/\r*\$/\r/'
exit "\${PIPESTATUS[0]}"
EOF
chmod +x "$crlf/python3"
out="$(PATH="$crlf:$PATH" bash -c 'source "$1"; cm_resolve_python && printf "%s|%s|" "${PY[*]}" "${CM_PY_NATIVE[*]}"; "${PY[@]}" -c "print(\"a\"); print(\"b\")" | od -An -c | tr -s " \n" " "' _ "$SCRIPT")"
assert_eq "a CRLF interpreter is wrapped and its output is LF-only" "cm_py_lf|python3| a \n b \n " "$out"
out="$(PATH="$crlf:$PATH" bash -c 'source "$1"; cm_resolve_python; "${PY[@]}" -c "raise SystemExit(3)"; printf "%s" "$?"' _ "$SCRIPT")"
assert_eq "the wrapper keeps the interpreter's exit status" "3" "$out"
rm -rf "$crlf"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
