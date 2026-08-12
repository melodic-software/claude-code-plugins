#!/usr/bin/env bash
# permission-state.sh — scope discovery and raw rule inventory for the
# audit-permission-state skill.
#
# Claude Code exposes no way to see the permission rules actually in effect:
# there is no `claude permissions` subcommand and no machine-readable export.
# This script is step one of computing that state locally — it finds every
# settings scope, says what it could and could not read, and emits each scope's
# raw allow/ask/deny rules. It decides NOTHING about precedence; that is the
# merge step's job, and a reader that cannot say which scopes it saw cannot be
# trusted to merge them.
#
# Output (one record per line, stable field order):
#   <scope> <surface> <status> <path>            one per settings surface
#   rule <scope> <surface> <kind> <rule text>    one per allow/ask/deny entry
#   NOTE: <text>                                 anything the operator must know
#
#   scope    managed | user | project | local | startdir-local
#   surface  file | dropin-dir | dropin-file:<name> | registry | plist (managed);
#            settings (everything else)
#   status   present | absent | unreadable | invalid-json | skipped | not-applicable
#   kind     allow | ask | deny
#
# EVERY scope and managed surface emits exactly one record on every OS, even
# when it does not apply here. A surface that is silently absent from the output
# is indistinguishable from one that was never attempted, and this script's whole
# value is being able to say which is which.
#
# Managed policy is READ-ONLY and always will be: those are admin-write OS
# locations or a claude.ai Owner role. This script writes nothing, anywhere.
#
# Prerequisites:
#   jq   required for correctness — exits 2 at the entry point when absent.
#   reg  optional platform integration (Windows managed policy). Absent or
#        failing: warn visibly, mark that surface `skipped`, keep every other
#        result.
#   defaults  the same, for the macOS managed-preferences domain.
#
# Test seams (the real locations are absolute system paths and a real user home,
# which no test may touch):
#   PERMISSION_STATE_FIXTURE_DIR       project root
#   PERMISSION_STATE_STARTDIR          session start directory
#   PERMISSION_STATE_MANAGED_PATH      managed-settings.json (drop-in dir follows it)
#   PERMISSION_STATE_REGISTRY_KEYS     newline-separated registry keys to query
#   PERMISSION_STATE_PLIST_DOMAIN      managed-preferences domain to read
#   CLAUDE_CONFIG_DIR / HOME           user scope, the same resolver Claude Code documents
#
# Usage:
#   permission-state.sh            full inventory
#   permission-state.sh --scopes   surface records only, no rule records
#   permission-state.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
permission-state.sh — discover every Claude Code settings scope and inventory its rules.

Usage: permission-state.sh [--scopes|--help]

  (no arg)   surface records + one record per allow/ask/deny rule
  --scopes   surface records only
  --help     this message

Records: "<scope> <surface> <status> <path>" and "rule <scope> <surface> <kind> <text>".
Every scope and managed surface emits exactly one record on every OS, so a surface
that was never attempted is never mistaken for one that is genuinely absent.

Reads only. Requires jq (exit 2 when absent); the Windows registry and macOS
preferences-domain surfaces are optional and degrade to `skipped` with a notice.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

mode="full"
[[ "${1:-}" == "--scopes" ]] && mode="scopes"

# `${BASH_SOURCE[0]%/*}` rather than `dirname`: `cd` and `pwd` are builtins, so
# plugin-root resolution needs nothing on PATH. A missing external tool here
# would leave PLUGIN_ROOT empty, the source would fail, and every managed surface
# would report `absent` — a reader claiming no policy is deployed because it
# could not load its own library is the worst failure this script can have.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
if [[ ! -r "$MANAGED_SCOPE_LIB" ]]; then
  echo "ERROR: cannot read $MANAGED_SCOPE_LIB — the plugin's shared managed-scope library is missing, so managed policy cannot be located" >&2
  exit 2
