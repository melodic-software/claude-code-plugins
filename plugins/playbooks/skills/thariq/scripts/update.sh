#!/usr/bin/env bash
# /playbooks:update (thariq pack) — drift detection + vendor sync.
#
# Maintainer-facing: run against a working-tree checkout of this plugin (the
# marketplace clone, or a directory loaded via --plugin-dir), never against an
# installed marketplace copy. Consumers receive updates through
# `/plugin marketplace update`.
#
# Modes:
#   --check  (default) read-only: report upstream version + vendor SHA delta
#   --apply  fetch latest upstream, replace vendor/SKILL.md verbatim, bump
#            frontmatter metadata (upstream-version + synced). Does NOT
#            rewrite the distilled SKILL.md body — integration is a manual,
#            reviewed step (the update action is advisory).
#
# Exit codes:
#   0  no drift OR --apply completed successfully
#   1  drift detected in --check mode (no mutations)
#   2  prerequisite missing (curl) or network failure
#
# Idempotency: re-running --check on a no-drift state produces identical output.
# Upstream version is read from the remote file's own YAML frontmatter
# `version:` field (no separate version API).

# No set -e — exit codes captured explicitly for a clean report.
set -uo pipefail

INSTALL_URL="https://howborisusesclaudecode.com/api/install-thariq"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FRONTMATTER_FILE="${SKILL_DIR}/SKILL.md"
VENDOR_FILE="${SKILL_DIR}/vendor/SKILL.md"
TMPDIR_RUN=$(mktemp -d -t thariq-update-XXXXXX)

