#!/usr/bin/env bash
# /firecrawl:update helper — drift detection and CLI upgrade for firecrawl-cli.
#
# Maintainer-facing: run against a working-tree checkout of this plugin (the
# marketplace clone, or a directory loaded via --plugin-dir), never against an
# installed marketplace copy — --apply and --record-upstream rewrite upstream.md
# in the skill dir.
# Consumers receive updates through `/plugin marketplace update`.
#
# Modes:
#   --check  (default) read-only: report CLI version delta + upstream SKILL.md drift
#   --apply  run npm install -g firecrawl-cli@latest and turn off the CLI's
#            background self-update (firecrawl update --disable-auto), then record the CLI version
#            and rollback target in upstream.md, keeping the recorded upstream SHA,
#            WITHOUT touching SKILL.md (Claude integrates upstream changes under
#            the skill body's Preservation rules; this script only owns the
#            deterministic parts — npm + metadata)
#   --record-upstream  record the fetched upstream SHA in upstream.md, installing
#            nothing; run only after Gate 2 or with no content delta, so a declined
#            or abandoned integration keeps showing as drift in --check
#
# Exit codes (the shared drift-check contract):
#   0  no drift OR apply or record completed successfully
#   1  drift detected in --check mode (no mutations)
#   2  unverifiable: prerequisite missing (curl/jq/npm), network failure, or usage;
#      or --apply refused or unconfirmed: npm's global bin does not hold the
#      firecrawl command, or the command does not read npm latest after install
#
# A firecrawl CLI that is not installed is reported but is not drift; an
# installed CLI behind npm latest is. Drift outranks unverifiable: a run that
# finds drift exits 1 even when another of its checks could not run.
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
UPSTREAM_MD="${SKILL_DIR}/upstream.md"
TMPDIR_RUN=$(mktemp -d "${TMPDIR:-/tmp}/firecrawl-update-XXXXXX")

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
}

check_prereqs() {
  local missing=0
  require_tool curl || missing=1
  require_tool jq || missing=1
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

# Latest published CLI version from the npm registry. `--fail` keeps an HTTP
# error page from being read as the response.
latest_cli_version() {
  local body
  body=$(curl -sSL --fail --max-time 10 "$NPM_LATEST_URL" 2>/dev/null)
  [[ -n "$body" ]] || return 1
  printf '%s' "$body" | jq -r '.version // empty'
}

# `--fail` is critical: an HTTP error page would otherwise be hashed as the real
# SKILL.md, poisoning upstream.md on --apply and masking drift on --check.
fetch_upstream_sha() {
  local out="${TMPDIR_RUN}/upstream-skill.md"
  curl -sSL --fail --max-time 15 "$UPSTREAM_URL" -o "$out" 2>/dev/null || return 1
  [[ -s "$out" ]] || return 1
  sha256 "$out" | awk '{print $1}'
}

# Read the value of a `- <Label>: <value>` line from upstream.md: empty when
# the file or the line is absent, or the value is a never-synced placeholder
# such as `never` or `(none recorded)`.
recorded_field() {
  [[ -f "$UPSTREAM_MD" ]] || return 0
  local value
  value=$(grep -m1 "^- $1: " "$UPSTREAM_MD" | tr -d '\r')
  value="${value#"- $1: "}"
  value="${value%"${value##*[![:space:]]}"}"
  case "$value" in
  "("* | never | none) return 0 ;;
  *) ;; # a recorded value
  esac
  printf '%s' "$value"
}

recorded_upstream_sha() { recorded_field 'Upstream SHA256'; }
recorded_cli_version() { recorded_field 'CLI version at sync'; }
recorded_sync_date() { recorded_field 'Last sync'; }

