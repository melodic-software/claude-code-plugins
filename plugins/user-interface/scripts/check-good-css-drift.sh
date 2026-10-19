#!/usr/bin/env bash
# Drift check for the good-css files /user-interface:write-css absorbed or
# vendors. Run weekly by .github/workflows/maintenance-check-upstream-drift.yml;
# docs/upstream/good-css.md is the attribution and pin record.
#
# Read-only. Compares the blob SHA of each upstream file on the default branch
# with the SHA pinned below, and checks that each vendored copy still hashes
# (git hash-object) to its pin.
#
# Usage: check-good-css-drift.sh [--check | --help]
#
# Exit codes:
#   0  no drift
#   1  drift: an upstream file changed or is gone, or a vendored copy no longer matches
#   2  unverifiable (curl or git missing, network, auth or rate limit) or usage
#
# Tests source this file and replace fetch_blob_sha and PLUGIN_DIR.

set -uo pipefail

UPSTREAM_REPO="vojtaholik/good-css"
UPSTREAM_BRANCH="main"
PIN="92d436ba1937d1b1407c47e35abb3e199eaace2e"
# upstream path|pinned blob SHA|vendored copy under the plugin root (empty: absorbed only)
PINNED=(
  "scripts/check-css.mjs|6fa72714ba18cf02f698fa8015f63df043b3af85|skills/write-css/vendor/check-css.mjs"
  "LICENSE|66a325d82e56f2f41ebd14812517d6c50f5b66da|skills/write-css/vendor/LICENSE"
  "PRACTICES.md|b8a6cb6e6a30331d852e151504d2c7b5567dfc20|"
)
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

# Print the blob SHA of one upstream path on the default branch; return 3 when
# the path is gone (404), 1 when the API answers nothing usable. A token in
# GH_TOKEN or GITHUB_TOKEN raises the rate limit; none is needed for this
# public repository.
fetch_blob_sha() {
  local path="$1" body status sha
  local headers=(-H "Accept: application/vnd.github+json")
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  [[ -n "$token" ]] && headers+=(-H "Authorization: Bearer ${token}")
  body=$(curl -sS --max-time 30 -w '\n%{http_code}' "${headers[@]}" \
    "https://api.github.com/repos/${UPSTREAM_REPO}/contents/${path}?ref=${UPSTREAM_BRANCH}" 2>/dev/null) || return 1
  status="${body##*$'\n'}"
  [[ "$status" == 404 ]] && return 3
  [[ "$status" == 200 ]] || return 1
  body="${body%$'\n'*}"
  sha=$(printf '%s' "$body" | grep -oE '"sha"[[:space:]]*:[[:space:]]*"[0-9a-f]{40}"' | head -1 | grep -oE '[0-9a-f]{40}')
  [[ -n "$sha" ]] || return 1
  printf '%s' "$sha"
}

run_check() {
  local entry path pinned copy current status local_sha drift=0 fetch_failed=0

  section "Vendored copies vs pin"
  for entry in "${PINNED[@]}"; do
    IFS='|' read -r path pinned copy <<<"$entry"
    [[ -n "$copy" ]] || continue
    if ! local_sha=$(git hash-object "${PLUGIN_DIR}/${copy}" 2>/dev/null); then
      log "MISSING    ${copy}"
      drift=1
    elif [[ "$local_sha" == "$pinned" ]]; then
      log "unchanged  ${copy}"
    else
      log "MODIFIED   ${copy}  ${pinned} -> ${local_sha}"
      drift=1
    fi
  done

  section "Upstream ${UPSTREAM_REPO}@${UPSTREAM_BRANCH} vs pin ${PIN:0:12}"
  for entry in "${PINNED[@]}"; do
    IFS='|' read -r path pinned copy <<<"$entry"
    current=$(fetch_blob_sha "$path")
    status=$?
    if ((status == 3)); then
      log "GONE       ${path}  (deleted or renamed upstream)"
      drift=1
    elif ((status != 0)); then
      err "could not read the blob SHA of ${path} (network, auth or rate limit)"
      fetch_failed=1
    elif [[ "$current" == "$pinned" ]]; then
      log "unchanged  ${path}"
    else
      log "CHANGED    ${path}  ${pinned} -> ${current}"
      drift=1
    fi
  done

  section "Summary"
  if ((drift)); then
    log "Drift detected. Compare: https://github.com/${UPSTREAM_REPO}/compare/${PIN}...${UPSTREAM_BRANCH}"
    log "Re-audit per docs/upstream/good-css.md; restore or re-vendor a modified copy."
    return 1
  fi
  if ((fetch_failed)); then
    log "Unverifiable: at least one upstream file could not be read."
    return 2
  fi
  log "No drift. Upstream and vendored copies match pin ${PIN:0:12}."
  return 0
}

print_help() {
  cat <<'EOF'
Usage: check-good-css-drift.sh [--check | --help]

  --check  (default) Read-only: compare upstream blob SHAs of scripts/check-css.mjs,
           LICENSE and PRACTICES.md with the pinned ones, and the vendored copies
           under skills/write-css/vendor/ with their pins. Exit 0 no drift,
           1 drift, 2 unverifiable.
  --help   Show this message.
EOF
}

main() {
  case "${1:---check}" in
    -h | --help)
      print_help
      return 0
      ;;
    --check) ;;
    *)
      err "unknown mode: $1 (expected --check or --help)"
      return 2
      ;;
  esac
  local tool
  for tool in curl git; do
    command -v "$tool" >/dev/null 2>&1 || {
      err "$tool not on PATH"
      return 2
    }
  done
  run_check
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
