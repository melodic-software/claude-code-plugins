#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
permission-state.sh — discover every Claude Code settings scope and inventory its rules.

Usage: permission-state.sh [--scopes|--help]

  (no arg)   surface records + one record per allow/ask/deny rule
  --scopes   surface records only
  --help     this message

Records: "<scope> <surface> <status> <path>", "rule <scope> <surface> <kind> <text>",
and "conf <scope> <surface> <key> <json>" for permission-plane config keys
(today: autoMode.classifyAllShell).
Every scope and managed surface emits exactly one record on every OS, so a surface
that was never attempted is never mistaken for one that is genuinely absent.

Reads only. Requires jq (exit 2 when absent); the Windows registry and macOS
preferences-domain surfaces are optional and degrade to `skipped` with a notice.
EOF
}

mode="full"
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--scopes) mode="scopes" ;;
*) ;;
esac

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"

if ! command -v jq >/dev/null 2>&1; then
  # shellcheck source=../../../lib/jq-install-hint.sh
  if [[ -r "$PLUGIN_ROOT/lib/jq-install-hint.sh" ]] && source "$PLUGIN_ROOT/lib/jq-install-hint.sh"; then
    jqhint::missing_message permission-state.sh "${PERMISSION_STATE_OSTYPE-${OSTYPE:-}}" >&2
  else
    echo "ERROR: jq required" >&2
  fi
  exit 2
fi

MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
if [[ ! -r "$MANAGED_SCOPE_LIB" ]]; then
  echo "ERROR: cannot read $MANAGED_SCOPE_LIB — the plugin's shared managed-scope library is missing, so managed policy cannot be located" >&2
  exit 2
fi
# shellcheck source=../../../lib/managed-scope.sh
source "$MANAGED_SCOPE_LIB"

NL_SENTINEL=$'\x01MULTILINE\x01'

# shellcheck disable=SC2016 # a jq program: $k and $nl are jq variables bound with --arg, and must not expand in the shell
RULES_JQ='.permissions[$k] // [] | .[] | if test("[\n\r]") then $nl + (. | gsub("[\n\r]"; " ")) else . end'

crlf_strip() { sed 's/\r$//'; }

emit() { printf '%s %s %s %s\n' "$1" "$2" "$3" "${4:--}"; }
note() { printf 'NOTE: %s\n' "$1"; }

reg_cmd() { MSYS2_ARG_CONV_EXCL='*' reg "$@"; }


START_DIR="${PERMISSION_STATE_STARTDIR:-$PWD}"

if [[ -n "${PERMISSION_STATE_FIXTURE_DIR:-}" ]]; then
  PRIMARY_DIR="$PERMISSION_STATE_FIXTURE_DIR"
  REPO_ROOT="$PERMISSION_STATE_FIXTURE_DIR"
else
  PRIMARY_DIR="$PWD"
  {
    read -r REPO_ROOT
    read -r REPO_PREFIX
  } < <(git rev-parse --show-toplevel --show-prefix 2>/dev/null | tr -d '\r')
fi

TOPLEVEL_SHARED=""
[[ -z "${REPO_PREFIX:-}" || -z "${REPO_ROOT:-}" ]] || TOPLEVEL_SHARED="$REPO_ROOT/.claude/settings.json"

LOCAL_ROOT="$REPO_ROOT"
local_basis="repository root"
if [[ -z "${PERMISSION_STATE_FIXTURE_DIR:-}" ]]; then
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
  if [[ -n "$common_dir" ]]; then
    main_root="$(cd "$common_dir/.." 2>/dev/null && pwd)"
    if [[ -n "$main_root" && "$main_root" != "$REPO_ROOT" ]]; then
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
if [[ "$LOCAL_ROOT" != "$START_DIR" ]]; then
  case "${PERMISSION_STATE_OSTYPE-${OSTYPE:-}}" in
  msys* | cygwin* | win32*)
    LOCAL_ROOT="$START_DIR"
    local_basis="start directory (on Windows)"
    ;;
  *) ;;
  esac
