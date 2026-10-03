# GENERATED from lib/managed-scope.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash
# Managed (machine-scope) policy surfaces — per-OS enumeration, library only.
#
# No top-level execution, no env-driven side effects, no exit calls. Callers own
# presentation, redaction posture, test seams, and exit-code mapping: one caller
# reports managed policy as counts, another as presence only, and a third reads
# it to compute an effective merge. Only the LOCATIONS are shared.
#
# WHY THIS EXISTS: managed policy is not one file. Per the official settings doc
# it is, per OS, a JSON file plus a `managed-settings.d/` drop-in directory, plus
# a Windows registry policy key or a macOS managed-preferences domain. Three
# components in this marketplace need that enumeration, and a third hand-written
# copy would drift the moment upstream adds or moves a surface — as it already
# had: the copies disagreed about whether the drop-in directory existed at all.
#
# Server-managed settings are fetched at sign-in and cached at
# `<config-root>/remote-settings.json` (`mscope::remote_cache_file`). The cache
# is not an admin-written policy file: it is user-writable, it can be stale, and
# several cached keys stay withheld until the server confirms the payload. A
# reader may report the cache's presence. It must not fold the cache into the
# effective managed policy, and it must not treat a missing cache as "no
# organization policy". The failure read is the Organization policy line in
# `/status` (and `claude doctor`'s managed-settings remote line).
# Basis: https://code.claude.com/docs/en/server-managed-settings and
# https://code.claude.com/docs/en/managed-settings. Verified 2026-09-28.
# Recheck when either page moves the cache path or changes what `/status` reports
# on a failed fetch.
#
# Cross-source combination is not "arrays concatenated, objects deep-merged".
# Under `managedSourcesBehavior: "merge"` Claude Code combines keys by kind
# (lists union, locks take the strictest value, restriction allowlists and
# values-taken-whole come from the highest source that sets them, provided MCP
# server names union with the higher entry winning on a clash, and a named set
# of keys is read from the highest source only). `sandbox.credentials.awsPairs`
# and `sandbox.ripgrep` are values taken whole since v2.1.257. `env` merges per
# variable. Basis: https://code.claude.com/docs/en/settings-reference
# (`managedSourcesBehavior`) and https://code.claude.com/docs/en/managed-settings
# ("Compose every managed source"). Verified 2026-09-28. Recheck when that table
# gains or drops a key kind, or when awsPairs / ripgrep leave the whole-value row.
#
# The legacy Windows location C:\ProgramData\ClaudeCode\managed-settings.json is
# unsupported since v2.1.75 and is deliberately never probed — reporting it would
# report policy that is not in force.
#
# Verified against https://code.claude.com/docs/en/settings and
# https://code.claude.com/docs/en/managed-settings on 2026-09-28.
# Recheck trigger: that page's managed-settings location list gains, drops, or
# moves a surface. Basis: the paths are documented, not discoverable — a machine
# with no policy deployed looks identical to a machine whose policy this file
# fails to find.

# mscope::base_file [override] — absolute path to the managed-settings.json this
# OS reads. A non-empty <override> is returned verbatim, so a caller's own test
# seam stays the caller's: the real locations are absolute system paths that a
# fixture directory cannot reach.
#
# Windows resolves through $PROGRAMFILES so a relocated Program Files directory
# still resolves; the doc spells the default as C:\Program Files\ClaudeCode.
mscope::base_file() {
  local override="${1:-}"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  case "$OSTYPE" in
  darwin*) printf '%s\n' "/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  msys* | cygwin*) printf '%s\n' "${PROGRAMFILES:-C:\\Program Files}\\ClaudeCode\\managed-settings.json" ;;
  *) printf '%s\n' "/etc/claude-code/managed-settings.json" ;;
  esac
}

# mscope::dropin_dir [override] — absolute path to the managed-settings.d
# directory that sits beside the base file. Derived from the base file so an
# override relocates both together, which is what a fixture needs.
#
# Drop-in merge, for callers that report it. This is the file-source merge, not
# the cross-source table above. managed-settings.json is the base; every *.json
# in the directory follows in alphabetical order. Hidden files and files that
# do not end in .json are ignored. When two files set the same key: a single
# value is replaced by the later file; lists combine with duplicates removed;
# nested blocks merge key by key; fallbackModel, modelPicker, and a same-named
# extraKnownMarketplaces or managedMcpServers entry are replaced whole.
# Basis: https://code.claude.com/docs/en/managed-settings ("Split a file-based
# policy across teams"). Verified 2026-09-28. Recheck when that section changes
# how two drop-in files combine a key.
mscope::dropin_dir() {
  local base
  base="$(mscope::base_file "${1:-}")"
  printf '%s\n' "${base%managed-settings.json}managed-settings.d"
}

# mscope::remote_cache_file <config-root> — the server-managed settings cache
# Claude Code writes under the configuration directory. Empty when no root is
# given. The caller resolves CLAUDE_CONFIG_DIR or ~/.claude; this function does
# not read the environment.
mscope::remote_cache_file() {
  local root="${1:-}"
  [[ -n "$root" ]] || return 0
  root="${root%/}"
  printf '%s\n' "$root/remote-settings.json"
}

# mscope::registry_keys — Windows policy keys, one per line, highest policy
# priority first; nothing at all on other platforms. Each key carries the policy
# JSON in a `Settings` value (REG_SZ or REG_EXPAND_SZ), so a reader wants that
# value, not the key's subkeys. HKCU is "lowest policy priority, only used when
# no admin-level source exists" — a reader that merges both would report policy
# that is not in force.
mscope::registry_keys() {
  case "$OSTYPE" in
  msys* | cygwin*)
    # portability-ok: the `\S` here is the literal first character of SOFTWARE in
    # single-quoted Windows registry paths, not a GNU regex escape. This line
    # only ever runs on Windows, and `printf '%s'` does no escape interpretation.
    printf '%s\n' 'HKLM\SOFTWARE\Policies\ClaudeCode' 'HKCU\SOFTWARE\Policies\ClaudeCode'
    ;;
  *) ;;
  esac
}

# mscope::plist_domain — the macOS managed-preferences domain, empty elsewhere.
mscope::plist_domain() {
  case "$OSTYPE" in
  darwin*) printf '%s\n' "com.anthropic.claudecode" ;;
  *) ;;
  esac
}
