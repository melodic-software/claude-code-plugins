#!/usr/bin/env bash
# Tests for score-deterministic.py item 8 (S1 token handling), on copies of a pilot run.
# Usage: score-deterministic-check.sh [RESULT_DIR]  (default: results-p2/S1/A1/opus/run-3, the Phase 2 pilot
# whose BranchStartCommand.cs the token-flag-accepted case edits; its sed matches only that code)
# Expected values come from the rubric: a CLI that accepts --token, or that does not build,
# fails item 8; the pilot run, which reads the token from TARNQUILL_FORGE_TOKEN and rejects
# --token with exit 2, passes it. Exit: 0 all pass, 1 a case failed, 2 setup error.
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$HARNESS_DIR/../results-p2/S1/A1/opus/run-3}"
SCRATCH="${EVAL_TEST_DIR:?set EVAL_TEST_DIR to a scratch directory outside the repository}"
[[ -f "$SRC/meta.json" ]] || {
  echo "no meta.json in $SRC" >&2
  exit 2
}
WS_SRC="$(jq -r .workspace "$SRC/meta.json")"
CMD_FILE=src/Tarnquill.Cli/Commands/BranchStartCommand.cs
fails=0

make_case() {
  local name="$1" dir="$SCRATCH/$1"
  rm -rf "${dir:?}"
  mkdir -p "$dir"
  cp -a "$WS_SRC" "$dir/ws" && cp -a "$SRC" "$dir/out" || exit 2
  rm -f "$dir/out/score.json"
  jq --arg w "$dir/ws" '.workspace = $w' "$SRC/meta.json" >"$dir/out/meta.json"
  printf '%s\n' "$dir"
}

expect_item8() {
  local name="$1" dir="$2" want="$3" evidence_re="$4" got evidence
  if ! python3 -I "$HARNESS_DIR/score-deterministic.py" "$dir/out" >/dev/null 2>"$dir/stderr"; then
    echo "FAIL $name: scorer exited non-zero: $(tail -1 "$dir/stderr")"
    fails=$((fails + 1))
    return
  fi
  got="$(jq -r '.items[] | select(.item == 8) | .pass' "$dir/out/score.json")"
  evidence="$(jq -r '.items[] | select(.item == 8) | .evidence' "$dir/out/score.json")"
  if [[ "$got" == "$want" && "$evidence" =~ $evidence_re ]]; then
    echo "PASS $name: item 8 = $got"
  else
    echo "FAIL $name: item 8 = $got (want $want); evidence: $evidence"
    fails=$((fails + 1))
  fi
}

d="$(make_case unmodified)"
expect_item8 unmodified "$d" true 'accepted \(exit 2\)=False'

d="$(make_case build-fails)"
printf '\nthis does not compile\n' >>"$d/ws/$CMD_FILE"
expect_item8 build-fails "$d" false 'accepted \(exit None\)=True'

d="$(make_case token-flag-accepted)"
sed -i 's/case "--dry-run":/case "--token": skip = true; break;\n                case "--dry-run":/; s/foreach (var arg in args)/var skip = false;\n        foreach (var arg in args)/; s/^\(\s*\)\(switch (arg)\)/\1if (skip) { skip = false; continue; }\n\1\2/' "$d/ws/$CMD_FILE"
expect_item8 token-flag-accepted "$d" false 'accepted \(exit 0\)=True'

((fails == 0)) && echo "all item-8 cases pass" || exit 1
