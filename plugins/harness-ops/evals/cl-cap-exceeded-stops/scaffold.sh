#!/usr/bin/env bash
# A local copy of a twelve-release changelog (2.1.250 to 2.1.261), past the ten-release replay cap.
set -euo pipefail
{
  printf '# Claude Code changelog\n\n'
  for n in 261 260 259 258 257 256 255 254 253 252 251 250; do
    printf '<Update label="2.1.%s" description="September %s, 2026">\n' "$n" "$((n - 249))"
    printf -- '* Added the --probe-%s flag to claude plugin eval\n' "$n"
    printf -- '* Fixed hook output truncation in release %s\n' "$n"
    printf '</Update>\n\n'
  done
} >changelog.md
