#!/usr/bin/env bash
# Runs the DLSS 5 mod script's own selftest so run-plugin-tests.sh discovers it. The selftest
# builds its own temp data dir and fixtures and asserts on file-system state. The script is
# Windows-only (backslash paths, Authenticode), so any other OS SKIPs, as does a machine
# without pwsh.
set -euo pipefail

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *)
    echo "SKIP: not Windows -- DLSS 5 selftest skipped"
    exit 0
    ;;
esac
if ! command -v pwsh >/dev/null 2>&1; then
  echo "SKIP: pwsh not on PATH -- DLSS 5 selftest skipped"
  exit 0
fi

dir="$(cygpath -m "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
pwsh -NoProfile -NonInteractive -File "$dir/Invoke-Dlss5Mod.ps1" -Verb selftest
