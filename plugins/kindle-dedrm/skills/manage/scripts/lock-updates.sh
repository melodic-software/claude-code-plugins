#!/usr/bin/env bash
# Exit codes: 0 = success, 1 = failure, 2 = path doesn't exist

# Git Bash sets the Windows env vars at runtime.
# shellcheck disable=SC2154

set -uo pipefail

UPDATES_DIR_BASH="${LOCALAPPDATA}/Amazon/Kindle/updates"
UPDATES_DIR_WIN="${LOCALAPPDATA}\\Amazon\\Kindle\\updates"
TRUSTEE="${USERDOMAIN}\\${USERNAME}"
CACHED_INSTALLER="${UPDATES_DIR_BASH}/KindleForPC-installer.exe"
TEST_WRITE="${UPDATES_DIR_BASH}/test-write"

action="${1:-check}"

ensure_dir() {
  if [[ ! -d "${UPDATES_DIR_BASH}" ]]; then
    echo "[lock-updates] ${UPDATES_DIR_BASH} does not exist (Kindle for PC not installed?)"
    return 2
  fi
}

icacls_updates() {
  powershell.exe -NoProfile -Command "icacls '${UPDATES_DIR_WIN}'${1:+ $1}"
}

case "${action}" in
apply)
  ensure_dir || exit 2
  if [[ -f "${CACHED_INSTALLER}" ]]; then
    echo "[lock-updates] deleting cached installer"
    rm -f "${CACHED_INSTALLER}"
  else
    echo "[lock-updates] no cached installer to delete"
  fi
  echo "[lock-updates] applying ICACLS deny for ${TRUSTEE}"
  icacls_updates "/deny '${TRUSTEE}:(W,WD,AD,WA)'" || {
    echo "[lock-updates] icacls deny failed"
    exit 1
  }
  if touch "${TEST_WRITE}" 2>/dev/null; then
    echo "[lock-updates] WARNING: lock test write succeeded — deny did not stick"
    rm -f "${TEST_WRITE}"
    exit 1
  fi
  echo "[lock-updates] verified: writes are blocked"
  ;;
remove)
  ensure_dir || {
    echo "[lock-updates] dir absent — no deny to remove"
    exit 0
  }
  echo "[lock-updates] removing ICACLS deny for ${TRUSTEE}"
  icacls_updates "/remove:d '${TRUSTEE}'" || {
    echo "[lock-updates] icacls remove:d failed"
    exit 1
  }
  if touch "${TEST_WRITE}" 2>/dev/null; then
    rm -f "${TEST_WRITE}"
    echo "[lock-updates] verified: writes work (deny removed)"
  else
    echo "[lock-updates] WARNING: still cannot write — another deny may remain"
    icacls_updates
    exit 1
  fi
  ;;
check)
  ensure_dir || {
    echo "[lock-updates] absent (n/a)"
    exit 0
  }
  if grep -q '(DENY)(W)' < <(icacls_updates 2>/dev/null); then
    echo "[lock-updates] DENY active"
    exit 0
  else
    echo "[lock-updates] no DENY in place"
    exit 1
  fi
  ;;
*)
  echo "Usage: $0 {apply|remove|check}"
  exit 1
  ;;
esac
