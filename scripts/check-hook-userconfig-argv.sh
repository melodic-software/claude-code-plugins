#!/usr/bin/env bash
# Gate: no plugin hook configuration may carry a bare ${user_config.*} token.
#
#   scripts/check-hook-userconfig-argv.sh    fail on any ${user_config.*} in a
#                                            plugin hook config
#
# Why: the declared userConfig `default` is unimplemented upstream (#46477 —
# closed not-planned), so an unset-but-defaulted ${user_config.*} argv token
# silently drops the ENTIRE hook entry instead of substituting. On a default
# install the hook never fires — the exact regression disk-hygiene shipped
# through 0.8.x and #1242 fixed. The channel decision matrix
# (docs/conventions/hook-config-delivery/) rules argv out for hooks until
# upstream implements `default`; this gate pins that rule.
#
# Scope: hook configurations only — the default hooks/hooks.json, any
# manifest-pointed hook config file (`hooks` as a string or array of paths),
# and an inline manifest `hooks` object. MCP and LSP server configs are OUT of
# scope: ${user_config.*} substitution there is sanctioned and does not drop
# components. A hooks/*.json file the manifest never references is not loaded
# by Claude Code and is not scanned.
#
# Escape hatch: scripts/hook-userconfig-argv-allowlist.txt lists repo-relative
# file paths permitted to carry the token — reserved for a ratified channel D
# (`required:true` + argv, no unset case) adoption per the convention's
# Open-gaps probe. An allowlist entry whose file is missing or clean is stale
# and fails the gate, so the list can only shrink back to reality.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "check-hook-userconfig-argv: jq is required but not installed" >&2
  exit 1
fi

ALLOWLIST="scripts/hook-userconfig-argv-allowlist.txt"
# shellcheck disable=SC2016  # single quotes are deliberate: the token is matched literally, never expanded
TOKEN='${user_config.'

# CRLF tolerance: on Windows (Git Bash) jq and text files can carry \r line
# endings; strip them from every value read, or path tests silently miss.
allowed() {
  local path="$1"
  [[ -f "$ALLOWLIST" ]] || return 1
  tr -d '\r' <"$ALLOWLIST" | grep -Fxq "$path"
}

errors=0
declare -A flagged_or_allowed=()

flag() {
  local file="$1" where="$2"
  flagged_or_allowed["$file"]=1
  # shellcheck disable=SC2310  # allowed only greps a static file; nothing inside it can fail unexpectedly
  if allowed "$file"; then
    return 0
  fi
  echo "USERCONFIG ARGV: ${file}:${where}: bare \${user_config.*} in plugin hook config" >&2
  errors=$((errors + 1))
}

# scan_manifest_path <plugin-dir> <manifest> <relative hooks path> — trust
# boundary: a manifest-pointed hook config must stay inside its own plugin
# directory. Reject absolute paths and any `..` segment (portable string
# check — no realpath dependency) with a visible skip, so a crafted manifest
# cannot point this gate at files outside the tree it claims to scan.
scan_manifest_path() {
  local plugin="$1" manifest="$2" rel="$3"
  [[ -n "$rel" ]] || return 0
  if [[ "$rel" == /* || "$rel" =~ ^[A-Za-z]: || "/$rel/" == *"/../"* ]]; then
    echo "check-hook-userconfig-argv: skipping out-of-tree hooks path in $manifest: $rel" >&2
    return 0
  fi
  scan_file "$plugin/${rel#./}"
}

# scan_file <repo-relative hook config path> — two passes: a raw-text grep for
# precise file:line reporting, then a decoded pass (jq re-serializes the JSON,
# resolving \u-escapes such as ${user_config.KEY} that the loader decodes
# before substitution) so an escaped spelling of the token cannot slip past the
# raw scan. An unparsable file gets the raw pass only.
scan_file() {
  local file="$1" hits line
  [[ -f "$file" ]] || return 0
  hits="$(grep -nF "$TOKEN" "$file" || true)"
  if [[ -n "$hits" ]]; then
    while IFS= read -r line; do
      flag "$file" "${line%%:*}"
    done <<<"$hits"
  elif jq -c . "$file" 2>/dev/null | grep -qF "$TOKEN"; then
    flag "$file" "escaped token in decoded JSON"
  fi
}

for plugin in plugins/*/; do
  plugin="${plugin%/}"
  manifest="$plugin/.claude-plugin/plugin.json"

  # Default location, always loaded when present.
  scan_file "$plugin/hooks/hooks.json"

  [[ -f "$manifest" ]] || continue
  hooks_type="$(jq -r '.hooks | type' "$manifest" 2>/dev/null | tr -d '\r' || echo invalid)"
  case "$hooks_type" in
  string)
    rel="$(jq -r '.hooks' "$manifest" | tr -d '\r')"
    scan_manifest_path "$plugin" "$manifest" "$rel"
    ;;
  array)
    while IFS= read -r rel; do
      rel="${rel%$'\r'}"
      scan_manifest_path "$plugin" "$manifest" "$rel"
    done < <(jq -r '.hooks[] | select(type == "string")' "$manifest" 2>/dev/null || true)
    ;;
  object)
    if jq -c '.hooks' "$manifest" 2>/dev/null | grep -qF "$TOKEN"; then
      flag "$manifest" "inline hooks object"
    fi
    ;;
  *) ;; # null, absent, or unparsable manifest (manifest validity has its own gate)
  esac
done

# Stale-allowlist guard: every entry must name a scanned hook config that still
# carries the token; anything else is drift the list must shed.
if [[ -f "$ALLOWLIST" ]]; then
  while IFS= read -r entry; do
    entry="${entry%$'\r'}"
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    if [[ -z "${flagged_or_allowed[$entry]:-}" ]]; then
      echo "STALE ALLOWLIST: $ALLOWLIST: '$entry' names no scanned hook config carrying \${user_config.*} — remove it" >&2
      errors=$((errors + 1))
    fi
  done <"$ALLOWLIST"
fi

if ((errors > 0)); then
  {
    echo
    echo "A \${user_config.*} token in a plugin hook config silently drops the"
    echo "whole hook entry whenever the key is unset (declared defaults are not"
    echo "implemented upstream). Deliver the value per the channel decision"
    echo "matrix instead: docs/conventions/hook-config-delivery/README.md."
  } >&2
  exit 1
fi
echo "No bare \${user_config.*} tokens in plugin hook configs."