run_check() {
  local current latest upstream_sha recorded_sha recorded_ver synced drift=0 unverifiable=0

  section "CLI version"
  current=$(current_cli_version)
  if ! latest=$(latest_cli_version) || [[ -z "$latest" ]]; then
    err "failed to reach npm registry — network or proxy issue"
    latest=""
    unverifiable=1
  fi
  recorded_ver=$(recorded_cli_version)

  if [[ -z "$current" ]]; then
    log "installed:  NOT INSTALLED (not counted as drift)"
  else
    log "installed:  $current"
  fi
  log "latest:     ${latest:-unknown}"
  synced=$(recorded_sync_date)
  log "last sync:  ${synced:-never} (CLI ${recorded_ver:-not recorded})"

  if [[ -n "$current" && -z "$latest" ]]; then
    log "→ CLI version unverifiable"
  elif [[ -n "$current" && "$current" != "$latest" ]]; then
    log "→ CLI upgrade available: $current → $latest"
    drift=1
  elif [[ -n "$current" ]]; then
    log "→ CLI at latest"
  fi

  section "Upstream SKILL.md"
  recorded_sha=$(recorded_upstream_sha)
  if ! upstream_sha=$(fetch_upstream_sha); then
    err "failed to fetch upstream SKILL.md from $UPSTREAM_URL"
    log "recorded SHA256: ${recorded_sha:-(never synced)}"
    unverifiable=1
  else
    log "fetched SHA256:  $upstream_sha"
    log "recorded SHA256: ${recorded_sha:-(never synced — first run)}"
    if [[ -z "$recorded_sha" ]]; then
      drift=1
    elif [[ "$upstream_sha" == "$recorded_sha" ]]; then
      log "→ upstream unchanged"
    else
      log "→ upstream content changed since last sync"
      drift=1
    fi
  fi

  section "Summary"
  if [[ $drift -eq 0 && $unverifiable -eq 1 ]]; then
    log "Unverifiable: the npm registry or the upstream SKILL.md could not be read."
    return 2
  fi
  if [[ $drift -eq 0 ]]; then
    log "No drift. CLI and skill are in sync with upstream."
    return 0
  fi
  log "Drift detected. Run '/firecrawl:update' (without --check) to apply."
  log "Script alone cannot rewrite SKILL.md — that's Claude's integration step,"
  log "governed by this update skill's SKILL.md Preservation rules."
  return 1
}

# The directory npm links global commands into: <prefix>/bin, or on Windows the
# prefix itself, printed as a Windows path that Git Bash's `command -v` never
# matches until converted.
npm_global_bin() {
  local prefix
  prefix=$(npm prefix -g 2>/dev/null | tr -d '\r')
  [[ -n "$prefix" ]] || return 1
  case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) cygpath -u "$prefix" ;;
  *) printf '%s/bin' "$prefix" ;;
  esac
}

physical_dir() { (cd "$1" 2>/dev/null && pwd -P); }

# Installing changes what `firecrawl` runs only when npm's global bin holds the
# command, so refuse when something else does. No command at all is a fresh install.
require_npm_owned_command() {
  local cmd bin
  cmd=$(command -v firecrawl) || return 0
  bin=$(npm_global_bin) || {
    err "cannot read npm's global prefix (npm prefix -g) to tell who owns $cmd; nothing written"
    return 2
  }
  if [[ "$(physical_dir "$(dirname "$cmd")")" != "$(physical_dir "$bin")" ]]; then
    err "firecrawl resolves to $cmd, outside npm's global bin ($bin), so npm install -g would not change what it runs"
    err "nothing installed or written: update the pin in the owner of $cmd instead"
    return 2
  fi
}

run_apply() {
  local current latest previous_ver

  require_npm_owned_command || return 2

  previous_ver=$(current_cli_version)
  # Registry preflight — fail before npm install mutates the global CLI.
  if ! latest=$(latest_cli_version) || [[ -z "$latest" ]]; then
    err "failed to reach npm registry"
    return 2
  fi

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
  if [[ "$current" != "$latest" ]]; then
    err "firecrawl reports $current after install, expected $latest; upstream.md not written — rollback: npm install -g ${NPM_PKG}@${previous_ver:-<previous>}"
    return 2
  fi
  # A global install updates itself in the background; turn that off so the CLI
  # changes only through this gated path.
  if ! firecrawl update --disable-auto; then
    err "firecrawl update --disable-auto failed; upstream.md not written — the CLI may update itself outside /firecrawl:update"
    return 2
  fi
  firecrawl --status 2>&1 | head -10 || true

  # The upstream SHA and sync date stay as recorded: they mark what the skill has
  # integrated, which only --record-upstream, after Gate 2, may advance.
  rewrite_upstream_md "$(recorded_upstream_sha)" "$current" "$previous_ver" "$(recorded_sync_date)"
  log "upstream.md: CLI version and rollback target recorded; upstream SHA kept"

  section "Next step"
  log "Now invoke the skill's Gate-2 integration: review the upstream SKILL.md"
  log "changes (diff against the tmp-fetched content) and integrate under the"
  log "Preservation rules. See this update skill's SKILL.md. When Gate 2 is done,"
  log "or there was no content delta, run --record-upstream."
  return 0
}