fi
if [[ "$LOCAL_ROOT" != "$START_DIR" ]]; then
  owner_foreign=0
  if [[ -n "${PERMISSION_STATE_OWNER_OVERRIDE:-}" ]]; then
    [[ "$PERMISSION_STATE_OWNER_OVERRIDE" != "foreign" ]] || owner_foreign=1
  else
    for owned_path in "$LOCAL_ROOT" "$LOCAL_ROOT/.git" "$LOCAL_ROOT/.claude"; do
      if [[ -e "$owned_path" && ! -O "$owned_path" ]]; then owner_foreign=1; fi
    done
  fi
  if [[ "$owner_foreign" -eq 1 ]]; then
    LOCAL_ROOT="$START_DIR"
    local_basis="start directory (repository root or its .git/.claude is not owned by this user)"
  fi
fi

USER_CONFIG_ROOT="${CLAUDE_CONFIG_DIR:-${HOME:+$HOME/.claude}}"

MANAGED_FILE="$(mscope::base_file "${PERMISSION_STATE_MANAGED_PATH:-}")"
MANAGED_DROPIN="$(mscope::dropin_dir "${PERMISSION_STATE_MANAGED_PATH:-}")"


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
  crlf_strip <"$path" | jq -e '
    (.permissions | type) as $pt
    | if $pt == "null" then true
      elif $pt == "object" then
        [.permissions.allow, .permissions.ask, .permissions.deny]
        | all(. == null or type == "array")
      else false end
  ' >/dev/null 2>&1 || {
    printf 'invalid-json\n'
    return 0
  }
  printf 'present\n'
}

emit_rules_of_kind() {
  local scope="$1" surface="$2" noun="$3" kind="$4" rule
  while IFS= read -r rule; do
    [[ -n "$rule" ]] || continue
    case "$rule" in
    *"$NL_SENTINEL"*)
      note "$scope $surface $kind rule contains a literal newline or carriage return and cannot be represented as one record; reported here rather than split or silently stripped into text that matches no rule in the $noun: ${rule#"$NL_SENTINEL"}"
      ;;
    *) printf 'rule %s %s %s %s\n' "$scope" "$surface" "$kind" "$rule" ;;
    esac
  done < <(jq -r --arg k "$kind" --arg nl "$NL_SENTINEL" "$RULES_JQ" 2>/dev/null |
    tr -d '\r')
}

emit_file_rules() {
  [[ "$mode" == "full" ]] || return 0
  local scope="$1" surface="$2" path="$3" kind
  for kind in allow ask deny; do
    emit_rules_of_kind "$scope" "$surface" file "$kind" < <(crlf_strip <"$path")
  done
}

emit_file_conf() {
  [[ "$mode" == "full" ]] || return 0
  local scope="$1" surface="$2"
  jq -r '
    def emit($k; $v): "\($k) \($v)";
    [
      (if (.autoMode | type) == "object" and (.autoMode | has("classifyAllShell"))
         then emit("classifyAllShell"; .autoMode.classifyAllShell | tojson) else empty end),
      (if has("autoMode") then emit("autoModePresent"; "true") else empty end),
      (if (.permissions | type) == "object" and (.permissions | has("defaultMode"))
         then emit("defaultMode"; .permissions.defaultMode | tojson)
       elif has("defaultMode") then emit("defaultMode"; .defaultMode | tojson) else empty end),
      (if has("useAutoModeDuringPlan") then emit("useAutoModeDuringPlan"; .useAutoModeDuringPlan | tojson) else empty end),
      (if has("disableAutoMode") then emit("disableAutoMode"; .disableAutoMode | tojson) else empty end),
      (if (.permissions | type) == "object" and (.permissions | has("disableAutoMode"))
         then emit("permissions.disableAutoMode"; .permissions.disableAutoMode | tojson) else empty end),
      (if has("allowManagedPermissionRulesOnly")
         then emit("allowManagedPermissionRulesOnly"; .allowManagedPermissionRulesOnly | tojson) else empty end),
      (if has("prependPlugins")
         then emit("prependPluginsNamesGuard"; (.prependPlugins | type == "array"
           and any(.[]; . == "sec-default@builtin" or . == "cc-plugin-sec-default@builtin")) | tojson)
       else empty end),
      # Every level is type-checked before it is indexed: one jq error here
      # would empty the whole array, the managed lock record included.
      (if (.pluginConfigs | type) == "object"
          and (.pluginConfigs["cc-plugin-sec-default@builtin"] | type) == "object"
          and (.pluginConfigs["cc-plugin-sec-default@builtin"].options | type) == "object"
          and (.pluginConfigs["cc-plugin-sec-default@builtin"].options | has("allowModsToOverrideDenyRules"))
         then emit("modsOverrideDenyRules"; .pluginConfigs["cc-plugin-sec-default@builtin"].options.allowModsToOverrideDenyRules | tojson)
       else empty end)
    ] | .[]
  ' 2>/dev/null | tr -d '\r' | while IFS= read -r line; do
    [[ -n "$line" ]] && printf 'conf %s %s %s\n' "$scope" "$surface" "$line"
  done
  return 0
}

