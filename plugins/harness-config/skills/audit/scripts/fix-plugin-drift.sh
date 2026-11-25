#!/usr/bin/env bash

# The jq programs below are single-quoted on purpose: $name is a jq variable.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


MODE="dry-run"
INPUT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --yes | -y)
    MODE="apply"
    shift
    ;;
  --dry-run)
    MODE="dry-run"
    shift
    ;;
  --input)
    if [[ $# -lt 2 ]]; then
      echo "Missing value for --input" >&2
      exit 2
    fi
    INPUT_JSON="$2"
    shift 2
    ;;
  --help | -h)
    cat <<'EOF'
Apply plugin drift fixes to .claude/settings.json from check-plugin-drift.sh findings:
remove ORPHAN entries set to exactly false; report everything else for a person.

  --dry-run  (default)   print the plan, write nothing
  --yes      / -y        apply the removals
  --input <path>         read check-plugin-drift.sh JSON instead of re-running the check
  --help                 print this usage

Env: CLAUDE_SETTINGS_FILE (project settings.json), SETTINGS_AUDIT_FIXTURE_DIR
(forwarded to check-plugin-drift.sh), CLAUDE_CONFIG_DIR and HOME (user settings).

Exit: 0 plan printed or applied; non-zero on any failed check, refused apply or
failed read-back.
EOF
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    exit 2
    ;;
  esac
done


PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
source "$RESOLVE_SCOPES_LIB"

if [[ -n "${CLAUDE_SETTINGS_FILE:-}" ]]; then
  SETTINGS="$CLAUDE_SETTINGS_FILE"
  SETTINGS_FROM_LADDER=0
else
  PROJECT_ROOT=""
  scopes::project_root_to PROJECT_ROOT
  SETTINGS="$PROJECT_ROOT/.claude/settings.json"
  SETTINGS_FROM_LADDER=1
fi
SETTINGS_SHOW="${SETTINGS//[[:cntrl:]]/?}"

if [[ ! -f "$SETTINGS" ]]; then
  echo "ERROR: settings file not found: $SETTINGS_SHOW" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

USER_DIR=""
scopes::user_dir_to USER_DIR


if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

JQ_DEFS='def san: tostring | gsub("[[:cntrl:]]"; "?");'

settings_file_is_managed() {
  local base parent
  base=$(basename -- "$SETTINGS")
  parent=$(basename -- "$(dirname -- "$SETTINGS")")
  [[ "$base" == "managed-settings.json" || "$base" == "remote-settings.json" || "$parent" == "managed-settings.d" ]]
}

print_remediation() {
  if settings_file_is_managed; then
    printf '  %s\n' "update managed enabledPlugins"
  else
    printf '  %s\n' "$1"
  fi
}


TMP_JSON=""
TMP_SETTINGS=""
TMP_EOL=""
SNAPSHOT=""
LOWER_JSON=""

# shellcheck disable=SC2329  # invoked by the traps installed immediately below
cleanup_temps() {
  rm -f "${TMP_JSON:-}" "${TMP_SETTINGS:-}" "${TMP_EOL:-}" "${SNAPSHOT:-}" "${LOWER_JSON:-}"
}
trap cleanup_temps EXIT
trap 'cleanup_temps; exit 130' INT
trap 'cleanup_temps; exit 143' TERM HUP

if [[ -z "$INPUT_JSON" ]]; then
  TMP_JSON=$(mktemp "${TMPDIR:-/tmp}/plugin-drift-json-XXXXXX")
  printf '%sRunning check-plugin-drift.sh...%s\n' "$CYAN" "$RESET" >&2
  check_status=0
  SETTINGS_AUDIT_OUTPUT_JSON="$TMP_JSON" CLAUDE_SETTINGS_FILE="$SETTINGS" \
    bash "$SCRIPT_DIR/check-plugin-drift.sh" >/dev/null || check_status=$?
  if [[ "$check_status" -gt 1 ]]; then
    echo "ERROR: check-plugin-drift.sh failed with status $check_status, so no findings were produced" >&2
    exit 2
  fi
  if [[ "$check_status" -eq 1 && ! -s "$TMP_JSON" ]]; then
    echo "ERROR: check-plugin-drift.sh reported drift but wrote no findings document" >&2
    exit 2
  fi
  if [[ ! -s "$TMP_JSON" ]]; then
    echo "NOTE: check-plugin-drift.sh produced no findings document, so no marketplace was audited" >&2
    if ! printf '[]\n' >"$TMP_JSON"; then
      echo "ERROR: cannot write the empty findings document: $TMP_JSON" >&2
      exit 2
    fi
  fi
  INPUT_JSON="$TMP_JSON"
fi

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "ERROR: findings JSON not found: $INPUT_JSON" >&2
  exit 2
fi

if ! jq -s -e 'length == 1 and (.[0] | type == "array" and (any(.[]; type != "object") | not))' \
  "$INPUT_JSON" >/dev/null 2>&1; then
  echo "ERROR: findings JSON is not an array of marketplace blocks: $INPUT_JSON" >&2
  exit 2
fi


findings() {
  local out
  out=$(jq -c "[.[] | select(.status == \"ok\") | $1] | unique" "$INPUT_JSON") || return 1
  printf '%s' "${out%$'\r'}"
}

findings_failed() {
  echo "ERROR: cannot read the $1 list from the findings JSON: $INPUT_JSON" >&2
  exit 2
}

count() {
  jq -j 'length' <<<"$1"
}

remove_json=$(findings '.orphans[] | select(.enabled == false) | "\(.name)@\(.marketplace)"') ||
  findings_failed "orphan removals"

manual_json=$(findings '.orphans[] | select(.enabled != false)
  | {key: "\(.name)@\(.marketplace)",
     why: (if .enabled == true then "true in this file" else "neither true nor false in this file" end)}') ||
  findings_failed "enabled orphans"

new_json=$(findings '.new_upstream[] | "\(.name)@\(.marketplace)"') ||
  findings_failed "new upstream"

catalog_rename_json=$(findings '.renames[] | select((.to | type == "string") and .source == "renames") | "\(.from) -> \(.to)  (\(.marketplace))"') ||
  findings_failed "renames"
heuristic_rename_json=$(findings '.renames[] | select((.to | type == "string") and .source != "renames") | "\(.from) -> \(.to)  (\(.marketplace))"') ||
  findings_failed "renames"

removed_json=$(findings '.removed[]? | "\(.name)@\(.marketplace)"') ||
  findings_failed "removed"

skipped_json=$(jq -c '[.[] | select(.status != "ok")
  | "\(.key // "") (\(.skip_reason // "no reason given"))"]' "$INPUT_JSON") ||
  findings_failed "marketplace status"

remove_count=$(count "$remove_json")
manual_count=$(count "$manual_json")
new_count=$(count "$new_json")
catalog_rename_count=$(count "$catalog_rename_json")
heuristic_rename_count=$(count "$heuristic_rename_json")
rename_count=$((catalog_rename_count + heuristic_rename_count))
removed_count=$(count "$removed_json")
skipped_count=$(count "$skipped_json")
ok_count=$(jq -j '[.[] | select(.status == "ok")] | length' "$INPUT_JSON") ||
  findings_failed "marketplace status"


print_list() {
  local indent="$1" entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '%s- %s\n' "$indent" "$entry"
  done < <(jq -r "$JQ_DEFS .[] | $3" <<<"$2" | tr -d '\r')
}

printf '\n%sPlugin drift fix plan%s (mode: %s)\n' "$CYAN" "$RESET" "$MODE"
printf 'Settings file: %s\n\n' "$SETTINGS_SHOW"

if [[ "$skipped_count" -gt 0 ]]; then
  printf '%sSKIPPED%s %d marketplaces not audited:\n' "$YELLOW" "$RESET" "$skipped_count"
  print_list '  ' "$skipped_json" 'san'
  echo
fi

if [[ "$ok_count" -eq 0 ]]; then
  printf '%sNo marketplace was audited, so there is nothing to report.%s\n' "$YELLOW" "$RESET"
  exit 0
fi

if [[ "$remove_count" -eq 0 && "$manual_count" -eq 0 && "$new_count" -eq 0 && "$rename_count" -eq 0 && "$removed_count" -eq 0 ]]; then
  printf '%sNo drift detected, nothing to do.%s\n' "$GREEN" "$RESET"
  exit 0
fi


LOWER_FILES=()
LOWER_CLOSED=""
lower_scope_files() {
  local candidates=() f
  if [[ "$(basename "$SETTINGS")" == "settings.local.json" ]]; then
    candidates+=("$(dirname "$SETTINGS")/settings.json")
  fi
  if [[ -n "$USER_DIR" ]]; then
    [[ "$SETTINGS" -ef "$USER_DIR/settings.json" ]] || candidates+=("$USER_DIR/settings.json")
  else
    LOWER_CLOSED="no user config directory could be resolved (CLAUDE_CONFIG_DIR and HOME are unset)"
  fi
  local d
  for f in "${candidates[@]+"${candidates[@]}"}"; do
    if [[ ! -e "$f" && ! -L "$f" ]]; then
      d=$(dirname "$f")
      while [[ ! -e "$d" && ! -L "$d" && "$d" != "$(dirname "$d")" ]]; do
        d=$(dirname "$d")
      done
      if [[ -d "$d" && ! -x "$d" ]]; then
        LOWER_CLOSED="cannot search $d to tell whether $f exists"
      fi
      continue
    fi
    if [[ ! -f "$f" || ! -r "$f" ]]; then
      LOWER_CLOSED="cannot read $f"
      continue
    fi
    if ! jq -s -e 'length == 1 and (.[0]
      | if type != "object" then false
        elif has("enabledPlugins") then (.enabledPlugins | type != "object" | not)
        else true end)' "$f" >/dev/null 2>&1; then
      LOWER_CLOSED="$f is not valid JSON or its enabledPlugins is not an object"
      continue
    fi
    LOWER_FILES+=("$f")
  done
}

filtered_count=0
if [[ "$remove_count" -gt 0 ]]; then
  SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/settings-snapshot-XXXXXX") || SNAPSHOT=""
  if [[ -z "$SNAPSHOT" ]]; then
    echo "ERROR: cannot create a snapshot under ${TMPDIR:-/tmp}, settings unchanged" >&2
    exit 2
  fi
  if ! cat "$SETTINGS" >"$SNAPSHOT"; then
    echo "ERROR: cannot snapshot $SETTINGS_SHOW, settings unchanged" >&2
    exit 2
  fi

  lower_scope_files
  LOWER_JSON=$(mktemp "${TMPDIR:-/tmp}/settings-lower-XXXXXX") || LOWER_JSON=""
  if [[ -z "$LOWER_JSON" ]]; then
    echo "ERROR: cannot create a working file under ${TMPDIR:-/tmp}, settings unchanged" >&2
    exit 2
  fi
  lower_ok=1
  if [[ "${#LOWER_FILES[@]}" -gt 0 ]]; then
    jq -n '[inputs | .enabledPlugins // {}]' "${LOWER_FILES[@]}" >"$LOWER_JSON" || lower_ok=0
  else
    jq -n '[]' >"$LOWER_JSON" || lower_ok=0
  fi
  if [[ "$lower_ok" -ne 1 ]]; then
    echo "ERROR: cannot read the lower-precedence scope files, settings unchanged" >&2
    exit 2
  fi
  closed=0
  [[ -n "$LOWER_CLOSED" ]] && closed=1

  if ! plan=$(jq -c --slurpfile s "$SNAPSHOT" --slurpfile lw "$LOWER_JSON" --argjson closed "$closed" '
    . as $rm
    | ($s | if length != 1 then error("the settings file is not one JSON document") else .[0] end)
    | if type != "object" then error("the settings file is not a JSON object") else . end
    | (.enabledPlugins // {}) as $ep
    | if ($ep | type) != "object" then error("enabledPlugins is not an object") else . end
    | [$rm[] | . as $k
        | if ($ep | has($k) | not) then {k: $k, to: "drop", f: true}
          elif $ep[$k] == true then {k: $k, to: "manual", why: "now true in this file", f: true}
          elif $ep[$k] != false then {k: $k, to: "manual", why: "now neither true nor false in this file", f: true}
          elif $closed == 1 then {k: $k, to: "manual", why: "a lower-precedence scope file could not be checked"}
          elif any($lw[0][]; .[$k] == true) then
            {k: $k, to: "manual", why: "true in a lower-precedence scope file; removing this entry would enable it"}
          else {k: $k, to: "remove"} end] as $c
    | {remove: [$c[] | select(.to == "remove") | .k],
       manual: [$c[] | select(.to == "manual") | {key: .k, why}],
       filtered: ([$c[] | select(.f)] | length)}
  ' <<<"$remove_json"); then
    echo "ERROR: cannot read $SETTINGS_SHOW to filter the plan against it" >&2
    exit 2
  fi

  remove_json=$(jq -c '.remove' <<<"$plan") || remove_json=""
  manual_json=$(jq -c -s '.[0] + .[1].manual | unique' <<<"$manual_json"$'\n'"$plan") || manual_json=""
  filtered_count=$(jq -j '.filtered' <<<"$plan") || filtered_count=""
  if [[ -z "$remove_json" || -z "$manual_json" || -z "$filtered_count" ]]; then
    echo "ERROR: cannot read the filtered plan, settings unchanged" >&2
    exit 2
  fi
  remove_json="${remove_json%$'\r'}"
  remove_count=$(count "$remove_json")
  manual_count=$(count "$manual_json")
fi

if [[ -n "$LOWER_CLOSED" ]]; then
  printf '%sNOTE%s %s, so every orphan removal is held for manual review.\n\n' \
    "$YELLOW" "$RESET" "${LOWER_CLOSED//[[:cntrl:]]/?}"
fi

if [[ "$remove_count" -gt 0 ]]; then
  printf '%sAUTO-REMOVE%s %d orphan entries (enabled=false):\n' "$YELLOW" "$RESET" "$remove_count"
  print_list '  ' "$remove_json" 'san'
  if [[ "${#LOWER_FILES[@]}" -gt 0 ]]; then
    printf '  Checked for a true this removal would expose: %s\n' "${LOWER_FILES[*]//[[:cntrl:]]/?}"
  else
    printf '  No lower-precedence scope file exists on this machine to check.\n'
  fi
  printf '  Not checked: other developers'\'' user scopes and managed settings. A shared\n'
  printf '  project file'\''s false can be what keeps a plugin off for them.\n'
  echo
fi

if [[ "$new_count" -gt 0 ]]; then
  printf '%sNEW (report only)%s %d upstream plugins with no entry in the settings file:\n' "$CYAN" "$RESET" "$new_count"
  print_list '  ' "$new_json" 'san'
  echo
fi

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sMANUAL REVIEW%s %d orphan entries left for a person to decide:\n' "$RED" "$RESET" "$manual_count"
  printf '  Removing these could change which plugins load, so they are surfaced only:\n'
  print_list '    ' "$manual_json" '"\(.key | san) (\(.why))"'
  echo
fi

if [[ "$catalog_rename_count" -gt 0 ]]; then
  printf '%sRENAME%s %d catalog renames (report only, nothing is written):\n' "$YELLOW" "$RESET" "$catalog_rename_count"
  print_list '  ' "$catalog_rename_json" 'san'
  print_remediation "replace the key in this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
  echo
fi

if [[ "$heuristic_rename_count" -gt 0 ]]; then
  printf '%sRENAME?%s %d possible rename pairs (heuristic, review manually):\n' "$YELLOW" "$RESET" "$heuristic_rename_count"
  print_list '  ' "$heuristic_rename_json" 'san'
  printf '  %s\n' "confirm before editing the key"
  echo
fi

if [[ "$removed_count" -gt 0 ]]; then
  printf '%sREMOVED (report only)%s %d entries the catalog renames map marks removed:\n' "$YELLOW" "$RESET" "$removed_count"
  print_list '  ' "$removed_json" 'san'
  print_remediation "remove the key from this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
  echo
fi

if [[ "$filtered_count" -gt 0 ]]; then
  printf '%sFILTERED%s %d plan entries no longer match the settings file\n\n' "$YELLOW" "$RESET" "$filtered_count"
fi

if [[ "$remove_count" -eq 0 ]]; then
  printf '%sNothing to apply%s (no pending removal).\n' "$YELLOW" "$RESET"
  exit 0
fi


if [[ "$MODE" != "apply" ]]; then
  printf '%sDry-run only.%s Re-run with %s--yes%s to apply the removals.\n' \
    "$YELLOW" "$RESET" "$CYAN" "$RESET"
  exit 0
fi

if [[ -L "$SETTINGS" ]]; then
  echo "ERROR: the settings path is a symlink, $SETTINGS_SHOW" >&2
  echo "The replacement is a rename and would replace the link itself. Point CLAUDE_SETTINGS_FILE at the file the link resolves to." >&2
  exit 2
fi

user_candidates=()
[[ -n "$USER_DIR" ]] && user_candidates+=("$USER_DIR")
[[ -n "${HOME:-}" ]] && user_candidates+=("$HOME/.claude")
if [[ "${#user_candidates[@]}" -eq 0 ]]; then
  echo "NOTE: no user config directory could be resolved, so the user-settings guard checked nothing" >&2
fi
for candidate in "${user_candidates[@]+"${user_candidates[@]}"}"; do
  [[ "$SETTINGS" -ef "$candidate/settings.json" ]] || continue
  if [[ "$SETTINGS_FROM_LADDER" -eq 1 ]]; then
    echo "ERROR: the project-root ladder resolved to the user settings file, $SETTINGS_SHOW" >&2
    echo "This script writes project scope. Run it from the project, or set CLAUDE_SETTINGS_FILE to the file you mean." >&2
    exit 2
  fi
  echo "WARNING: CLAUDE_SETTINGS_FILE points at the user settings file, $SETTINGS_SHOW" >&2
  echo "The guard that would refuse this target is waived because the path was given explicitly." >&2
  break
done

TMP_SETTINGS=$(mktemp "${TMPDIR:-/tmp}/settings-json-XXXXXX")

if [[ -z "$TMP_SETTINGS" ]]; then
  echo "ERROR: cannot create a working copy under ${TMPDIR:-/tmp}, settings unchanged" >&2
  exit 2
fi

TMP_EOL=$(mktemp "$(dirname "$SETTINGS")/.settings-json-XXXXXX")
if [[ -z "$TMP_EOL" ]]; then
  echo "ERROR: cannot stage a replacement beside $SETTINGS_SHOW, settings unchanged" >&2
  exit 2
fi

if ! jq --slurpfile s "$SNAPSHOT" '
  . as $rm | $s[0] | reduce $rm[] as $k (.; del(.enabledPlugins[$k]))
' <<<"$remove_json" >"$TMP_SETTINGS"; then
  echo "ERROR: jq filter failed, settings unchanged" >&2
  exit 2
fi

if ! jq -e 'type == "object"' "$TMP_SETTINGS" >/dev/null 2>&1; then
  echo "ERROR: post-edit JSON invalid, settings unchanged" >&2
  exit 2
fi

if ! cp -p "$SETTINGS" "$TMP_EOL"; then
  echo "ERROR: cannot stage the replacement beside $SETTINGS_SHOW, settings unchanged" >&2
  exit 2
fi

SETTINGS_WAS_WRITABLE=1
[[ -w "$SETTINGS" ]] || SETTINGS_WAS_WRITABLE=0
if ! chmod u+w "$TMP_EOL"; then
  echo "ERROR: cannot make the staged replacement writable, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

cr=$(tr -dc '\r' <"$SNAPSHOT" | wc -c) || cr=""
lf=$(tr -dc '\n' <"$SNAPSHOT" | wc -c) || lf=""
if [[ -z "$cr" || -z "$lf" ]]; then
  echo "ERROR: cannot measure the settings file's line endings, settings unchanged" >&2
  exit 2
fi

if [[ "$cr" -gt 0 && "$cr" -ge "$lf" ]]; then
  if ! {
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s\r\n' "${line%$'\r'}"
    done <"$TMP_SETTINGS" >"$TMP_EOL"
  }; then
    echo "ERROR: cannot write the staged replacement, settings unchanged: $TMP_EOL" >&2
    exit 2
  fi
elif ! tr -d '\r' <"$TMP_SETTINGS" >"$TMP_EOL"; then
  echo "ERROR: cannot write the staged replacement, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

if ! jq -e 'type == "object"' "$TMP_EOL" >/dev/null 2>&1; then
  echo "ERROR: line-ending normalization produced invalid JSON, settings unchanged" >&2
  exit 2
fi

if cmp -s "$SNAPSHOT" "$TMP_EOL"; then
  echo "ERROR: the staged replacement is identical to the settings file as read for the plan, so the edit did not reach it; settings unchanged" >&2
  exit 2
fi

if [[ "$SETTINGS_WAS_WRITABLE" -eq 0 ]] && ! chmod u-w "$TMP_EOL"; then
  echo "ERROR: cannot restore the read-only mode on the staged replacement, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ) || STAMP=""
if [[ -z "$STAMP" ]]; then
  echo "ERROR: cannot read the clock for the backup name, settings unchanged" >&2
  exit 2
fi

remove_own_backup() {
  [[ -f "$BACKUP" && ! -L "$BACKUP" ]] && rm -f "$BACKUP"
}

BACKUP=$(mktemp -u "$SETTINGS.bak.$STAMP.XXXXXX") || BACKUP=""
if [[ -z "$BACKUP" ]]; then
  echo "ERROR: cannot name a backup beside $SETTINGS_SHOW, settings unchanged" >&2
  exit 2
fi
BACKUP_SHOW="${BACKUP//[[:cntrl:]]/?}"
if [[ -e "$BACKUP" || -L "$BACKUP" ]]; then
  echo "ERROR: something already exists at the backup name, settings unchanged: $BACKUP_SHOW" >&2
  exit 2
fi
write_rc=0
(
  set -C
  umask 077
  exec 3>"$BACKUP" || exit 3
  [[ -f /dev/fd/3 && ! -L "$BACKUP" && /dev/fd/3 -ef "$BACKUP" ]] || exit 3
  cat "$SNAPSHOT" >&3 || exit 4
) 2>/dev/null || write_rc=$?
if [[ "$write_rc" -ne 0 ]]; then
  [[ "$write_rc" -eq 4 ]] && remove_own_backup
  echo "ERROR: cannot write the backup on an exclusive open, settings unchanged: $BACKUP_SHOW" >&2
  exit 2
fi
if [[ ! -f "$BACKUP" || -L "$BACKUP" ]] || ! cmp -s "$SNAPSHOT" "$BACKUP"; then
  echo "ERROR: the backup at $BACKUP_SHOW is not a regular file holding the settings as read for the plan; settings unchanged" >&2
  exit 2
fi

if ! cmp -s "$SNAPSHOT" "$SETTINGS"; then
  remove_own_backup
  echo "ERROR: $SETTINGS_SHOW changed after the plan was computed, so another writer's edit would be lost; settings left as that writer left them, no backup kept" >&2
  exit 2
fi

if ! mv "$TMP_EOL" "$SETTINGS"; then
  echo "ERROR: cannot replace $SETTINGS_SHOW; it is unchanged and backed up at $BACKUP_SHOW" >&2
  exit 2
fi
TMP_EOL=""

if ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || cmp -s "$BACKUP" "$SETTINGS"; then
  echo "ERROR: $SETTINGS_SHOW does not hold the edited document after the replace; the pre-apply copy is at $BACKUP_SHOW" >&2
  exit 2
fi

printf '%sApplied:%s %d removals to %s (backup: %s)\n' "$GREEN" "$RESET" \
  "$remove_count" "$SETTINGS_SHOW" "$BACKUP_SHOW"

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sManual review still required for %d orphan entries (see above).%s\n' \
    "$RED" "$manual_count" "$RESET"
fi

exit 0