fi
# shellcheck source=../../../lib/managed-scope.sh
source "$MANAGED_SCOPE_LIB"

emit() { printf '%s %s %s %s\n' "$1" "$2" "$3" "${4:--}"; }
note() { printf 'NOTE: %s\n' "$1"; }

# MSYS/Cygwin rewrite any argument containing backslashes as though it were a
# POSIX path, so a registry key reaches reg.exe mangled and the call dies with
# "ERROR: Invalid syntax" — which a naive caller reads as "no policy deployed"
# on a machine that has one. Measured on Git Bash 2026-08-11: the same query
# succeeds with the rewrite disabled and fails with it on. Scope the opt-out to
# these calls rather than exporting it, so nothing else in the process changes.
reg_cmd() { MSYS2_ARG_CONV_EXCL='*' reg "$@"; }

# --- Root resolution ----------------------------------------------------------

# The session's start directory. Claude Code wrote settings.local.json here
# before v2.1.211 and still reads what an earlier version left behind.
START_DIR="${PERMISSION_STATE_STARTDIR:-$PWD}"

if [[ -n "${PERMISSION_STATE_FIXTURE_DIR:-}" ]]; then
  PROJECT_ROOT="$PERMISSION_STATE_FIXTURE_DIR"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# settings.local.json lives "at the root of the git repository, resolved through
# worktrees to the main checkout, so one file covers sessions started in any
# subdirectory or worktree" — anchoring on --show-toplevel would look for it in
# the WORKTREE, where it is not. --git-common-dir points at the main checkout's
# .git for every linked worktree and at our own inside the main checkout, so its
# parent is the main checkout root either way.
#
# Three documented exceptions keep the file in the start directory: outside a git
# repository, when the repository root is the home directory, and in Agent SDK
# sessions. The first two are detectable here; the third is not, so it is stated
# rather than silently mis-resolved.
LOCAL_ROOT="$PROJECT_ROOT"
local_basis="repository root"
if [[ -z "${PERMISSION_STATE_FIXTURE_DIR:-}" ]]; then
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -n "$common_dir" ]]; then
    main_root="$(cd "$common_dir/.." 2>/dev/null && pwd)"
    if [[ -n "$main_root" && "$main_root" != "$PROJECT_ROOT" ]]; then
      LOCAL_ROOT="$main_root"
      local_basis="main checkout, resolved through this worktree"
    fi
  else
    LOCAL_ROOT="$START_DIR"
    local_basis="start directory (not inside a git repository)"
  fi
fi
if [[ -n "${HOME:-}" && "$LOCAL_ROOT" == "$HOME" ]]; then
  LOCAL_ROOT="$START_DIR"
  local_basis="start directory (repository root is the home directory)"
fi

if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  USER_CONFIG_ROOT="$CLAUDE_CONFIG_DIR"
elif [[ -n "${HOME:-}" ]]; then
  USER_CONFIG_ROOT="$HOME/.claude"
else
  USER_CONFIG_ROOT=""
fi

MANAGED_FILE="$(mscope::base_file "${PERMISSION_STATE_MANAGED_PATH:-}")"
MANAGED_DROPIN="$(mscope::dropin_dir "${PERMISSION_STATE_MANAGED_PATH:-}")"

# --- Reading ------------------------------------------------------------------

# classify_json_file <path> — status for a settings file, without ever holding
# its contents in a variable (a settings file may carry credentials, and a shell
# variable would put them into `set -x` output).
classify_json_file() {
  local path="$1"
  [[ -f "$path" ]] || {
    printf 'absent\n'
    return 0
  }
  : <"$path" 2>/dev/null || {
    printf 'unreadable\n'
    return 0
  }
  tr -d '\r' <"$path" | jq empty 2>/dev/null || {
    printf 'invalid-json\n'
    return 0
  }
  tr -d '\r' <"$path" | jq -e '
    (.permissions | type) as $pt
    | if $pt == "null" then true
      elif $pt == "object" then
        (.permissions | to_entries[] | .value | type) as $kt
        | ($kt == "null" or $kt == "array")
      else false end
  ' >/dev/null 2>&1 || {
    printf 'invalid-json\n'
    return 0
  }
  printf 'present\n'
}

