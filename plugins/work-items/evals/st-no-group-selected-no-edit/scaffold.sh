#!/usr/bin/env bash
# A committed repository with comment markers in two folders: alpha/ holds three, zeta/ holds
# one, so smallest-first order is the reverse of alphabetical order. The marker words are
# assembled at run time so this file carries none of them literally.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

t="TO""DO"
f="FIX""ME"
mkdir -p alpha zeta
{
  printf 'def parse(text):\n'
  printf '    # %s: reject empty input\n' "$t"
  printf '    return text.split(",")\n\n'
  printf 'def render(rows):\n'
  printf '    # %s: rows with commas break the output\n' "$f"
  printf '    return "\\n".join(rows)\n\n'
  printf 'def load(path):\n'
  printf '    # %s: stream large files instead of reading them whole\n' "$t"
  printf '    return open(path).read()\n'
} >alpha/csv_tools.py
{
  printf 'export function label(n) {\n'
  printf '  // %s: pluralize the unit\n' "$t"
  printf '  return n + " item";\n'
  printf '}\n'
} >zeta/label.js
printf '# tools\n' >README.md
git add .
git commit -q -m "chore: scaffold tools"
