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
# WHY THIS EXISTS: managed policy is not one file. Each OS has several
# surfaces (files, a drop-in directory, an OS policy store), listed at
# https://code.claude.com/docs/en/managed-settings#where-each-mechanism-stores-the-policy
# with the drop-in directory at
# https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams
# (as of 2026-10-11; recheck when either section gains, drops or moves a
# surface). Three components in this marketplace need that enumeration, and a
# third hand-written copy would drift the moment upstream adds or moves a
# surface, as it already had: the copies disagreed about whether the drop-in
# directory existed at all. The paths are documented, not discoverable: a
# machine with no policy deployed looks identical to a machine whose policy
# this file fails to find. A location the first section says Claude Code does
# not read is deliberately never probed, so nothing reports policy that is not
# in force.
#
# The server-managed cache (`mscope::remote_cache_file`) is not an admin-written
# policy file: it is user-writable and it can be stale. A reader may report the
# cache's presence. It must not fold the cache into the effective managed
# policy, and it must not treat a missing cache as "no organization policy";
# whether a fetch failed is read from Claude Code's own status report instead.
# Upstream records, as of 2026-10-11:
#   * the cache path:
#     https://code.claude.com/docs/en/server-managed-settings#invalid-entries-in-delivered-settings
#   * when the cache applies and which cached keys wait for the server:
#     https://code.claude.com/docs/en/server-managed-settings#fetch-and-caching-behavior
#   * where a failed fetch is reported:
#     https://code.claude.com/docs/en/server-managed-settings#verify-settings-delivery
# Recheck when the invalid-entries section names a cache path other than the
# one mscope::remote_cache_file returns, the fetch-and-caching section changes
# when cached settings apply or which cached keys wait for the server, or the
# verify section stops naming /status or claude doctor as where a failed fetch
# shows.
#
# Cross-source combination is not "arrays concatenated, objects deep-merged":
# a reader that computes an effective merge follows the per-key rules at
# https://code.claude.com/docs/en/managed-settings#compose-every-managed-source
# and https://code.claude.com/docs/en/settings-reference#managedsourcesbehavior,
# and drop-in files combine by the rules in the split-a-file section above
# (as of 2026-10-11; recheck when any of those sections gains or drops a key
# kind or a combination rule).

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
