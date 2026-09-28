#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$ROOT/decision-rows.sh"
fail=0
ok() { printf 'PASS: %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }

good=$'correct\tSKILL.md\twas P1 / is a lens\t1\topen\nreplace\taudit\tnative overlap\t2\tnominated\nnote\t\tremember\t3\t\n'
if printf '%s' "$good" | bash "$SCRIPT" >/tmp/dec-out.txt; then
  ok "valid rows pass"
else
  bad "valid rows pass"
fi

if printf '%s\n' $'skip\t\t\t\t' | bash "$SCRIPT" >/dev/null 2>/tmp/dec-err.txt; then
  bad "skip should fail"
else
  if grep -q "skip leaves no row" /tmp/dec-err.txt; then
    ok "skip has no row"
  else
    bad "skip message"
  fi
fi

if printf '%s\n' $'adopt\towner\t\t1\t' | bash "$SCRIPT" >/dev/null 2>/tmp/dec-err.txt; then
  bad "empty adopt sentence should fail"
else
  ok "adopt requires a sentence"
fi

if printf '%s\n' $'replace\towner\tnamed\t1\treplaced' | bash "$SCRIPT" >/dev/null 2>/tmp/dec-err.txt; then
  bad "replaced state should fail"
else
  if grep -q "nominated" /tmp/dec-err.txt; then
    ok "replace stays nominated"
  else
    bad "replace message"
  fi
fi

dir="$(mktemp -d)"
if printf '%s' "$good" | bash "$SCRIPT" --write "$dir" >/dev/null && [[ -f "$dir/decisions.tsv" ]]; then
  ok "write working set"
else
  bad "write working set"
fi
rm -rf "$dir"
[[ "$fail" -eq 0 ]]
