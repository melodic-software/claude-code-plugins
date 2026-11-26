#!/usr/bin/env bash
# Exit codes:
#   0  no drift
#   1  drift: a vendored copy no longer matches its pin, or is missing
#   2  unverifiable (git missing) or usage

set -uo pipefail

PINNED=(
  "6fa72714ba18cf02f698fa8015f63df043b3af85|skills/write-css/vendor/check-css.mjs"
  "66a325d82e56f2f41ebd14812517d6c50f5b66da|skills/write-css/vendor/LICENSE"
)
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

run_check() {
  local entry pinned copy local_sha drift=0

  for entry in "${PINNED[@]}"; do
    IFS='|' read -r pinned copy <<<"$entry"
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

  if ((drift)); then
    log "Drift detected: restore or re-vendor the copy per docs/upstream/good-css.md."
    return 1
  fi
  log "No drift. The vendored copies match their pinned blob SHAs."
  return 0
}

print_help() {
  cat <<'EOF'
Usage: check-good-css-drift.sh [--check | --help]

  --check  (default) Read-only: check that the vendored copies under
           skills/write-css/vendor/ still hash to their pinned blob SHAs.
           Exit 0 no drift, 1 drift, 2 unverifiable.
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
  command -v git >/dev/null 2>&1 || {
    err "git not on PATH"
    return 2
  }
  run_check
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
  exit $?
fi
