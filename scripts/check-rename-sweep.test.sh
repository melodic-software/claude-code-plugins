#!/usr/bin/env bash
# Self-test for scripts/check-rename-sweep.sh: the clean tree passes, and a
# seeded stale reference under vendor/ (the sweep's known-miss regression class)
# is caught with a non-zero exit.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

pass=0
fail=0
seed="plugins/knowledge/vendor/.rename-sweep-selftest.md"
trap 'rm -f "$seed"' EXIT

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name (expected exit $expected, got $actual)" >&2
    fail=$((fail + 1))
  fi
}

bash scripts/check-rename-sweep.sh >/dev/null 2>&1
check "clean tree passes (allowlisted CHANGELOG + trigger-phrase hits only)" 0 $?

printf 'stale ref: youtube-digest\n' > "$seed"
bash scripts/check-rename-sweep.sh >/dev/null 2>&1
check "seeded vendor/ stale ref is caught" 1 $?

out="$(bash scripts/check-rename-sweep.sh 2>&1 >/dev/null)" || true
case "$out" in
  *"$seed"*) echo "ok: violation output names the seeded file"; pass=$((pass + 1)) ;;
  *) echo "FAIL: violation output does not name the seeded file" >&2; fail=$((fail + 1)) ;;
esac
rm -f "$seed"

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
