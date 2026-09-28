#!/usr/bin/env bash
# Exercises the csharp-ls Windows spawn planner and the shell-less launcher.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if grep -nE 'shell:[[:space:]]*true|cmd\.exe' "$ROOT/bin/"*.mjs; then
  printf 'csharp-ls spawn must not set shell true or call cmd.exe\n' >&2
  exit 1
fi

node --test "$ROOT/bin/csharp-ls-windows-spawn.test.mjs"
