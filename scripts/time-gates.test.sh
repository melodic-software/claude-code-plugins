# shellcheck shell=bash
# Self-test for scripts/time-gates.sh: the row format, the invocation each gate
# gets, a failing gate's exit code recorded rather than judged, and the usage
# errors. The gates are stubs under a mktemp root handed over in
# TIME_GATES_ROOT, so no real gate runs here.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMER="$ROOT/scripts/time-gates.sh"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
stub_root="$scratch/tree"
gates=(
  scripts/check-purged-em-dashes.sh
  scripts/check-changed-skills.sh
  scripts/check-changelog-parity.sh
  plugins/skill-quality/scripts/check-skill.sh
  plugins/planning/scripts/check-open-questions.sh
)
# Each stub records its arguments, and the check-skill stub its skills root, to
# <gate>.args under the scratch directory. The parity stub fails with exit 1.
for g in "${gates[@]}"; do
  mkdir -p "$stub_root/$(dirname "$g")"
  rc=0
  [[ "$g" != scripts/check-changelog-parity.sh ]] || rc=1
  # The body is written literally: its $ must survive into the stub.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" "${CHECK_SKILL_SKILLS_ROOT:-}" >"%s/%s.args"\nexit %s\n' \
    "$scratch" "${g##*/}" "$rc" >"$stub_root/$g"
done

out="$scratch/gates.tsv"
rc=0
TIME_GATES_ROOT="$stub_root" bash "$TIMER" --timings "$out" --base main >/dev/null 2>&1 || rc=$?
if ((rc == 0)); then
  ok "a run that wrote every row exits 0, a failing gate included"
else
  fail "expected exit 0, got $rc"
fi
if [[ "$(cut -f1 "$out")" == "$(printf '%s\n' "${gates[@]}")" ]]; then
  ok "one row per gate, in order"
else
  fail "rows: [$(<"$out")]"
fi
row_shape=$'^[^\t]+\t[0-9]+\\.[0-9]{3}\t[0-9]+$'
bad=0
while IFS= read -r row; do
  [[ "$row" =~ $row_shape ]] || bad=1
done <"$out"
if ((bad == 0)); then
  ok "each row is path, seconds to the millisecond and exit code"
else
  fail "a row is malformed: [$(<"$out")]"
fi
if [[ "$(grep '^scripts/check-changelog-parity.sh' "$out" | cut -f3)" == 1 ]]; then
  ok "a failing gate's exit code is recorded"
else
  fail "parity row: [$(<"$out")]"
fi

# expect_eq <label> <want> <got>
expect_eq() {
  if [[ "$3" == "$2" ]]; then
    ok "$1"
  else
    fail "$1: expected [$2], got [$3]"
  fi
}
args_of() { sed -n "${2:-1}p" "$scratch/$1.args"; }
expect_eq "the em-dash gate runs --check" "--check" "$(args_of check-purged-em-dashes.sh)"
expect_eq "the changed-skills gate gets --base" "main" "$(args_of check-changed-skills.sh)"
expect_eq "the parity gate runs --check-bump against --base" "--check-bump main" "$(args_of check-changelog-parity.sh)"
expect_eq "the skill gate checks one skill" "check" "$(args_of check-skill.sh)"
expect_eq "the skill gate reads its plugin's skills root" "$stub_root/plugins/skill-quality/skills" "$(args_of check-skill.sh 2)"
ledger_args="$(args_of check-open-questions.sh)"
expect_eq "the register gate gets a ledger" "--ledger interview-checklist.md" "${ledger_args%% *} ${ledger_args##*/}"

# run_timer <label> <want-rc> <args...>
run_timer() {
  local label="$1" want="$2" rc=0
  shift 2
  TIME_GATES_ROOT="$stub_root" bash "$TIMER" "$@" >/dev/null 2>&1 || rc=$?
  expect_eq "$label" "$want" "$rc"
}
run_timer "no --timings is a usage error" 2
run_timer "a --timings file in a missing directory is rejected" 2 --timings "$scratch/missing/t.tsv"
rm "$stub_root/plugins/planning/scripts/check-open-questions.sh"
run_timer "a missing gate is an error" 2 --timings "$out"

test_harness::report