emit_json_scope() {
  local scope="$1" surface="$2" path="$3" status
  status="$(classify_json_file "$path")"
  emit "$scope" "$surface" "$status" "$path"
  case "$status:$scope" in
  invalid-json:managed)
    note "Managed source $surface at $path is not a JSON object. From Claude Code v2.1.259 a managed settings file or drop-in that cannot be parsed refuses startup (exit 1) and names the source. This is not silent non-enforcement."
    ;;
  invalid-json:user)
    note "User settings at $path are not valid JSON. An interactive session shows a Settings Error; after continue, /status names the file. A -p run skips the broken file. The retention sweep pauses and warns in /status unless managed settings supply cleanupPeriodDays."
    ;;
  invalid-json:*)
    note "Settings source $scope $surface at $path is not valid JSON. An interactive session shows a Settings Error; after continue, /status names the file. A -p run skips the broken file."
    ;;
  present:*)
    emit_file_rules "$scope" "$surface" "$path"
    emit_file_conf "$scope" "$surface" < <(crlf_strip <"$path")
    ;;
  *) ;;
  esac
  return 0
}


emit_json_scope managed file "$MANAGED_FILE"

if [[ -d "$MANAGED_DROPIN" ]]; then
  emit managed dropin-dir present "$MANAGED_DROPIN"
  while IFS= read -r dropin; do
    [[ -f "$dropin" ]] || continue
    case "${dropin##*/}" in .*) continue ;; *) ;; esac
    emit_json_scope managed "dropin-file:${dropin##*/}" "$dropin"
  done < <(find "$MANAGED_DROPIN" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort)
else
  emit managed dropin-dir absent "$MANAGED_DROPIN"
fi


registry_keys="${PERMISSION_STATE_REGISTRY_KEYS-$(mscope::registry_keys)}"
if [[ -z "$registry_keys" ]]; then
  emit managed registry not-applicable "-"
elif ! command -v reg >/dev/null 2>&1; then
  emit managed registry skipped "-"
  note "Windows managed policy not read: 'reg' is not on PATH. Every other scope below is unaffected; the managed result is incomplete, not empty."
else
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
    reg_json="$(reg_cmd query "$registry_path" /v Settings 2>/dev/null | tr -d '\r' |
      sed -n 's/.*REG_\(EXPAND_\)\{0,1\}SZ[[:space:]]*//p' | head -1)"
    if [[ -z "$reg_json" ]] || ! printf '%s' "$reg_json" | jq empty 2>/dev/null; then
      note "Windows managed policy key $registry_path carries a Settings value that did not parse as JSON. An HKLM value that is not a JSON object refuses startup (exit 1) and names the source (v2.1.259+). A malformed HKCU value does not refuse startup; it is a notice in /status and claude doctor. Reporting it as unread rather than as empty."
    else
      for kind in allow ask deny; do
        emit_rules_of_kind managed registry policy "$kind" < <(printf '%s' "$reg_json")
      done
      emit_file_conf managed registry < <(printf '%s' "$reg_json")
    fi
  fi
fi

plist_domain="${PERMISSION_STATE_PLIST_DOMAIN-$(mscope::plist_domain)}"
if [[ -z "$plist_domain" ]]; then
  emit managed plist not-applicable "-"
elif ! command -v defaults >/dev/null 2>&1; then
  emit managed plist skipped "-"
  note "macOS managed preferences not read: 'defaults' is not on PATH. Every other scope below is unaffected; the managed result is incomplete, not empty."
