#!/usr/bin/env bash
# status.sh — emit current state of the kindle-dedrm workflow as JSON.
# Read by SKILL.md pre-computed-context block + by `status` action.
# Idempotent, read-only — no mutations.

# shellcheck disable=SC2154
# (Windows env vars LOCALAPPDATA/USERPROFILE/APPDATA are set on Git Bash runtime)

set -uo pipefail

# Resolve paths via Windows env vars (Git Bash translates these).
KINDLE_APP_DIR="${LOCALAPPDATA}/Amazon/Kindle/application"
KINDLE_UPDATES_DIR="${LOCALAPPDATA}/Amazon/Kindle/updates"
KINDLE_CONTENT_DIR="${USERPROFILE}/Documents/My Kindle Content"
CALIBRE_LIBRARY_DIR="${USERPROFILE}/Calibre Library"
CALIBRE_PLUGINS_DIR="${APPDATA}/calibre/plugins"
KEY_FINDER_DIR="${HOME}/Tools/Kindle_Key_Finder"
DOWNLOADS_DIR="${HOME}/Downloads"
FIREWALL_RULE_NAME="Block Kindle for PC (lock 2.8.0)"

# --- Probes ---

probe_kindle_version() {
  if [[ -f "${KINDLE_APP_DIR}/Kindle.exe" ]]; then
    powershell.exe -NoProfile -Command "(Get-Item 'C:\\Users\\${USERNAME}\\AppData\\Local\\Amazon\\Kindle\\application\\Kindle.exe').VersionInfo.FileVersion" 2>/dev/null | tr -d '\r\n '
  fi
}

probe_firewall_rule() {
  powershell.exe -NoProfile -Command "if (Get-NetFirewallRule -DisplayName '${FIREWALL_RULE_NAME}' -ErrorAction SilentlyContinue) { (Get-NetFirewallRule -DisplayName '${FIREWALL_RULE_NAME}').Enabled } else { 'absent' }" 2>/dev/null | tr -d '\r\n '
}

probe_icacls_deny() {
  if [[ ! -d "${KINDLE_UPDATES_DIR}" ]]; then
    echo "n/a-no-dir"
    return
  fi
  if powershell.exe -NoProfile -Command "icacls 'C:\\Users\\${USERNAME}\\AppData\\Local\\Amazon\\Kindle\\updates'" 2>/dev/null | grep -q '(DENY)(W)'; then
    echo "applied"
  else
    echo "absent"
  fi
}

probe_cached_installer() {
  if [[ -f "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" ]]; then
    local size_bytes
    size_bytes=$(stat -c%s "${KINDLE_UPDATES_DIR}/KindleForPC-installer.exe" 2>/dev/null || echo 0)
    echo "present-${size_bytes}b"
  else
    echo "absent"
  fi
}

probe_key_finder() {
  if [[ -d "${KEY_FINDER_DIR}" && -f "${KEY_FINDER_DIR}/Run_keyfinder_admin.vbs" ]]; then
    echo "installed"
  else
    echo "absent"
  fi
}

probe_downloads() {
  local found=0
  local dedrm_zip kkf_zip
  [[ -f "${DOWNLOADS_DIR}/KindleForPC-installer-2.8.70980.exe" ]] && found=$((found + 1))
  dedrm_zip=("${DOWNLOADS_DIR}"/DeDRM_tools-*.zip)
  [[ -e ${dedrm_zip[0]} ]] && found=$((found + 1))
  kkf_zip=("${DOWNLOADS_DIR}"/Kindle_Key_Finder_*.JH.zip)
  [[ -e ${kkf_zip[0]} ]] && found=$((found + 1))
  echo "${found}/3"
}

probe_calibre_plugins() {
  if [[ ! -d "${CALIBRE_PLUGINS_DIR}" ]]; then
    echo "calibre-not-found"
    return
  fi
  local has_dedrm has_kfx has_dedrm_json
  local dedrm_match kfx_match
  dedrm_match=("${CALIBRE_PLUGINS_DIR}"/*[Dd]e[Dd][Rr][Mm]*)
  kfx_match=("${CALIBRE_PLUGINS_DIR}"/*KFX*)
  has_dedrm=$([[ -e ${dedrm_match[0]} ]] && echo 1 || echo "")
  has_kfx=$([[ -e ${kfx_match[0]} ]] && echo 1 || echo "")
  has_dedrm_json=$([[ -f "${CALIBRE_PLUGINS_DIR}/dedrm.json" ]] && echo 1 || echo 0)
  echo "dedrm=$([[ -n $has_dedrm ]] && echo present || echo absent),kfx=$([[ -n $has_kfx ]] && echo present || echo absent),dedrm.json=$([[ "$has_dedrm_json" == 1 ]] && echo present || echo absent)"
}

probe_book_count() {
  local synced converted
  # shellcheck disable=SC2010
  # (ls|grep used for filename-pattern count; entries are Amazon-generated _EBOK dirs without spaces)
  synced=$(ls "${KINDLE_CONTENT_DIR}" 2>/dev/null | grep -c "_EBOK")
  converted=$(find "${CALIBRE_LIBRARY_DIR}" -name "*.epub" 2>/dev/null | grep -vc "Quick Start")
  echo "synced=${synced},converted=${converted}"
}

# --- Compose JSON ---

cat <<EOF
{
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "kindle": {
    "installed": $([[ -f "${KINDLE_APP_DIR}/Kindle.exe" ]] && echo true || echo false),
    "version": "$(probe_kindle_version)",
    "expected": "2.8.0.70980"
  },
  "firewall_rule": "$(probe_firewall_rule)",
  "icacls_deny": "$(probe_icacls_deny)",
  "cached_installer": "$(probe_cached_installer)",
  "key_finder": "$(probe_key_finder)",
  "downloads": "$(probe_downloads)",
  "calibre_plugins": "$(probe_calibre_plugins)",
  "books": "$(probe_book_count)"
}
EOF
