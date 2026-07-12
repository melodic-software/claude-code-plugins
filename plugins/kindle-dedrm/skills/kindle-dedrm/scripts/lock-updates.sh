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
UPDATES_DIR_WIN="C:\\Users\\${USERNAME}\\AppData\\Local\\Amazon\\Kindle\\updates"
TRUSTEE="${USERDOMAIN}\\${USERNAME}"

action="${1:-check}"

ensure_dir() {
  if [[ ! -d "${UPDATES_DIR_BASH}" ]]; then
    echo "[lock-updates] ${UPDATES_DIR_BASH} does not exist (Kindle for PC not installed?)"
    return 2
  fi
  return 0
}

case "${action}" in
  apply)
    ensure_dir || exit 2
    # Delete cached installer if present
    if [[ -f "${UPDATES_DIR_BASH}/KindleForPC-installer.exe" ]]; then
      echo "[lock-updates] deleting cached installer"
      rm -f "${UPDATES_DIR_BASH}/KindleForPC-installer.exe"
    else
      echo "[lock-updates] no cached installer to delete"
    fi
    # Apply ICACLS deny
    echo "[lock-updates] applying ICACLS deny for ${TRUSTEE}"
    powershell.exe -NoProfile -Command "icacls '${UPDATES_DIR_WIN}' /deny '${TRUSTEE}:(W,WD,AD,WA)'" || {
      echo "[lock-updates] icacls deny failed"
      exit 1
    }
    # Verify lock
    if touch "${UPDATES_DIR_BASH}/test-write" 2>/dev/null; then
      echo "[lock-updates] WARNING: lock test write succeeded — deny did not stick"
      rm -f "${UPDATES_DIR_BASH}/test-write"
      exit 1
    else
      echo "[lock-updates] verified: writes are blocked"
    fi
    ;;
  remove)
    ensure_dir || {
      echo "[lock-updates] dir absent — no deny to remove"
      exit 0
    }
    echo "[lock-updates] removing ICACLS deny for ${TRUSTEE}"
    powershell.exe -NoProfile -Command "icacls '${UPDATES_DIR_WIN}' /remove:d '${TRUSTEE}'" || {
      echo "[lock-updates] icacls remove:d failed"
      exit 1
    }
    # Verify removal
    if touch "${UPDATES_DIR_BASH}/test-write" 2>/dev/null; then
      rm -f "${UPDATES_DIR_BASH}/test-write"
      echo "[lock-updates] verified: writes work (deny removed)"
    else
      echo "[lock-updates] WARNING: still cannot write — another deny may remain"
      powershell.exe -NoProfile -Command "icacls '${UPDATES_DIR_WIN}'"
      exit 1
    fi
    ;;
  check)
    ensure_dir || {
      echo "[lock-updates] absent (n/a)"
      exit 0
    }
    if powershell.exe -NoProfile -Command "icacls '${UPDATES_DIR_WIN}'" 2>/dev/null | grep -q '(DENY)(W)'; then
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