run_record_upstream() {
  local current upstream_sha

  upstream_sha=$(fetch_upstream_sha) || {
    err "failed to fetch upstream SKILL.md; upstream.md not written"
    return 2
  }
  current=$(current_cli_version)
  rewrite_upstream_md "$upstream_sha" "${current:-$(recorded_cli_version)}" \
    "$(recorded_field 'Previous CLI version (rollback target)')" "$(date -u +%Y-%m-%d)"
  log "upstream.md: upstream SHA256 $upstream_sha recorded"
  return 0
}

# A value with nothing recorded is written as the placeholder recorded_field
# reads back as empty, so --check still treats the skill as never synced.
rewrite_upstream_md() {
  local sha="$1" ver="$2" prev="$3" synced="${4:-}"
  cat >"$UPSTREAM_MD" <<EOF
<!-- firecrawl update state: do not edit by hand. -->
<!-- Written by the skill's scripts/update.sh --apply and --record-upstream. -->

# Firecrawl skill upstream sync state

- Last sync: ${synced:-never}
- Upstream URL: ${UPSTREAM_URL}
- Upstream SHA256: ${sha:-(none recorded)}
- CLI version at sync: ${ver:-(none recorded)}
- Previous CLI version (rollback target): ${prev:-none}
- CLI npm URL: https://www.npmjs.com/package/${NPM_PKG}
- Next recheck: run the update action with --check weekly or when a scrape
  fails unexpectedly. Script alone never rewrites SKILL.md. Claude integrates
  upstream content under SKILL.md Preservation rules.
EOF
}

main() {
  local mode="${1:---check}"

  case "$mode" in
  -h | --help)
    cat <<'EOF'
Usage: update.sh [--check | --apply | --record-upstream | --help]

Drift-check + upgrade helper for the firecrawl plugin skill. Maintainer-
facing: run in a working-tree checkout of the plugin, not an installed copy.

  --check  (default) Read-only drift report: CLI version delta + upstream SHA delta.
           Exit 0 if in sync, 1 if drift detected, 2 on prerequisite/network error.

  --apply  Run npm install -g firecrawl-cli@latest, turn off the CLI's background
           self-update (firecrawl update --disable-auto), and record the CLI version
           and rollback target in upstream.md, keeping the recorded upstream SHA.
           Exit 2 before installing, writing nothing, when something other than
           npm's global bin owns the firecrawl command. Exit 2 after installing,
           without writing upstream.md, when the command does not read npm latest.
           Does NOT rewrite SKILL.md — that's Claude's integration step, governed
           by SKILL.md Preservation rules.

  --record-upstream
           Fetch upstream SKILL.md and record its SHA in upstream.md, with the
           version the firecrawl command reads. Installs nothing. Run it only after
           Gate 2 is done or there was no content delta. Exit 2, writing nothing,
           when the fetch fails.

  --help   Show this message.
EOF
    exit 0
    ;;
  *) ;; # other modes handled below after prerequisite checks
  esac

  if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
    err "SKILL.md not found at ${SKILL_DIR} — run from a plugin checkout"
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
  --record-upstream)
    run_record_upstream
    ;;
  *)
    err "unknown mode: $mode (expected --check, --apply, --record-upstream, or --help)"
    exit 2
    ;;
  esac
}

# Source-guard: only run main when executed directly, not when sourced (tests).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
