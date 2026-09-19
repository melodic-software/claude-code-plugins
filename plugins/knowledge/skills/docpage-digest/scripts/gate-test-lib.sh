# shellcheck shell=bash
# Shared wrapper body for the docpage-digest gate suites. Sourced by
# check-fences-exact.test.sh and check-snippets.test.sh, each of which stays a
# *.test.sh file because plugin-gate resolves suites by that filename. This file
# is sourced, never executed, and holds no test cases of its own.

# gate_test::run_suite <scripts-dir> <suite-file>
#
# Resolve an interpreter at or above the MIN_PYTHON floor parsed from
# digest_fences.py, then run <suite-file> under it with -v. Exits 1 when the
# floor cannot be parsed and 0 (SKIP) when no interpreter meets it; otherwise
# the suite's own status is the caller's status.
gate_test::run_suite() {
  local dir="$1" suite="$2"
  local engine="$dir/digest_fences.py"
  local floor
  floor="$(sed -n 's/^MIN_PYTHON = (\([0-9]*\), \([0-9]*\)).*/\1.\2/p' "$engine")"
  if [[ -z "$floor" ]]; then
    echo "FAIL: could not parse MIN_PYTHON from $engine" >&2
    exit 1
  fi

  local python="" candidate resolved lower
  for candidate in python3 python; do
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    lower="$(printf '%s' "$resolved" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lower" == *windowsapps* && ! -s "$resolved" ]]; then
      continue
    fi
    if "$candidate" -c "import sys; floor = tuple(int(part) for part in '$floor'.split('.')); raise SystemExit(0 if sys.version_info >= floor else 1)"; then
      python="$candidate"
      break
    fi
  done
  if [[ -z "$python" ]]; then
    echo "SKIP: Python ${floor}+ not found" >&2
    exit 0
  fi

  "$python" "$dir/$suite" -v
}
