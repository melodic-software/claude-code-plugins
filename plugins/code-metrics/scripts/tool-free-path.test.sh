#!/usr/bin/env bash
# Regression tests for tool-free-path.sh: the excluded set is derived from
# the collector ladder, the filled directory keeps those collectors off PATH,
# and the resolvable-collector check fails when one is put back.
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

# 1. The ladder names the shipped adapters (skipping reserved rungs).
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

# 2. Adapter PATH names that differ from the ladder tool name are in the
#    excluded set (mypy-report looks up mypy, cpd looks up pmd).
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

# 3. A filled directory has none of those names resolvable, and no adapter
#    that looks up a binary probes successfully.
EMPTY="$WORK/empty"
cm_fill_tool_free_path "$EMPTY"
leftover="$(cm_resolvable_ladder_collectors "$EMPTY" | sort -u | tr '\n' ' ')"
leftover="${leftover% }"
assert_eq "no ladder collector is resolvable on the tool-free PATH" "" "$leftover"

# 4. Putting a ladder collector back on that directory makes the check fail.
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

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