cleanup() {
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

check_prereqs() {
  local missing=0
  if ! command -v curl >/dev/null 2>&1; then
    err "curl not on PATH — cannot continue"
    missing=1
  fi
  if ! command -v sha256sum >/dev/null 2>&1 &&
    ! command -v shasum >/dev/null 2>&1; then
    err "neither sha256sum nor shasum on PATH — cannot hash upstream"
    missing=1
  fi
  [[ $missing -eq 0 ]] || exit 2
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

# Read nested metadata.<field> from the local SKILL.md frontmatter.
local_metadata_field() {
  local field="$1"
  [[ -f "$FRONTMATTER_FILE" ]] || return 0
  awk -v f="$field" '/^metadata:/{m=1;next} m && /^[a-zA-Z]/{m=0} m && $1 == f":"{print $2;exit}' \
    "$FRONTMATTER_FILE" | tr -d '"' | tr -d "'" | tr -d '\r'
}

# Read top-level version: from a fetched upstream file's frontmatter block.
upstream_version_from_file() {
  awk 'NR==1 && /^---/{f=1;next} f && /^---/{exit} f && /^version:/{print $2;exit}' "$1" |
    tr -d '"' | tr -d "'" | tr -d '\r'
}

fetch_upstream() {
  local out="${TMPDIR_RUN}/upstream-skill.md"
  curl -sSL --fail --max-time 30 "$INSTALL_URL" -o "$out" 2>/dev/null || return 1
  [[ -s "$out" ]] || return 1
  printf '%s' "$out"
}

file_sha() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  sha256 "$path" | awk '{print $1}' | tr -d '\r'
}

replace_metadata_field() {
  local field="$1" value="$2" tmp="${TMPDIR_RUN}/skill.md.tmp"
  # Escape chars special on sed's replacement side (& \ and the | delimiter) so
  # an upstream version string with metacharacters can't mangle the file.
  local value_safe
  value_safe=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')
  sed -E "s|^([[:space:]]+${field}:[[:space:]]+).*\$|\\1${value_safe}|" \
    "$FRONTMATTER_FILE" >"$tmp"
  mv "$tmp" "$FRONTMATTER_FILE"
}

run_check() {
  local local_ver upstream_md upstream_ver upstream_sha vendor_sha drift=0

  section "Frontmatter / upstream version"
  local_ver=$(local_metadata_field "upstream-version")
  upstream_md=$(fetch_upstream) || {
    err "failed to fetch $INSTALL_URL — network or DNS issue"
    return 2
  }
  upstream_ver=$(upstream_version_from_file "$upstream_md")

  log "local:     ${local_ver:-<unset>}"
  log "upstream:  ${upstream_ver:-<unset>}"
  if [[ -z "$local_ver" ]]; then
    log "→ frontmatter metadata.upstream-version missing"
    drift=1
  elif [[ -n "$upstream_ver" && "$local_ver" != "$upstream_ver" ]]; then
    log "→ version drift: $local_ver → $upstream_ver"
    drift=1
  else
    log "→ version match"
  fi

  section "vendor/SKILL.md SHA"
  upstream_sha=$(file_sha "$upstream_md")
  vendor_sha=$(file_sha "$VENDOR_FILE")
  log "vendor SHA256:   ${vendor_sha:-<missing>}"
  log "upstream SHA256: $upstream_sha"
  if [[ -z "$vendor_sha" ]]; then
    log "→ vendor/SKILL.md missing — first sync"
    drift=1
  elif [[ "$upstream_sha" == "$vendor_sha" ]]; then
    log "→ vendor content matches upstream byte-for-byte"
  else
    log "→ vendor content drift (bytes differ)"
    drift=1
  fi

  section "Summary"
  if [[ $drift -eq 0 ]]; then
    log "No drift. thariq pack in sync with upstream v${upstream_ver}."
    return 0
  fi
  log "Drift detected. Run '/playbooks:update --apply' to sync vendor + frontmatter."
  log "Manual integration into the distilled SKILL.md body is required after --apply."
  return 1
}

run_apply() {
  local prev_ver prev_synced upstream_md upstream_ver upstream_sha vendor_sha today

  section "Pre-state"
  prev_ver=$(local_metadata_field "upstream-version")
  prev_synced=$(local_metadata_field "synced")
  log "previous metadata.upstream-version: ${prev_ver:-<unset>}"
  log "previous metadata.synced:           ${prev_synced:-<unset>}"

  section "Fetch upstream"
  upstream_md=$(fetch_upstream) || {
    err "failed to fetch $INSTALL_URL"
    return 2
  }
  upstream_ver=$(upstream_version_from_file "$upstream_md")
  upstream_sha=$(file_sha "$upstream_md")
  log "upstream version: ${upstream_ver:-<unset>}"
  log "upstream SHA256:  $upstream_sha"

  vendor_sha=$(file_sha "$VENDOR_FILE")
  if [[ "$upstream_sha" == "$vendor_sha" && "$prev_ver" == "$upstream_ver" ]]; then
    log "Nothing to do — vendor + frontmatter already match upstream v${upstream_ver}."
    return 0
  fi

  section "Replace vendor/SKILL.md"
  mkdir -p "$(dirname "$VENDOR_FILE")"
  cp "$upstream_md" "$VENDOR_FILE"
  log "vendor/SKILL.md replaced ($(wc -c <"$VENDOR_FILE" | tr -d ' \r') bytes)"

  section "Bump frontmatter metadata"
  today=$(date -u +%Y-%m-%d)
  replace_metadata_field "upstream-version" "${upstream_ver:-$prev_ver}"
  replace_metadata_field "synced" "$today"
  log "metadata.upstream-version: ${prev_ver:-<unset>} → ${upstream_ver:-<unchanged>}"
  log "metadata.synced:           ${prev_synced:-<unset>} → $today"

  section "Manual next steps"
  log "1. Diff the vendor baseline against prior HEAD to surface changed guidance:"
  log "     git diff HEAD -- \"$VENDOR_FILE\""
  log "2. Integrate deltas into the distilled SKILL.md body (preserve its framing)."
  log "3. Bump the playbooks plugin version in its .claude-plugin/plugin.json so consumers update."
  log "4. Commit: chore(playbooks): sync thariq pack to upstream v${upstream_ver}"
  return 0
}

print_help() {
  cat <<'EOF'
Usage: update.sh [--check | --apply | --help]

Vendor-backed update helper for the thariq pack (playbooks plugin). Maintainer-
facing: run in a working-tree checkout of the plugin, not an installed copy.

  --check  (default) Read-only drift report: upstream frontmatter version +
           SHA delta vs vendor/SKILL.md. Exit 0 in sync, 1 drift, 2 prereq/network.

  --apply  Fetch latest upstream, replace vendor/SKILL.md verbatim, bump
           frontmatter metadata (upstream-version + synced). Distilled-body
           integration stays a manual step.

  --help   Show this message.

Source: https://howborisusesclaudecode.com/api/install-thariq
EOF
}

main() {
  local mode="${1:---check}"

  case "$mode" in
  -h | --help)
    print_help
    exit 0
    ;;
  *) ;; # other modes handled below after prerequisite checks
  esac

  if [[ ! -f "$FRONTMATTER_FILE" ]]; then
    err "SKILL.md not found at $FRONTMATTER_FILE — run from a plugin checkout"
    exit 2
  fi

  check_prereqs

  case "$mode" in
  --check)
    run_check
    ;;
  --apply)
    run_apply
    ;;
  *)
    err "unknown mode: $mode (expected --check, --apply, or --help)"
    exit 2
    ;;
  esac
}

# Source-guard: only run main when executed directly, not when sourced (tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