emit_file_rules() {
  # emit_file_rules <scope> <surface> <path>
  [[ "$mode" == "full" ]] || return 0
  local scope="$1" surface="$2" path="$3" kind
  for kind in allow ask deny; do
    while IFS= read -r rule; do
      [[ -n "$rule" ]] && printf 'rule %s %s %s %s\n' "$scope" "$surface" "$kind" "$rule"
      # jq emits CRLF on Windows; a trailing \r would corrupt every rule string.
    done < <(tr -d '\r' <"$path" | jq -r --arg k "$kind" '.permissions[$k] // [] | .[]' 2>/dev/null | tr -d '\r')
  done
}

emit_json_scope() {
  # emit_json_scope <scope> <surface> <path>
  local scope="$1" surface="$2" path="$3" status
  status="$(classify_json_file "$path")"
  emit "$scope" "$surface" "$status" "$path"
  [[ "$status" == "present" ]] && emit_file_rules "$scope" "$surface" "$path"
  return 0
}

# --- Managed scope: portable core --------------------------------------------

emit_json_scope managed file "$MANAGED_FILE"

if [[ -d "$MANAGED_DROPIN" ]]; then
  emit managed dropin-dir present "$MANAGED_DROPIN"
  # "managed-settings.json is merged first as the base, then all *.json files in
  # the drop-in directory are sorted alphabetically and merged on top… Hidden
  # files starting with . are ignored." Read them in that documented order so a
  # downstream merge does not have to guess it; `sort` is the same collation the
  # doc's "alphabetically" names, and the caller sees the order it read them in.
  while IFS= read -r dropin; do
    [[ -f "$dropin" ]] || continue
    case "${dropin##*/}" in .*) continue ;; *) ;; esac
    emit_json_scope managed "dropin-file:${dropin##*/}" "$dropin"
  done < <(find "$MANAGED_DROPIN" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort)
else
  emit managed dropin-dir absent "$MANAGED_DROPIN"
fi

# --- Managed scope: declared optional platform integrations -------------------
#
# Present where native and readable; a visibly announced `skipped` otherwise. The
# portable core above is never affected — that is the contract an optional
# platform integration owes.

registry_keys="${PERMISSION_STATE_REGISTRY_KEYS:-$(mscope::registry_keys)}"
if [[ -z "$registry_keys" ]]; then
  emit managed registry not-applicable "-"
elif ! command -v reg >/dev/null 2>&1; then
  emit managed registry skipped "-"
  note "Windows managed policy not read: 'reg' is not on PATH. Every other scope below is unaffected; the managed result is incomplete, not empty."
