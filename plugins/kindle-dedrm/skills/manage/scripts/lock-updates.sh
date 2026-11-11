#!/usr/bin/env bash
# lock-updates.sh — apply or remove the ICACLS deny on Kindle's updates dir.
# Apply: deletes any cached installer, then denies write so Kindle can't re-download.
# Remove: clears the deny ACE (cleanup action only).
#
# Usage: lock-updates.sh {apply|remove|check}
#
# Exit codes: 0 = success, 1 = failure, 2 = path doesn't exist

# shellcheck disable=SC2154
# (Windows env vars LOCALAPPDATA/USERNAME/USERDOMAIN are set on Git Bash runtime)

set -uo pipefail

UPDATES_DIR_BASH="${LOCALAPPDATA}/Amazon/Kindle/updates"
# LOCALAPPDATA is already a native Windows path on Git Bash (C:\Users\<user>\AppData\Local),
# so derive the icacls target from it — honors OneDrive-redirected or non-C: profiles.
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

# icacls_updates [args]: icacls on the updates dir through PowerShell; no args lists its ACL.
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
