#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
commit() { git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "$1"; }

printf '%s\n' '[FORMAT]' 'max-module-lines=400' >.pylintrc
printf '%s\n' '# ledger' 'Posts entries to the ledger.' >README.md
for i in $(seq 1 700); do
  printf 'RATE_%d = %d\n' "$i" "$i"
done >constants.py
for i in $(seq 1 520); do
  printf 'def post_%d(entry):\n    return entry + %d\n' "$i" "$i"
done >ledger.py
printf '%s\n' 'def total(entries):' '    return sum(entries)' >report.py
git add .pylintrc README.md constants.py ledger.py report.py
commit "add the ledger"

for i in $(seq 1 8); do
  printf 'def adjust_%d(entry):\n    return entry - %d\n' "$i" "$i" >>ledger.py
  git add ledger.py
  commit "ledger: add adjustment $i"
done
