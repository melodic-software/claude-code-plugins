# shellcheck shell=bash
# Shared body for the docpage-digest gate suites, sourced by the *.test.sh wrappers
# (plugin-gate resolves suites by that filename); sourced, never executed.

# gate_test::run_suite <scripts-dir> <suite-file>: exits 1 on an unparsable
# MIN_PYTHON floor, 0 (SKIP) when no interpreter meets it, else the suite's status.
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
