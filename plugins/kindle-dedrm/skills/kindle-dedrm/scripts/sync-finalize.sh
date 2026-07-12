#!/usr/bin/env bash
# sync-finalize.sh — close the sync window: delete cached installer, re-enable firewall.
# Run AFTER user has opened Kindle, synced, and quit Kindle entirely.
#
# Usage: sync-finalize.sh

# shellcheck disable=SC2154
# (Windows env vars LOCALAPPDATA/USERNAME are runtime-resolved)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KINDLE_UPDATES_DIR="${LOCALAPPDATA}/Amazon/Kindle/updates"

echo "=== kindle-dedrm: sync finalize ==="

# Step 1 — confirm Kindle is not running
if powershell.exe -NoProfile -Command "Get-Process Kindle -ErrorAction SilentlyContinue" 2>/dev/null | grep -qi kindle; then
  echo "[sync-finalize] ERROR: Kindle is still running. Quit it (File → Exit + close tray icon) and re-run."
  exit 1
fi

# Step 2 — verify Kindle.exe is still 2.8.0.70980
KINDLE_VER=$(powershell.exe -NoProfile -Command "(Get-Item 'C:\\Users\\${USERNAME}\\AppData\\Local\\Amazon\\Kindle\\application\\Kindle.exe').VersionInfo.FileVersion" 2>/dev/null | tr -d '\r\n ')
if [[ "${KINDLE_VER}" != "2.8.0.70980" ]]; then
  echo "[sync-finalize] WARNING: Kindle.exe version is ${KINDLE_VER}, expected 2.8.0.70980"
  echo "[sync-finalize] An auto-update may have run. See references/troubleshooting.md 'Installed wrong Kindle for PC version'."
  echo "[sync-finalize] Continuing with cleanup anyway, but key extraction may fail until version is restored."
fi

# Step 3 — delete any cached installer (this is what the firewall didn't catch)
if [[ -f "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" ]]; then
  SIZE=$(stat -c%s "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" 2>/dev/null || echo unknown)
  echo "[sync-finalize] cached installer present (${SIZE} bytes) — deleting"
  rm -f "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe"
  if [[ -f "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" ]]; then
    echo "[sync-finalize] ERROR: delete failed (file still present)"
    exit 1
  fi
  echo "[sync-finalize] cached installer deleted"
else
  echo "[sync-finalize] no cached installer — firewall caught the update attempt"
fi

# Step 4 — clean any other unexpected files in updates/ (paranoia)
OTHER_FILES=$(find "${KINDLE_UPDATES_DIR}" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
if [[ "${OTHER_FILES}" -gt 0 ]]; then
  echo "[sync-finalize] additional files in updates dir:"
  ls -la "${KINDLE_UPDATES_DIR}"
  echo "[sync-finalize] manually inspect; deleting non-installer files..."
  find "${KINDLE_UPDATES_DIR}" -mindepth 1 -delete 2>/dev/null || true
fi

# Step 5 — re-enable firewall (admin required)
echo
echo "[sync-finalize] re-enabling firewall rule (admin required)..."
echo
echo "  Open elevated PowerShell and run:"
echo "    Enable-NetFirewallRule -DisplayName 'Block Kindle for PC (lock 2.8.0)'"
echo
echo "  Or run this skill's wrapper from elevated pwsh:"
echo "    pwsh -File '${SCRIPT_DIR}/firewall.ps1' -Action enable"
echo

# Step 6 — prompt user to run keyfinder
cat <<'EOF'
=== NEXT (process new books) ===

After firewall is re-enabled:

1. Quit Calibre completely (the keyfinder writes to dedrm.json — conflicts if Calibre is running).

2. Double-click ~/Tools/Kindle_Key_Finder/Run_keyfinder_admin.vbs (UAC prompt → Yes).

3. Saved config auto-loads (10s countdown). Tool processes only new books:
   - Phase 1: Key extraction
   - Phase 2: DeDRM config (writes new keys to dedrm.json)
   - Phase 3: Calibre import (DeDRM strips encryption)
   - Phase 4: KFX → EPUB conversion

4. Verify new EPUBs:
   find "${USERPROFILE}/Calibre Library" -name "*.epub" -mtime -1

=== END ===
EOF

exit 0
