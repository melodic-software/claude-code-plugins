#!/usr/bin/env bash
# Apply plugin drift fixes to .claude/settings.json based on
# check-plugin-drift.sh findings.
#
# Fix policy (audit Category E):
#
#   ORPHAN, enabled=false  ->  REMOVE from enabledPlugins, unless a
#                              lower-precedence scope file holds `true` for
#                              the key (see below). The entry references a
#                              plugin its marketplace no longer lists.
#
#   ORPHAN, enabled=true   ->  REPORT ONLY (manual review required)
#                              (user explicitly enabled a plugin that is now
#                              gone upstream; auto-removing silently breaks
#                              their intent. Surface and let them decide)
#
#   ORPHAN, any other value ->  REPORT ONLY (manual review required). Only an
#                              exact `false` is ever removed.
#
#   NEW upstream            ->  REPORT ONLY. Nothing is added: an absent entry
#                              and an explicit `false` are separate states, and
#                              the choice between them belongs to a person.
#
#   RENAME                  ->  REPORT ONLY. A catalog renames-map pair and a
#                              heuristic pair are both left for a person. This
#                              script writes nothing for either. A removed row
#                              is never turned into a rename to null.
#
#   REMOVED                 ->  REPORT ONLY. A null entry in the catalog
#                              renames map. Not an orphan, so it is not removed.
#
# Modes:
#   --dry-run  (default)   print plan, no writes
#   --yes      / -y        apply the removals
#   --input <path>         consume existing JSON from check-plugin-drift.sh
#                          (otherwise re-runs the check internally)
#   --help                 print usage
#
# Env overrides:
#   CLAUDE_SETTINGS_FILE    path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR forwarded to check-plugin-drift.sh
#   CLAUDE_CONFIG_DIR, HOME locate the user settings file for the guard below
#
# Apply behavior:
#   A check that fails is fatal. The run never reports an audit it did not
#   complete. Findings with no audited marketplace, because none is declared or
#   every one was skipped, say so instead of reporting no drift, and every
#   skipped marketplace is listed with its reason.
#   Findings that are not exactly one array of marketplace blocks, or a list jq
#   cannot read from them, are fatal. Keys travel as JSON arrays from the
#   findings through the filter to the edit, so a key holding a carriage return
#   or any other character is removed exactly. Displayed entries print control
#   characters as `?`.
#   Removals are filtered against one snapshot of the settings file before the
#   plan is rendered: a removal whose key is absent is dropped, and one whose
#   key no longer holds exactly false moves to manual review. When a removal is pending, a
#   settings file that is not valid JSON or whose enabledPlugins is not an
#   object is fatal, on a dry run too.
#   Lower-precedence guard, on a dry run too: removing a `false` lets a lower
#   scope's value take effect. The lower-precedence files are the user settings
#   file (CLAUDE_CONFIG_DIR, else HOME/.claude) and, when the audited file is
#   settings.local.json, its sibling settings.json. A `true` for the key in
#   any of them moves the removal to manual review. One that exists but cannot
#   be read, is not valid JSON, or whose enabledPlugins is not an object sends
#   every removal to manual review, as does an unresolvable user directory.
#   Other developers' user scopes and managed settings are not checked, and a
#   plan with a pending removal says so.
#   The edit, the line-ending measurement and the backup all come from that
#   snapshot. An apply is refused when the settings file no longer matches it
#   just before the replace, because another writer changed it after the plan
#   was computed; the backup this run just wrote is removed when it is still a
#   regular file. The window between that compare and the replace is not
#   closed.
#   The settings file is copied to a new file named
#   <settings>.bak.<UTC stamp>.<random>. The name comes from mktemp -u, is
#   refused when anything already exists there, and is written on one exclusive
#   open (bash noclobber, O_CREAT|O_EXCL) under umask 077, so 0600 wherever the
#   platform honors mode bits (MSYS does not). Nothing is written until the
#   open descriptor is a regular file that is the one at the name, so no link
#   planted there, before or after the check, is written through. Nothing is
#   replaced unless that copy is a regular non-symlink file equal to the
#   snapshot.
#   The file's own line-ending style survives the jq round trip.
#   An apply is refused when the project-root ladder resolved the path to the
#   user settings file. Set CLAUDE_SETTINGS_FILE to write that file on purpose.
#   An apply is refused when the settings path is a symlink, because the
#   replacement is a rename and would replace the link itself.
#   A read-only settings file is still applied, and comes back read-only on
#   platforms that honor mode bits.
#   A staged replacement identical to the snapshot is refused. The filter
#   leaves only entries that change the file, so this refusal is defensive.
#   "Applied" is printed only after the settings file is read back and found to
#   hold the edit. Any failure before that is fatal, and an interrupting signal
#   ends the run rather than letting it continue with its temporaries deleted.

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
    # Two expressions, not GNU's `\?`: BSD sed has no optional-quantifier escape.
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# //' -e 's/^#//'
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
  # Initialized here so ShellCheck SC2154 sees the assignment; the ladder fills it in.
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

# Initialized here so ShellCheck SC2154 sees the assignment. Read by the
# lower-precedence guard and by the user-settings guard.
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

# One cleanup, installed once, for every temp this run can create. `rm -f ""` is
# a silent no-op, so an unset path costs nothing.
#
# The signal traps EXIT the script; they do not merely delete. A trap that only
# removed files let an interrupted run CONTINUE with its temps gone, and every
# step after that worked on a stage still holding the original bytes, so the run
# printed "Applied" and changed nothing.
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
  # 0 is "no orphan", 1 is "orphan found" (advisory). Anything else is fatal.
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

# Exactly one document, an array of marketplace blocks, each an object. `-s`
# gathers every document, because `jq -e` alone judges only the last one and a
# file holding an object followed by `[]` would pass; a zero-byte file slurps to
# an empty list. The element test is phrased as `!=` so no jq call before the
# post-edit validation carries that validation's text.
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

# count <json-array> - its length. -j appends no terminator, so there is no
# carriage return to strip on a native-Windows jq.
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
  # One array of enabledPlugins maps, in the order the files were found. With
  # no file, `-n` without inputs so jq never waits on stdin.
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

# The replacement is staged beside the settings file, not under $TMPDIR: /tmp is
# commonly a separate mount, where the final `mv` degrades to a copy plus an
# unlink and an interruption leaves the settings file truncated. A
# same-directory temp makes the last step a rename, which is atomic.
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

# `jq empty` exits 0 on a zero-byte file, so it cannot tell valid JSON from
# nothing written at all. A settings file is always an object, so the stronger
# predicate costs nothing and catches a truncated write.
if ! jq -e 'type == "object"' "$TMP_SETTINGS" >/dev/null 2>&1; then
  echo "ERROR: post-edit JSON invalid, settings unchanged" >&2
  exit 2
fi

# Copy the original onto the stage so the replacement inherits its mode and not
# mktemp's 0600. The content that lands here is overwritten below; only the mode
# survives, which is the point.
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
  # A read loop, not `sed 's/$/\r/'`: BSD sed reads \r as a literal r. The
  # `|| [[ -n "$line" ]]` arm keeps a final line that carries no terminator.
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
# Status 4 is the only one after this run created the file; any other failure
# leaves what is at the name alone, because it is not this run's.
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