else
  # The policy JSON lives in a single `Settings` value on the key. HKCU is
  # documented as "lowest policy priority, only used when no admin-level source
  # exists", so the search stops at the first key that EXISTS and the rest are
  # not consulted — merging them would report policy that is not in force.
  #
  # Existence is probed with a bare `reg query <key>`, not `/v Settings`: with
  # `/v` the two failures that must not be conflated — key absent, and key
  # present but carrying no Settings value — return the same exit code and the
  # same message ("The system was unable to find the specified registry key or
  # value"), measured on Windows 11 2026-08-11. Keying the search on the /v form
  # would let an admin-level key with an unreadable value fall through to HKCU
  # and report user-level policy as the managed policy while the admin-level key
  # is what is in force. A key that exists but yields nothing readable is
  # reported as `unreadable`, never as a licence to consult the next key.
  registry_status="absent"
  registry_path="-"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    reg_cmd query "$key" >/dev/null 2>&1 || continue
    registry_path="$key"
    if reg_cmd query "$key" /v Settings >/dev/null 2>&1; then
      registry_status="present"
    else
      registry_status="unreadable"
      note "Managed policy key $registry_path exists but carries no readable Settings value. Lower-priority policy keys are NOT consulted in its place — an admin-level key that exists is the source in force, so the managed registry result is unread rather than empty."
    fi
    break
  done <<<"$registry_keys"
  emit managed registry "$registry_status" "$registry_path"
  if [[ "$registry_status" == "present" && "$mode" == "full" ]]; then
    # `reg query` prints "<name> <type> <data>" with the data as the rest of the
    # line; cut at the type token rather than by field count, because the JSON
    # payload contains spaces.
    reg_json="$(reg_cmd query "$registry_path" /v Settings 2>/dev/null | tr -d '\r' |
      sed -n 's/^[[:space:]]*Settings[[:space:]]*REG_\(EXPAND_\)\{0,1\}SZ[[:space:]]*//p' | head -1)"
    if [[ -z "$reg_json" ]] || ! printf '%s' "$reg_json" | jq empty 2>/dev/null; then
      note "Windows managed policy key $registry_path carries a Settings value that did not parse as JSON — reporting it as unread rather than as empty."
    else
      for kind in allow ask deny; do
        while IFS= read -r rule; do
          [[ -n "$rule" ]] && printf 'rule managed registry %s %s\n' "$kind" "$rule"
        done < <(printf '%s' "$reg_json" | jq -r --arg k "$kind" '.permissions[$k] // [] | .[]' 2>/dev/null | tr -d '\r')
      done
    fi
  fi
fi

plist_domain="${PERMISSION_STATE_PLIST_DOMAIN:-$(mscope::plist_domain)}"
if [[ -z "$plist_domain" ]]; then
  emit managed plist not-applicable "-"
elif ! command -v defaults >/dev/null 2>&1; then
  emit managed plist skipped "-"
  note "macOS managed preferences not read: 'defaults' is not on PATH. Every other scope below is unaffected; the managed result is incomplete, not empty."
else
  if defaults read "$plist_domain" >/dev/null 2>&1; then
    emit managed plist present "$plist_domain"
    note "The managed-preferences domain $plist_domain is present. Its rules are NOT inventoried yet — this reader reports the surface, not its contents."
  else
    emit managed plist absent "$plist_domain"
  fi
fi

# Server-managed settings arrive remotely at sign-in and have no local path, so
# no local reader can see them. Saying so is the difference between an honest
# managed report and one that implies completeness it cannot have.
note "Server-managed settings (delivered at sign-in via the claude.ai admin console or a self-hosted gateway) have no local path and are not visible to any local reader. 'managed' above means the local managed surfaces only."

# --- The four file scopes -----------------------------------------------------

if [[ -n "$USER_CONFIG_ROOT" ]]; then
  emit_json_scope user settings "$USER_CONFIG_ROOT/settings.json"
else
  emit user settings skipped "-"
  note "User scope not read: neither CLAUDE_CONFIG_DIR nor HOME is set, so ~/.claude could not be resolved."
fi

emit_json_scope project settings "$PROJECT_ROOT/.claude/settings.json"
emit_json_scope local settings "$LOCAL_ROOT/.claude/settings.local.json"
note "local scope anchored on the $local_basis. In an Agent SDK session the file stays in the start directory instead, which this reader cannot detect."

# The pre-v2.1.211 copy is a DISTINCT scope member, not a fallback: when both
# exist "the repository root's value wins, except that permission rules from both
# files stay in effect", so both rule sets are live and both must be inventoried.
STARTDIR_LOCAL="$START_DIR/.claude/settings.local.json"
if [[ "$STARTDIR_LOCAL" == "$LOCAL_ROOT/.claude/settings.local.json" ]]; then
  emit startdir-local settings not-applicable "$STARTDIR_LOCAL"
else
  emit_json_scope startdir-local settings "$STARTDIR_LOCAL"
fi

exit 0
