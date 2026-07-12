#!/usr/bin/env bash
# cleanup.sh — reverse every mutation made by the kindle-dedrm skill.
# Per-item confirmation by default. --soft skips destructive Kindle/Calibre changes.
# --full additionally offers to uninstall Kindle for PC and remove Calibre plugins.
#
# Usage: cleanup.sh [--soft|--full] [--dry-run]
#
# Default mode: confirm-each across the standard reversal matrix.
# --soft: tools + downloads only (keep firewall + ICACLS + Kindle for PC + plugins).
# --full: everything including Kindle for PC uninstaller + Calibre plugin reminder.

# shellcheck disable=SC2154
# (Windows env vars LOCALAPPDATA/APPDATA are set on Git Bash runtime)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="confirm" # confirm | soft | full
DRY_RUN=0
for arg in "$@"; do
  case "${arg}" in
    --soft) MODE="soft" ;;
    --full) MODE="full" ;;
    --dry-run) DRY_RUN=1 ;;
    *)
      echo "Unknown arg: ${arg}"
      exit 1
      ;;
  esac
done

KINDLE_UPDATES_DIR="${LOCALAPPDATA}/Amazon/Kindle/updates"
KINDLE_APP_DIR="${LOCALAPPDATA}/Amazon/Kindle/application"
CALIBRE_PLUGINS_DIR="${APPDATA}/calibre/plugins"
KEY_FINDER_DIR="${HOME}/Tools/Kindle_Key_Finder"
DOWNLOADS_DIR="${HOME}/Downloads"

ask_yn() {
  local prompt="$1"
  if [[ "${MODE}" == "soft" ]]; then
    case "${prompt}" in
      *"firewall"* | *"ICACLS"* | *"Kindle for PC uninstall"* | *"Calibre plugin"*) return 1 ;;
      *) ;;
    esac
  fi
  if [[ "${MODE}" == "full" ]]; then
    case "${prompt}" in
      *"Calibre Library"*) return 1 ;;
      *) ;;
    esac
  fi
  echo
  read -r -p "${prompt} [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

run_or_show() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] would run: $*"
  else
    # shellcheck disable=SC2294
    # (callers pass shell strings with redirections/pipes, not array args)
    eval "$@"
  fi
}

echo "=== kindle-dedrm: cleanup (mode=${MODE}, dry-run=${DRY_RUN}) ==="
echo
echo "Reversal walkthrough. Each item is confirmed independently."
echo "The user's Calibre Library (decrypted EPUBs) is NEVER offered for deletion."
echo

# --- 1. Firewall rule ---
if [[ "${MODE}" != "soft" ]]; then
  if ask_yn "Remove firewall rule 'Block Kindle for PC (lock 2.8.0)'?"; then
    run_or_show "pwsh -NoProfile -File '${SCRIPT_DIR}/firewall.ps1' -Action remove"
  else
    echo "  skipped — firewall rule retained"
  fi
fi

# --- 2. ICACLS deny on updates dir ---
if [[ "${MODE}" != "soft" ]]; then
  if ask_yn "Remove ICACLS deny on ${KINDLE_UPDATES_DIR}?"; then
    run_or_show "bash '${SCRIPT_DIR}/lock-updates.sh' remove"
  else
    echo "  skipped — ICACLS deny retained"
  fi
fi

# --- 3. Cached installer in updates dir ---
if [[ -f "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" ]]; then
  if ask_yn "Delete cached installer at ${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe?"; then
    run_or_show "rm -f '${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe'"
  else
    echo "  skipped — cached installer retained"
  fi
fi

# --- 4. ~/Tools/Kindle_Key_Finder ---
if [[ -d "${KEY_FINDER_DIR}" ]]; then
  if ask_yn "Delete ${KEY_FINDER_DIR}/ (key finder + saved config + extracted keys)?"; then
    run_or_show "rm -rf '${KEY_FINDER_DIR}'"
  else
    echo "  skipped — keyfinder retained"
  fi
fi

