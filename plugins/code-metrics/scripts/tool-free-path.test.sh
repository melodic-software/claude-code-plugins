#!/usr/bin/env bash
# test-scope: plugins/code-metrics/scripts/collectors/*.py
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool-free-path.sh
source "$SCRIPT_DIR/tool-free-path.sh"

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

tools="$(cm_ladder_tools | tr '\n' ' ')"
tools="${tools% }"
case " $tools " in
*" lizard "* | *" type-coverage "* | *" mypy-report "* | *" cpd "* | *" line-counter "*)
  pass "the ladder lists shipped collectors"
  ;;
*)
  fail "the ladder lists shipped collectors" "lizard type-coverage mypy-report cpd line-counter" "$tools"
  ;;
esac
case " $tools " in
*" none "* | *" n/a "* | *" deferred "*)
  fail "reserved rungs are not collectors" "no none/n/a/deferred" "$tools"
  ;;
*)
  pass "reserved rungs are not collectors"
  ;;
esac

bins="$(cm_ladder_path_bins | tr '\n' ' ')"
bins="${bins% }"
case " $bins " in
*" mypy "* | *" pmd "* | *" eslint "*)
  pass "adapter PATH names that differ from the ladder tool are excluded"
  ;;
*)
  fail "adapter PATH names that differ from the ladder tool are excluded" \
    "mypy pmd eslint among the bins" "$bins"
  ;;
esac

EMPTY="$WORK/empty"
cm_fill_tool_free_path "$EMPTY"
leftover="$(cm_resolvable_ladder_collectors "$EMPTY" | sort -u | tr '\n' ' ')"
leftover="${leftover% }"
assert_eq "no ladder collector is resolvable on the tool-free PATH" "" "$leftover"

mkdir -p "$WORK/leak"
cp -a "$EMPTY/." "$WORK/leak/"
cat >"$WORK/leak/lizard" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then printf '1.24.0\n'; exit 0; fi
exit 0
EOF
chmod +x "$WORK/leak/lizard"
leaked="$(cm_resolvable_ladder_collectors "$WORK/leak" | sort -u | tr '\n' ' ')"
leaked="${leaked% }"
case " $leaked " in
*" lizard "*)
  pass "a collector put back on the path is reported as resolvable"
  ;;
*)
  fail "a collector put back on the path is reported as resolvable" "lizard among: $leaked" "$leaked"
  ;;
esac

REAL_PY="$(command -v python3 || command -v python)"
REAL_PY="$("$REAL_PY" -c 'import os, sys; print(os.path.realpath(sys.executable))')"
mkdir -p "$WORK/shimdir" "$WORK/version-bin"
cat >"$WORK/version-bin/mypy" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$WORK/version-bin/mypy"
cat >"$WORK/shimdir/python3" <<EOF
#!/usr/bin/env bash
export PATH="$WORK/version-bin:\$PATH"
exec "$REAL_PY" "\$@"
EOF
chmod +x "$WORK/shimdir/python3"
EMPTY_SHIM="$WORK/empty-shim"
PATH="$WORK/shimdir:$PATH" cm_fill_tool_free_path "$EMPTY_SHIM"
shim_target="$(readlink "$EMPTY_SHIM/python3" 2>/dev/null || true)"
if [[ "$shim_target" == "$REAL_PY" ]]; then
  pass "python3 on the tool-free PATH is the non-mutating interpreter"
else
  fail "python3 on the tool-free PATH is the non-mutating interpreter" "$REAL_PY" "$shim_target"
fi
leftover_shim="$(cm_resolvable_ladder_collectors "$EMPTY_SHIM" | sort -u | tr '\n' ' ')"
leftover_shim="${leftover_shim% }"
assert_eq "a PATH-mutating python3 shim does not restore mypy-report" "" "$leftover_shim"

mkdir -p "$WORK/planted"
printf 'open("%s", "w").close()\nraise SystemExit(0)\n' "$WORK/planted/PWNED" >"$WORK/planted/ast.py"
planted_bins="$(cd "$WORK/planted" && cm_ladder_path_bins | tr '\n' ' ')"
planted_bins="${planted_bins% }"
if [[ -e "$WORK/planted/PWNED" ]]; then
  fail "a planted ast.py in the working directory is not imported" "no marker" "marker created"
else
  pass "a planted ast.py in the working directory is not imported"
fi
assert_eq "the ladder reader's output is the same beside a planted ast.py" "$bins" "$planted_bins"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
