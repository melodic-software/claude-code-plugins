#!/usr/bin/env bash
# /firecrawl:update helper — drift detection and CLI upgrade for firecrawl-cli.
#
# Maintainer-facing: run against a working-tree checkout of this plugin (the
# marketplace clone, or a directory loaded via --plugin-dir), never against an
# installed marketplace copy — --apply rewrites UPSTREAM.md in the skill dir.
# Consumers receive updates through `/plugin marketplace update`.
#
# Modes:
#   --check  (default) read-only: report CLI version delta + upstream SKILL.md drift
#   --apply  run npm install -g firecrawl-cli@latest, then rewrite UPSTREAM.md
#            WITHOUT touching SKILL.md (Claude integrates upstream changes under
#            the skill body's Preservation rules; this script only owns the
#            deterministic parts — npm + metadata)
#
# Exit codes:
#   0  no drift OR apply completed successfully
#   1  drift detected in --check mode (no mutations)
#   2  prerequisite missing (curl/jq/npm) or network failure
#
# This script never calls `firecrawl init`, never installs the upstream bundled
# skills, and never writes upstream SKILL.md content to disk beyond a
# short-lived tmp fetch.

# No set -e — exit codes captured explicitly for a clean report.
set -uo pipefail

UPSTREAM_URL="https://www.firecrawl.dev/agent-onboarding/SKILL.md"
NPM_PKG="firecrawl-cli"
NPM_LATEST_URL="https://registry.npmjs.org/${NPM_PKG}/latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
UPSTREAM_MD="${SKILL_DIR}/UPSTREAM.md"
TMPDIR_RUN=$(mktemp -d -t firecrawl-update-XXXXXX)

cleanup() {
  rm -rf "$TMPDIR_RUN"
}
trap cleanup EXIT

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    err "$tool not on PATH — cannot continue"
    return 1
  fi
  return 0
}

check_prereqs() {
  local missing=0
  require_tool curl || missing=1
  require_tool jq || missing=1
  # sha256 is cross-platform: `sha256sum` on Linux/Git Bash, `shasum -a 256`
  # on stock macOS. Accept either — the `sha256` helper below picks one at
  # call time. Only fail when neither is available.
  if ! command -v sha256sum >/dev/null 2>&1 &&
    ! command -v shasum >/dev/null 2>&1; then
    err "neither sha256sum nor shasum on PATH — cannot hash upstream"
    missing=1
  fi
  [[ $missing -eq 0 ]] || exit 2
}

# Cross-platform SHA-256. Both emit `<hash>  <path>` on stdout, so the
# `awk '{print $1}'` caller works with either.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

# Current installed CLI version (empty if not installed).
current_cli_version() {
  if command -v firecrawl >/dev/null 2>&1; then
    firecrawl --version 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
  fi
}

# Latest published CLI version from npm registry (no auth required).
# `--fail` makes curl return non-zero on HTTP errors (404/5xx) instead of
# silently saving an error page body as if it were the real response.
latest_cli_version() {
  local body
  body=$(curl -sSL --fail --max-time 10 "$NPM_LATEST_URL" 2>/dev/null)
  [[ -n "$body" ]] || return 1
  printf '%s' "$body" | jq -r '.version // empty'
}

# Fetch upstream SKILL.md to TMPDIR_RUN and emit SHA256.
# `--fail` is critical: without it, an HTTP 404/503 error page body would be
# saved to $out and hashed as if it were the real SKILL.md, silently poisoning
# UPSTREAM.md on --apply and masking real drift on --check.
fetch_upstream_sha() {
  local out="${TMPDIR_RUN}/upstream-skill.md"
  if ! curl -sSL --fail --max-time 15 "$UPSTREAM_URL" -o "$out" 2>/dev/null; then
    return 1
  fi
  [[ -s "$out" ]] || return 1
  sha256 "$out" | awk '{print $1}'
}

# Read the last field of a `- <Label>: <value>` line from UPSTREAM.md
# (empty if the file or the line is absent — i.e. never synced).
recorded_field() {
  [[ -f "$UPSTREAM_MD" ]] || return 0
  grep -m1 "^- $1:" "$UPSTREAM_MD" | awk '{print $NF}'
}

recorded_upstream_sha() { recorded_field 'Upstream SHA256'; }
recorded_cli_version() { recorded_field 'CLI version at sync'; }