# --- 5. Downloaded artifacts ---
if [[ -f "${DOWNLOADS_DIR}/KindleForPC-installer-2.8.70980.exe" ]]; then
  if ask_yn "Delete ${DOWNLOADS_DIR}/KindleForPC-installer-2.8.70980.exe?"; then
    run_or_show "rm -f '${DOWNLOADS_DIR}/KindleForPC-installer-2.8.70980.exe'"
  else
    echo "  skipped — installer retained (useful for re-setup if Amazon revokes URL)"
  fi
fi

# Glob arrays (not ls-capture): quoted array expansion survives paths with spaces,
# and rm receives real array elements rather than eval-word-split strings.
DEDRM_ZIPS=("${DOWNLOADS_DIR}"/DeDRM_tools-v*.zip)
DEDRM_DIRS=("${DOWNLOADS_DIR}"/DeDRM_tools-v*/)
if [[ -e "${DEDRM_ZIPS[0]}" || -e "${DEDRM_DIRS[0]}" ]]; then
  if ask_yn "Delete DeDRM_tools zip + extracted dir from ${DOWNLOADS_DIR}/?"; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      [[ -e "${DEDRM_ZIPS[0]}" ]] && echo "[DRY-RUN] would run: rm -f ${DEDRM_ZIPS[*]}"
      [[ -e "${DEDRM_DIRS[0]}" ]] && echo "[DRY-RUN] would run: rm -rf ${DEDRM_DIRS[*]}"
    else
      [[ -e "${DEDRM_ZIPS[0]}" ]] && rm -f "${DEDRM_ZIPS[@]}"
      [[ -e "${DEDRM_DIRS[0]}" ]] && rm -rf "${DEDRM_DIRS[@]}"
    fi
  else
    echo "  skipped — DeDRM_tools archive retained"
  fi
fi

KKF_ZIPS=("${DOWNLOADS_DIR}"/Kindle_Key_Finder_*.JH.zip)
if [[ -e "${KKF_ZIPS[0]}" ]]; then
  if ask_yn "Delete Kindle_Key_Finder zip from ${DOWNLOADS_DIR}/?"; then
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "[DRY-RUN] would run: rm -f ${KKF_ZIPS[*]}"
    else
      rm -f "${KKF_ZIPS[@]}"
    fi
  else
    echo "  skipped — Kindle_Key_Finder zip retained"
  fi
fi

# --- 6. Kindle for PC uninstall (--full only) ---
if [[ "${MODE}" == "full" ]]; then
  if [[ -f "${KINDLE_APP_DIR}/uninstall.exe" ]]; then
    cat <<'EOF'

  Kindle for PC uninstall is interactive (UAC + uninstaller wizard).
  This skill cannot drive that GUI. To uninstall:

    Option 1: %LOCALAPPDATA%\Amazon\Kindle\application\uninstall.exe
    Option 2: Settings → Apps → Amazon Kindle → Uninstall

  Note: uninstall typically clears %USERPROFILE%\Documents\My Kindle Content\.
  Your decrypted EPUBs in %USERPROFILE%\Calibre Library\ are NOT affected.
EOF
    echo
    if ask_yn "Open the uninstaller now?"; then
      run_or_show "'${KINDLE_APP_DIR}/uninstall.exe'"
    else
      echo "  skipped — Kindle for PC retained"
    fi
  fi
fi

# --- 7. Calibre plugin reminder (--full only) ---
if [[ "${MODE}" == "full" ]]; then
  cat <<EOF

  Calibre plugin removal is GUI-only. To complete cleanup:

    1. Open Calibre.
    2. Preferences → Plugins.
    3. Expand "File type plugins" — find DeDRM and KFX Input.
    4. Click each → Remove plugin.
    5. Restart Calibre.
    6. Optional: rm '${CALIBRE_PLUGINS_DIR}/dedrm.json'

  Calibre Library (decrypted EPUBs) is NEVER deleted by this skill.
EOF
  if [[ -f "${CALIBRE_PLUGINS_DIR}/dedrm.json" ]] && ask_yn "Delete Calibre's dedrm.json (key store)?"; then
    run_or_show "rm -f '${CALIBRE_PLUGINS_DIR}/dedrm.json'"
  fi
fi

echo
echo "=== cleanup complete ==="
echo
echo "Final state:"
bash "${SCRIPT_DIR}/status.sh" 2>/dev/null || true
