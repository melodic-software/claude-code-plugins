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
# NOT COVERED, deliberately: server-managed settings, which the doc describes as
# "delivered remotely at sign-in from Anthropic's servers via the claude.ai admin
# console or from a self-hosted Claude apps gateway". They have no local path to
# enumerate, so a local reader cannot see them and must not imply it has.
#
# The legacy Windows location C:\ProgramData\ClaudeCode\managed-settings.json is
# unsupported since v2.1.75 and is deliberately never probed — reporting it would
# report policy that is not in force.
#
# Verified against https://code.claude.com/docs/en/settings on 2026-08-10.
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
# Merge semantics, for callers that report them: "managed-settings.json is merged
# first as the base, then all *.json files in the drop-in directory are sorted
# alphabetically and merged on top. Later files override earlier ones for scalar
# values, arrays are concatenated and de-duplicated, and objects are deep-merged.
# Hidden files starting with . are ignored."
mscope::dropin_dir() {
  local base
  base="$(mscope::base_file "${1:-}")"
  printf '%s\n' "${base%managed-settings.json}managed-settings.d"
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
    # a single-quoted Windows registry path, not a GNU regex escape. These lines
    # only ever run on Windows, and `printf '%s'` does no escape interpretation.
    printf '%s\n' 'HKLM\SOFTWARE\Policies\ClaudeCode'
    printf '%s\n' 'HKCU\SOFTWARE\Policies\ClaudeCode'
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
