#!/usr/bin/env bash

# shellcheck disable=SC2154

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE="confirm"
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
CACHED_INSTALLER="${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe"
KFC_DOWNLOAD="${DOWNLOADS_DIR}/KindleForPC-installer-2.8.70980.exe"
DEDRM_JSON="${CALIBRE_PLUGINS_DIR}/dedrm.json"

ask_yn() {
  local prompt="$1"
  case "${MODE}:${prompt}" in
  soft:*"firewall"* | soft:*"ICACLS"* | soft:*"Kindle for PC uninstall"* | soft:*"Calibre plugin"*) return 1 ;;
  full:*"Calibre Library"*) return 1 ;;
  *) ;;
  esac
  echo
  read -r -p "${prompt} [y/N]: " ans
  local answer="${ans,,}"
  [[ "${answer}" == "y" || "${answer}" == "yes" ]]
}

run_or_show() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] would run: $*"
  else
    # shellcheck disable=SC2294
    eval "$@"
  fi
}

rm_or_show() {
  local flags="$1"
  shift
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "[DRY-RUN] would run: rm ${flags} $*"
  else
    rm "${flags}" "$@"
  fi
}

echo "=== kindle-dedrm: cleanup (mode=${MODE}, dry-run=${DRY_RUN}) ==="
echo
echo "Reversal walkthrough. Each item is confirmed independently."
echo "The user's Calibre Library (decrypted EPUBs) is never offered for deletion."
echo

if [[ "${MODE}" != "soft" ]]; then
  if ask_yn "Remove firewall rule 'Block Kindle for PC (lock 2.8.0)'?"; then
    run_or_show "pwsh -NoProfile -File '${SCRIPT_DIR}/firewall.ps1' -Action remove"
  else
    echo "  skipped — firewall rule retained"
  fi

  if ask_yn "Remove ICACLS deny on ${KINDLE_UPDATES_DIR}?"; then
    run_or_show "bash '${SCRIPT_DIR}/lock-updates.sh' remove"
  else
    echo "  skipped — ICACLS deny retained"
  fi
fi

if [[ -f "${CACHED_INSTALLER}" ]]; then
  if ask_yn "Delete cached installer at ${CACHED_INSTALLER}?"; then
    run_or_show "rm -f '${CACHED_INSTALLER}'"
  else
    echo "  skipped — cached installer retained"
  fi
fi

if [[ -d "${KEY_FINDER_DIR}" ]]; then
  if ask_yn "Delete ${KEY_FINDER_DIR}/ (key finder + saved config + extracted keys)?"; then
    run_or_show "rm -rf '${KEY_FINDER_DIR}'"
  else
    echo "  skipped — keyfinder retained"
  fi
fi

if [[ -f "${KFC_DOWNLOAD}" ]]; then
  if ask_yn "Delete ${KFC_DOWNLOAD}?"; then
    run_or_show "rm -f '${KFC_DOWNLOAD}'"
  else
    echo "  skipped — installer retained (useful for re-setup if Amazon revokes URL)"
  fi
fi

DEDRM_ZIPS=("${DOWNLOADS_DIR}"/DeDRM_tools-v*.zip)
DEDRM_DIRS=("${DOWNLOADS_DIR}"/DeDRM_tools-v*/)
if [[ -e "${DEDRM_ZIPS[0]}" || -e "${DEDRM_DIRS[0]}" ]]; then
  if ask_yn "Delete DeDRM_tools zip + extracted dir from ${DOWNLOADS_DIR}/?"; then
    [[ -e "${DEDRM_ZIPS[0]}" ]] && rm_or_show -f "${DEDRM_ZIPS[@]}"
    [[ -e "${DEDRM_DIRS[0]}" ]] && rm_or_show -rf "${DEDRM_DIRS[@]}"
  else
    echo "  skipped — DeDRM_tools archive retained"
  fi
fi

KKF_ZIPS=("${DOWNLOADS_DIR}"/Kindle_Key_Finder_*.JH.zip)
if [[ -e "${KKF_ZIPS[0]}" ]]; then
  if ask_yn "Delete Kindle_Key_Finder zip from ${DOWNLOADS_DIR}/?"; then
    rm_or_show -f "${KKF_ZIPS[@]}"
  else
    echo "  skipped — Kindle_Key_Finder zip retained"
  fi
fi

if [[ "${MODE}" == "full" ]]; then
  if [[ -f "${KINDLE_APP_DIR}/uninstall.exe" ]]; then
    cat <<'EOF'

  Kindle for PC uninstall is interactive (UAC + uninstaller wizard).
  This skill cannot drive that GUI. To uninstall:

    Option 1: %LOCALAPPDATA%\Amazon\Kindle\application\uninstall.exe
    Option 2: Settings → Apps → Amazon Kindle → Uninstall

  Note: uninstall typically clears %USERPROFILE%\Documents\My Kindle Content\.
  Your decrypted EPUBs in %USERPROFILE%\Calibre Library\ are not affected.
EOF
    echo
    if ask_yn "Open the uninstaller now?"; then
      run_or_show "'${KINDLE_APP_DIR}/uninstall.exe'"
    else
      echo "  skipped — Kindle for PC retained"
    fi
  fi

  cat <<EOF

  Calibre plugin removal is GUI-only. To complete cleanup:

    1. Open Calibre.
    2. Preferences → Plugins.
    3. Expand "File type plugins" — find DeDRM and KFX Input.
    4. Click each → Remove plugin.
    5. Restart Calibre.
    6. Optional: rm '${DEDRM_JSON}'

  Calibre Library (decrypted EPUBs) is never deleted by this skill.
EOF
  if [[ -f "${DEDRM_JSON}" ]] && ask_yn "Delete Calibre's dedrm.json (key store)?"; then
    run_or_show "rm -f '${DEDRM_JSON}'"
  fi
fi

echo
echo "=== cleanup complete ==="
echo
echo "Final state:"
bash "${SCRIPT_DIR}/status.sh" 2>/dev/null || true