else
  if defaults read "$plist_domain" >/dev/null 2>&1; then
    emit managed plist present "$plist_domain"
    note "The managed-preferences domain $plist_domain is present. Its rules are NOT inventoried yet — this reader reports the surface, not its contents. A plist plutil reports as malformed refuses startup (exit 1) and names the source (v2.1.259+); this reader cannot see that failure."
  else
    emit managed plist absent "$plist_domain"
  fi
fi

remote_cache=""
if [[ -n "$USER_CONFIG_ROOT" ]]; then
  remote_cache="$(mscope::remote_cache_file "$USER_CONFIG_ROOT")"
  emit managed remote-cache "$(classify_json_file "$remote_cache")" "$remote_cache"
else
  emit managed remote-cache skipped "-"
fi
note "Server-managed settings are fetched at sign-in and cached at ${remote_cache:-the configuration directory remote-settings.json} (the managed remote-cache record above). The cache is user-writable and can be stale; this reader does not fold it into the effective set. The cache is not the live policy. 'managed' above means the local managed surfaces only. Run /status and read Setting sources plus the Organization policy line for why a policy did not load and which credential is in use; claude doctor shows the same Organization policy line."


if [[ -n "$USER_CONFIG_ROOT" ]]; then
  emit_json_scope user settings "$USER_CONFIG_ROOT/settings.json"
else
  emit user settings skipped "-"
  note "User scope not read: neither CLAUDE_CONFIG_DIR nor HOME is set, so ~/.claude could not be resolved."
fi

same_file() { [[ "$1" -ef "$2" || "$1" == "$2" ]]; }

emit_file_scope() {
  local scope="$1" path="$2" surface="${3:-settings}"
  if [[ -n "$USER_CONFIG_ROOT" ]] && same_file "$path" "$USER_CONFIG_ROOT/settings.json"; then
    emit "$scope" "$surface" not-applicable "$path"
    note "$scope scope skipped: $path is the user settings file (as when a session starts in the home directory, outside a repository), so it is reported once, as user, and no $scope-scope checks run on it."
    return 0
  fi
  emit_json_scope "$scope" "$surface" "$path"
}

emit_file_scope project "$PRIMARY_DIR/.claude/settings.json"
if [[ -n "$TOPLEVEL_SHARED" ]]; then
  emit_file_scope project "$TOPLEVEL_SHARED" toplevel
  note "$PRIMARY_DIR is below the repository root $REPO_ROOT. A Bash cd inside the project moves this reader without moving the session, so this directory may or may not be the session's primary working directory, and the reader reads both shared files: 'project settings' from here and 'project toplevel' from the root. Only the file in the directory the session started in, or last moved to with /cd, is in force, so the merged set can over-report one of these two files. If the session started in neither directory, its file is not read here: run this reader from the session's start directory. https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository"
else
  emit project toplevel not-applicable "-"
  note "project scope read from $PRIMARY_DIR, the reader's working directory, taken as the session's primary working directory. A repository root's .claude/settings.json does not apply to a session whose primary working directory is elsewhere."
fi
emit_file_scope local "$LOCAL_ROOT/.claude/settings.local.json"
note "local scope anchored on the $local_basis. The Agent SDK's resolveSettings() helper always reads the file from the starting directory; that is the helper's behavior, not a session property, and no documented environment variable identifies an Agent SDK or headless run, so this reader does not detect either."

if [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]]; then
  note "CLAUDE_CODE_REMOTE=true: this is a cloud session, which reads a DIFFERENT scope set than a local one. Your own machine's user settings and .claude/settings.local.json are not read at all, and a managed-settings.json file or MDM profile on your device does not reach it. A self-hosted environment's runner image can carry its own managed file, and a cloud thread in a project takes no permission rules from a repository's .claude/settings.json; this reader detects neither case, so read https://code.claude.com/docs/en/settings#settings-in-cloud-sessions before trusting the managed or project records above, and run /permissions in the session, which from Claude Code 2.1.319 says where the session's rules live. Any user scope reported above is this container's file, not yours."
fi

STARTDIR_LOCAL="$START_DIR/.claude/settings.local.json"
if [[ "$STARTDIR_LOCAL" == "$LOCAL_ROOT/.claude/settings.local.json" ]]; then
  emit startdir-local settings not-applicable "$STARTDIR_LOCAL"
else
  emit_json_scope startdir-local settings "$STARTDIR_LOCAL"
fi

exit 0
