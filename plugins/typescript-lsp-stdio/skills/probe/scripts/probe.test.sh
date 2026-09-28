#!/usr/bin/env bash
# Exercises the shell-less typescript-language-server spawn plan.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if grep -nE 'shell:[[:space:]]*true|cmd\.exe' "$ROOT/bin/"*.mjs; then
  printf 'typescript lsp spawn must not set shell true or call cmd.exe\n' >&2
  exit 1
fi

node --test "$ROOT/bin/typescript-lsp-stdio.test.mjs"
