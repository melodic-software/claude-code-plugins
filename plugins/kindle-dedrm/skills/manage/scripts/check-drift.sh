#!/usr/bin/env bash
# check-drift.sh — drift report against captured baselines in references/.
# Walks every upstream source listed in references/sources.md and reports
# OK / STALE / UNREACHABLE for each. No mutations.
#
# Usage: check-drift.sh

set -uo pipefail

# Captured pins — parsed from references/versions.md (single source of truth;
# a re-pin edits that file once and this script follows). Parsing is fail-hard:
# a pin this script cannot read is a pin it must not silently skip verifying.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_MD="${SCRIPT_DIR}/../references/versions.md"
SOURCES_MD="${SCRIPT_DIR}/../references/sources.md"

# pin <file> <section-heading> <row-label> — value of `| label | `value` |`
# within the named "## section", first match wins.
pin() {
  local file="$1" section="$2" label="$3" value
  value=$(awk -v sec="## ${section}" -v lab="${label}" '
    $0 == sec { insec = 1; next }
    insec && /^## / { exit }
    insec && $0 ~ "^\\| " lab " \\|" {
      if (match($0, /`[^`]+`/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
    }' "${file}" | tr -d '\r')
  if [[ -z "${value}" ]]; then
    echo "check-drift: cannot parse pin '${label}' (section '${section}') from ${file}" >&2
    exit 2
  fi
  printf '%s' "${value}"
}

PINNED_KFC_URL="$(pin "${VERSIONS_MD}" "Kindle for PC" "Installer URL")"
PINNED_KFC_SHA="$(pin "${VERSIONS_MD}" "Kindle for PC" "SHA256")"

PINNED_DEDRM_TAG="$(pin "${VERSIONS_MD}" "DeDRM_tools (Satsuoni fork)" "Pinned tag")"
PINNED_DEDRM_SHA="$(pin "${VERSIONS_MD}" "DeDRM_tools (Satsuoni fork)" "SHA256")"

PINNED_KKF_FILENAME="$(pin "${VERSIONS_MD}" "Kindle_Key_Finder (techy-notes.com)" "Pinned filename")"
PINNED_KKF_URL="$(pin "${VERSIONS_MD}" "Kindle_Key_Finder (techy-notes.com)" "Captured URL")"
PINNED_KKF_SHA="$(pin "${VERSIONS_MD}" "Kindle_Key_Finder (techy-notes.com)" "SHA256")"

PINNED_TUTORIAL_URL="$(grep -oE 'https://techy-notes\.com/[a-z0-9-]+/' "${SOURCES_MD}" | head -1)"
if [[ -z "${PINNED_TUTORIAL_URL}" ]]; then
  echo "check-drift: cannot parse tutorial URL from ${SOURCES_MD}" >&2
  exit 2
fi

ok() { echo "  [OK]      $*"; }
stale() { echo "  [STALE]   $*"; }
unreachable() { echo "  [UNREACH] $*"; }
note() { echo "            $*"; }

echo "=== kindle-dedrm: drift report ==="
echo
echo "Captured baselines from references/versions.md (see each row's Captured date)."
echo

# --- Source 1: Kindle for PC installer URL ---
echo "Kindle for PC installer:"
HTTP=$(curl -sI -o /dev/null -w "%{http_code}" "${PINNED_KFC_URL}" 2>/dev/null || echo "000")
case "${HTTP}" in
200) ok "${PINNED_KFC_URL} → HTTP 200 (URL still serving 2.8.0.70980)" ;;
403 | 404)
  unreachable "${PINNED_KFC_URL} → HTTP ${HTTP} (Amazon may have revoked)"
  note "Find alternate mirror — see references/sources.md 'How to add a new source'"
  ;;
000) unreachable "${PINNED_KFC_URL} → no response (network or DNS issue)" ;;
*) stale "${PINNED_KFC_URL} → HTTP ${HTTP} (unexpected)" ;;
esac
echo

# --- Source 2: DeDRM_tools latest pre-release ---
echo "DeDRM_tools (Satsuoni fork) latest pre-release:"
LATEST_TAG=$(gh api repos/Satsuoni/DeDRM_tools/releases --jq '[.[] | select(.prerelease == true)][0].tag_name' 2>/dev/null || echo "")
if [[ -z "${LATEST_TAG}" ]]; then
  unreachable "gh api Satsuoni/DeDRM_tools/releases → no response (network, gh auth, or repo gone)"
elif [[ "${LATEST_TAG}" == "${PINNED_DEDRM_TAG}" ]]; then
  ok "latest pre-release ${LATEST_TAG} == pinned ${PINNED_DEDRM_TAG}"
else
  stale "latest pre-release ${LATEST_TAG} != pinned ${PINNED_DEDRM_TAG}"
  note "Update references/versions.md DeDRM section, re-fetch DeDRM_tools.zip, recompute SHA256"
fi
echo

# --- Source 3: Kindle_Key_Finder zip — HEAD the pinned direct URL ---
# Roll-forward auto-discovery via the tutorial article body is dead: the
# article moved and is now subscriber-gated (see references/sources.md), so its
# public body carries no zip link. HEAD the pinned direct URL as the
# authoritative signal — a non-200 means the author revoked or rolled it, at
# which point a subscriber must read the current article and re-pin by hand.
echo "Kindle_Key_Finder zip (pinned direct URL — article-body discovery paywalled):"
KKF_HTTP=$(curl -sI -o /dev/null -w "%{http_code}" "${PINNED_KKF_URL}" 2>/dev/null || echo "000")
case "${KKF_HTTP}" in
200) ok "${PINNED_KKF_URL} → HTTP 200 (${PINNED_KKF_FILENAME} still served)" ;;
403 | 404)
  stale "${PINNED_KKF_URL} → HTTP ${KKF_HTTP} (revoked or rolled forward)"
  note "Subscriber must read the current techy-notes article for the new zip URL, then re-pin references/versions.md + recompute SHA256"
  ;;
000) unreachable "${PINNED_KKF_URL} → no response (network or DNS issue)" ;;
*) stale "${PINNED_KKF_URL} → HTTP ${KKF_HTTP} (unexpected)" ;;
esac
echo

# --- Source 4: Tutorial article reachability (informational) ---
# The article is subscriber-gated, so no body diff is possible; a HEAD probe
# just confirms the current slug still resolves. A 404 here means the author
# moved or unpublished the page again — re-discover via the site sitemap.
echo "Tutorial article (techy-notes.com — subscriber-gated):"
ART_HTTP=$(curl -sI -o /dev/null -w "%{http_code}" "${PINNED_TUTORIAL_URL}" 2>/dev/null || echo "000")
case "${ART_HTTP}" in
200) note "${PINNED_TUTORIAL_URL} → HTTP 200 (slug resolves; body paywalled, not diffable)" ;;
000) unreachable "${PINNED_TUTORIAL_URL} → no response" ;;
*)
  stale "${PINNED_TUTORIAL_URL} → HTTP ${ART_HTTP} (article moved again)"
  note "Re-discover via https://techy-notes.com/sitemap-posts.xml, update references/sources.md"
  ;;
esac
echo

# --- Source 5: Local download SHAs ---
echo "Local downloads (verify SHA256 if files present):"
DL_DIR="${HOME}/Downloads"
verify_sha() {
  local path="$1" expected="$2" label="$3"
  if [[ -f "${path}" ]]; then
    local actual
    actual=$(sha256sum "${path}" | awk '{print $1}')
    if [[ "${actual}" == "${expected}" ]]; then
      ok "${label} SHA matches"
    else
      stale "${label} SHA differs"
      note "  expected: ${expected}"
      note "  actual:   ${actual}"
    fi
  else
    note "  ${label}: not present at ${path}"
  fi
}
verify_sha "${DL_DIR}/$(basename "${PINNED_KFC_URL}")" "${PINNED_KFC_SHA}" "KindleForPC installer"
KKF_MATCHES=("${DL_DIR}"/Kindle_Key_Finder_*.JH.zip)
KKF_LOCAL="${KKF_MATCHES[0]}"
[[ -e "${KKF_LOCAL}" ]] && verify_sha "${KKF_LOCAL}" "${PINNED_KKF_SHA}" "Kindle_Key_Finder zip"
DEDRM_MATCHES=("${DL_DIR}"/DeDRM_tools-"${PINNED_DEDRM_TAG}".zip)
DEDRM_LOCAL="${DEDRM_MATCHES[0]}"
[[ -e "${DEDRM_LOCAL}" ]] && verify_sha "${DEDRM_LOCAL}" "${PINNED_DEDRM_SHA}" "DeDRM_tools zip"

echo
echo "=== End drift report ==="
echo
echo "Action items: address any [STALE] or [UNREACH] entries by updating"
echo "references/versions.md + references/sources.md, then re-running the relevant"
echo "portion of setup."