run_check() {
  local current latest upstream_sha recorded_sha recorded_ver drift=0

  section "CLI version"
  current=$(current_cli_version)
  latest=$(latest_cli_version) || {
    err "failed to reach npm registry — network or proxy issue"
    return 2
  }
  recorded_ver=$(recorded_cli_version)

  if [[ -z "$current" ]]; then
    log "installed:  NOT INSTALLED"
    drift=1
  else
    log "installed:  $current"
  fi
  log "latest:     $latest"
  [[ -n "$recorded_ver" ]] && log "last sync:  $recorded_ver"

  if [[ -n "$current" && "$current" != "$latest" ]]; then
    log "→ CLI upgrade available: $current → $latest"
    drift=1
  elif [[ -n "$current" && "$current" == "$latest" ]]; then
    log "→ CLI at latest"
  fi

  section "Upstream SKILL.md"
  upstream_sha=$(fetch_upstream_sha) || {
    err "failed to fetch upstream SKILL.md from $UPSTREAM_URL"
    return 2
  }
  recorded_sha=$(recorded_upstream_sha)

  log "fetched SHA256:  $upstream_sha"
  if [[ -z "$recorded_sha" ]]; then
    log "recorded SHA256: (never synced — first run)"
    drift=1
  else
    log "recorded SHA256: $recorded_sha"
    if [[ "$upstream_sha" == "$recorded_sha" ]]; then
      log "→ upstream unchanged"
    else
      log "→ upstream content changed since last sync"
      drift=1
    fi
  fi

  section "Summary"
  if [[ $drift -eq 0 ]]; then
    log "No drift. CLI and skill are in sync with upstream."
    return 0
  fi
  log "Drift detected. Run '/firecrawl:update' (without --check) to apply."
  log "Script alone cannot rewrite SKILL.md — that's Claude's integration step,"
  log "governed by this update skill's SKILL.md Preservation rules."
  return 1
}

run_apply() {
  local current latest upstream_sha previous_ver

  previous_ver=$(current_cli_version)
  latest=$(latest_cli_version) || {
    err "failed to reach npm registry"
    return 2
  }

  section "npm install -g ${NPM_PKG}@latest"
  if ! npm install -g "${NPM_PKG}@latest"; then
    err "npm install failed — rollback: npm install -g ${NPM_PKG}@${previous_ver:-<previous>}"
    return 2
  fi

  section "Post-install verification"
  current=$(current_cli_version)
  if [[ -z "$current" ]]; then
    err "firecrawl not on PATH after install — check npm global bin"
    return 2
  fi
  log "installed: $current (was: ${previous_ver:-none})"
  firecrawl --status 2>&1 | head -10 || true

  section "Upstream sync"
  upstream_sha=$(fetch_upstream_sha) || {
    err "failed to fetch upstream SKILL.md"
    return 2
  }
  log "new upstream SHA256: $upstream_sha"

  # Rewrite UPSTREAM.md. Claude does NOT run this section — update.sh writes
  # the deterministic record. SKILL.md content integration is a separate step
  # handled by the skill body (Preservation rules).
  rewrite_upstream_md "$upstream_sha" "$current" "$previous_ver"
  log "UPSTREAM.md refreshed"

  section "Next step"
  log "Now invoke the skill's Gate-2 integration: review the upstream SKILL.md"
  log "changes (diff against the tmp-fetched content) and integrate under the"
  log "Preservation rules. See this update skill's SKILL.md."
  return 0
}

rewrite_upstream_md() {
  local sha="$1" ver="$2" prev="$3"
  local today
  today=$(date -u +%Y-%m-%d)
  cat >"$UPSTREAM_MD" <<EOF
<!-- firecrawl update state — do not edit by hand. -->
<!-- Written by the skill's scripts/update.sh --apply. -->

# Firecrawl skill upstream sync state

- Last sync: ${today}
- Upstream URL: ${UPSTREAM_URL}
- Upstream SHA256: ${sha}
- CLI version at sync: ${ver}
- Previous CLI version (rollback target): ${prev:-none}
- CLI npm URL: https://www.npmjs.com/package/${NPM_PKG}
- Next recheck: run the update action with --check weekly or when a scrape
  fails unexpectedly. Script alone never rewrites SKILL.md — Claude integrates
  upstream content under SKILL.md Preservation rules.
EOF
}

main() {
  local mode="${1:---check}"

  if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
    err "SKILL.md not found at ${SKILL_DIR} — run from a plugin checkout"
    exit 2
  fi

  case "$mode" in
  -h | --help)
    cat <<'EOF'
Usage: update.sh [--check | --apply | --help]

Drift-check + upgrade helper for the firecrawl plugin skill. Maintainer-
facing: run in a working-tree checkout of the plugin, not an installed copy.

  --check  (default) Read-only drift report: CLI version delta + upstream SHA delta.
           Exit 0 if in sync, 1 if drift detected, 2 on prerequisite/network error.

  --apply  Run npm install -g firecrawl-cli@latest and refresh UPSTREAM.md.
           Does NOT rewrite SKILL.md — that's Claude's integration step, governed
           by SKILL.md Preservation rules.

  --help   Show this message.
EOF
    exit 0
    ;;
  *) ;; # other modes handled below after prerequisite checks
  esac

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
