#!/usr/bin/env bash
# Exit codes:
#   0  the operation succeeded
#   2  usage error, rejected argument, or a missing prerequisite (no
#      --plugin-data, no jq, no lib/state-key.sh)
#   3  `write` only: the findings payload is not well-formed JSON, is more than
#      one JSON document, or does not carry the shape `--implement` reads back.
#      Every problem is listed on stderr and NOTHING is written.
#   4  `read` only: no findings are persisted at this project's derived key.
#      This is an answer, not a failure, and it is deliberately distinct from 2
#      so a caller can tell "nothing audited yet" from "you called me wrong".
#   5  the persisted state is not in a usable condition: a history file, latest
#      pointer or findings file that exists but is not a readable regular file,
#      an incomplete publish (findings files with no pointer, or a `latest` that
#      could not be replaced), or a run id whose 99 suffixed names are all taken.
#      Distinct from 4 because UNREADABLE IS NOT ABSENT: reporting a state this
#      script cannot read as "nothing is persisted" is how an operator loses a
#      verdict set they already approved items from. Distinct from 2 because the
#      caller did nothing wrong.
set -uo pipefail

PROG="findings-state.sh"

COMPONENT="audit-automation-gaps"

SCHEMA_VERSION=1

CATEGORIES='["hooks","mcp","skills","subagents","scheduled"]'
VERDICTS='["PASS","CONDITIONAL","REJECT"]'

EXIT_PAYLOAD=3
EXIT_NO_ARTIFACT=4
EXIT_STATE=5

TMP_PAYLOAD=""
TMP_ENVELOPE=""
TMP_LATEST=""
RESERVED_TARGET=""

ARG_PLUGIN_DATA=""
ARG_ROOT=""
ARG_RUN_ID=""
ARG_FINDINGS=""
ARG_RUN_ID_GIVEN=0
ARG_FINDINGS_GIVEN=0
PLUGIN_DATA=""
STATE_KEY=""
BASE_DIR=""
HISTORY_FILE=""
LATEST_FILE=""

cleanup_tmp() {
  local f
  for f in "$TMP_PAYLOAD" "$TMP_ENVELOPE" "$TMP_LATEST"; do
    [[ -z "$f" ]] || rm -f "$f"
  done
  if [[ -n "$RESERVED_TARGET" ]] && [[ ! -s "$RESERVED_TARGET" ]]; then
    rm -f "$RESERVED_TARGET"
  fi
  return 0
}
trap cleanup_tmp EXIT

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

die_state() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "$EXIT_STATE"
}

preflight_state_file() {
  local path="$1" label="$2"
  if [[ -e "$path" ]] && [[ ! -f "$path" ]]; then
    die_state "$label exists but is not a regular file, so this run cannot be recorded and nothing was written: $path"
  fi
  if [[ -f "$path" ]] && [[ ! -w "$path" ]]; then
    die_state "$label exists but is not writable, so this run cannot be recorded and nothing was written: $path"
  fi
}

rollback_publish() {
  if [[ -n "$RESERVED_TARGET" ]]; then
    rm -f "$RESERVED_TARGET"
    RESERVED_TARGET=""
  fi
  die_state "$1"
}

usage() {
  cat <<'EOF'
findings-state.sh: persist and read back audit-automation-gaps verdicts.

  findings-state.sh paths --plugin-data <dir> [--root <path>]
  findings-state.sh write --plugin-data <dir> --findings <file|-> [--run-id <id>]
                          [--root <path>]
  findings-state.sh read  --plugin-data <dir> [--run-id <id>] [--root <path>]
  findings-state.sh list  --plugin-data <dir> [--root <path>]

--plugin-data is the resolved ${CLAUDE_PLUGIN_DATA} path. It is required because
that placeholder is not exported to the Bash tool; the skill substitutes it in
its own content and passes the result here.

--root derives the state key for that directory instead of the current one.
--run-id defaults, on write, to a UTC timestamp; on read, to the newest run.
--findings is the payload document, or `-` to read it from stdin.

paths  prints plugin_data=, state_key=, dir=, history=, latest=.
write  prints run_id=, state_key=, path=. Never overwrites a findings file.
read   prints one run's envelope JSON. Exit 4 when this project has none.
list   prints one JSON line per persisted run, oldest first, and nothing at all
       when this project has none.

Exit: 0 success; 2 usage or prerequisite; 3 rejected payload (write: not JSON,
more than one JSON document, or the wrong shape); 4 no artifact at this
project's key (read); 5 persisted state that exists but is not usable (a
history file, latest pointer or findings file that is not a readable regular
file, an incomplete publish, or 99 taken suffixes for one run id). 5 is not 4:
state this script cannot read is not state that is not there.
EOF
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%SZ; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required: the findings payload is a JSON document and this script will not half-check one"
  fi
}

validate_run_id() {
  local id="$1"
  if [[ -z "$id" ]]; then
    die "--run-id must not be empty"
  fi
  if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    die "--run-id must be a plain path segment matching [A-Za-z0-9][A-Za-z0-9_.-]*: $id"
  fi
  case "$id" in
  *..*) die "--run-id must not contain '..': $id" ;;
  *) : ;;
  esac
}

require_absolute_path() {
  local name="$1" value="$2"
  case "$value" in
  /* | ?:[\\/]*) : ;;
  *) die "$name must be an absolute path: $value" ;;
  esac
}

resolve_plugin_data() {
  local value="${1:-${CLAUDE_PLUGIN_DATA:-}}"
  if [[ -z "$value" ]]; then
    die "--plugin-data is required: \${CLAUDE_PLUGIN_DATA} is not exported to the Bash tool, so pass the path substituted into the skill text"
  fi
  require_absolute_path "--plugin-data" "$value"
  case "$value" in
  .. | ../* | ..[\\]* | *[/\\].. | *[/\\]..[/\\]*)
    die "--plugin-data must not contain a '..' path component: $value"
    ;;
  *) : ;;
  esac
  PLUGIN_DATA="$value"
}

derive_state_key() {
  local root="$1" plugin_root state_key_lib
  plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
  state_key_lib="$plugin_root/lib/state-key.sh"
  if [[ ! -f "$state_key_lib" ]]; then
    die "cannot find lib/state-key.sh at: $state_key_lib"
  fi
  if [[ -n "$root" ]]; then
    if [[ ! -d "$root" ]]; then
      die "--root is not a directory: $root"
    fi
    STATE_KEY=$(bash "$state_key_lib" --root "$root")
  else
    STATE_KEY=$(bash "$state_key_lib")
  fi
  if [[ -z "$STATE_KEY" ]]; then
    die "lib/state-key.sh produced no state key"
  fi
}

derive_repo_root() {
  local here="${1:-.}"
  (cd "$here" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || true
}

resolve_locations() {
  resolve_plugin_data "$1"
  derive_state_key "$2"
  BASE_DIR="$PLUGIN_DATA/$COMPONENT/$STATE_KEY"
  HISTORY_FILE="$BASE_DIR/history.jsonl"
  LATEST_FILE="$BASE_DIR/latest"
}

payload_problems_program() {
  cat <<JQ
def fields: ["id","candidate","category","verdict"];
def cats: $CATEGORIES;
def verds: $VERDICTS;
def check(\$i; \$c):
  ( fields
    | map(. as \$k
      | if (\$c | has(\$k) | not)
        then "candidate \(\$i): missing required field \"\(\$k)\""
        elif (\$c[\$k] | type) != "string"
        then "candidate \(\$i): \"\(\$k)\" must be a string"
        elif (\$c[\$k] | length) == 0
        then "candidate \(\$i): \"\(\$k)\" must not be empty"
        else empty
        end) )
  + ( if (\$c.category | type) == "string" and (cats | index(\$c.category)) == null
      then ["candidate \(\$i): \"category\" must be one of \(cats | join(", ")), got \"\(\$c.category)\""]
      else [] end )
  + ( if (\$c.verdict | type) == "string" and (verds | index(\$c.verdict)) == null
      then ["candidate \(\$i): \"verdict\" must be one of \(verds | join(", ")), got \"\(\$c.verdict)\""]
      else [] end )
  + ( if (\$c | has("evidence") | not)
      then ["candidate \(\$i): missing required field \"evidence\""]
      elif (\$c.evidence | type) != "array"
      then ["candidate \(\$i): \"evidence\" must be an array of strings"]
      elif (\$c.evidence | map(type) | any(. != "string"))
      then ["candidate \(\$i): \"evidence\" must be an array of strings"]
      else [] end )
  + ( if ((\$c.verdict == "PASS") or (\$c.verdict == "CONDITIONAL"))
         and ((\$c.plan | type) != "object")
      then ["candidate \(\$i): a \(\$c.verdict) verdict must carry a \"plan\" object, which is what --implement reads back"]
      else [] end );
def problems:
  if type != "object" then ["the findings payload must be a JSON object"]
  elif (has("candidates") | not) then ["the payload must carry a \"candidates\" array"]
  elif (.candidates | type) != "array" then ["\"candidates\" must be an array"]
  else
    ( .candidates
      | to_entries
      | map(if (.value | type) != "object"
            then ["candidate \(.key): must be an object"]
            else check(.key; .value)
            end)
      | add // [] )
  end;
problems | .[]
JQ
}

validate_payload() {
  local file="$1" problems documents
  if ! jq -e 'type' "$file" >/dev/null 2>&1; then
    printf '%s: the findings payload is not well-formed JSON\n' "$PROG" >&2
    jq . "$file" 2>&1 >/dev/null | head -5 >&2
    exit "$EXIT_PAYLOAD"
  fi
  documents=$(jq -s 'length' "$file" 2>/dev/null)
  if [[ "$documents" != "1" ]]; then
    printf '%s: the findings payload must be exactly one JSON document, and this stream carries %s.\n' \
      "$PROG" "${documents:-an unreadable number of}" >&2
    printf '%s: only the first document would be persisted, so nothing is written. Merge them before writing.\n' \
      "$PROG" >&2
    exit "$EXIT_PAYLOAD"
  fi
  problems=$(jq -r "$(payload_problems_program)" "$file")
  if [[ -n "$problems" ]]; then
    printf '%s: the findings payload does not carry the shape --implement reads back:\n' "$PROG" >&2
    printf '%s\n' "$problems" >&2
    exit "$EXIT_PAYLOAD"
  fi
}

parse_common_args() {
  local context="$1"
  shift
  ARG_PLUGIN_DATA=""
  ARG_ROOT=""
  ARG_RUN_ID=""
  ARG_FINDINGS=""
  ARG_RUN_ID_GIVEN=0
  ARG_FINDINGS_GIVEN=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --plugin-data)
      [[ $# -ge 2 ]] || die "--plugin-data needs a path"
      ARG_PLUGIN_DATA="$2"
      shift 2
      ;;
    --root)
      [[ $# -ge 2 ]] || die "--root needs a path"
      ARG_ROOT="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id needs a value"
      ARG_RUN_ID="$2"
      ARG_RUN_ID_GIVEN=1
      shift 2
      ;;
    --findings)
      [[ $# -ge 2 ]] || die "--findings needs a path or -"
      ARG_FINDINGS="$2"
      ARG_FINDINGS_GIVEN=1
      shift 2
      ;;
    *) die "unknown argument to $context: $1" ;;
    esac
  done
}

cmd_paths() {
  parse_common_args "paths" "$@"
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]] || [[ "$ARG_FINDINGS_GIVEN" -eq 1 ]]; then
    die "paths takes only --plugin-data and --root"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"
  printf 'plugin_data=%s\nstate_key=%s\ndir=%s\nhistory=%s\nlatest=%s\n' \
    "$PLUGIN_DATA" "$STATE_KEY" "$BASE_DIR" "$HISTORY_FILE" "$LATEST_FILE"
}

cmd_write() {
  parse_common_args "write" "$@"
  require_jq
  if [[ "$ARG_FINDINGS_GIVEN" -eq 0 ]]; then
    die "--findings is required: pass the payload document, or - to read it from stdin"
  fi
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    validate_run_id "$ARG_RUN_ID"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"

  mkdir -p "$BASE_DIR" || die "cannot create the findings directory: $BASE_DIR"

  TMP_PAYLOAD="$BASE_DIR/.payload.$$"
  TMP_ENVELOPE="$BASE_DIR/.envelope.$$"
  if [[ "$ARG_FINDINGS" == "-" ]]; then
    cat >"$TMP_PAYLOAD" || die "cannot stage the payload read from stdin"
  else
    if [[ ! -f "$ARG_FINDINGS" ]]; then
      die "--findings is not a file: $ARG_FINDINGS"
    fi
    cp "$ARG_FINDINGS" "$TMP_PAYLOAD" || die "cannot stage the payload: $ARG_FINDINGS"
  fi

  validate_payload "$TMP_PAYLOAD"

  local run_id="$ARG_RUN_ID"
  if [[ "$ARG_RUN_ID_GIVEN" -eq 0 ]]; then
    run_id=$(now_stamp)
  fi

  preflight_state_file "$HISTORY_FILE" "the history file"
  preflight_state_file "$LATEST_FILE" "the latest pointer"

  local target="" candidate="$run_id" suffix=1
  while :; do
    target="$BASE_DIR/findings-$candidate.json"
    if (set -C && : >"$target") 2>/dev/null; then
      break
    fi
    if [[ ! -e "$target" ]]; then
      die "cannot reserve the findings file: $target"
    fi
    suffix=$((suffix + 1))
    if [[ "$suffix" -gt 99 ]]; then
      die_state "all 99 suffixed findings names are taken for run id: $run_id"
    fi
    candidate="$run_id-$suffix"
  done
  run_id="$candidate"
  RESERVED_TARGET="$target"

  local written_at repo_root
  written_at=$(now_iso)
  repo_root=$(derive_repo_root "$ARG_ROOT")

  jq -n \
    --slurpfile payload "$TMP_PAYLOAD" \
    --argjson schema "$SCHEMA_VERSION" \
    --argjson verds "$VERDICTS" \
    --arg run_id "$run_id" \
    --arg written_at "$written_at" \
    --arg state_key "$STATE_KEY" \
    --arg repo_root "$repo_root" \
    --arg file "findings-$run_id.json" '
      ($payload[0]) as $p
      | ($p.candidates) as $c
      | {
          schema_version: $schema,
          run_id: $run_id,
          written_at: $written_at,
          state_key: $state_key,
          repo_root: $repo_root,
          file: $file,
          counts: ( {total: ($c | length)}
                    + ( $verds
                        | map(. as $v
                              | {key: ($v | ascii_downcase),
                                 value: ([$c[] | select(.verdict == $v)] | length)})
                        | from_entries ) ),
          findings: $p
        }' >"$TMP_ENVELOPE" || die "cannot compose the findings envelope"

  mv -f "$TMP_ENVELOPE" "$target" || rollback_publish "cannot publish the findings file: $target"
  TMP_ENVELOPE=""

  local line
  line=$(jq -c '{schema_version, run_id, written_at, state_key, file, counts}' "$target") ||
    rollback_publish "cannot compose the history line, so the findings file was rolled back: $target"
  printf '%s\n' "$line" >>"$HISTORY_FILE" ||
    rollback_publish "cannot append to the history file, so the findings file was rolled back: $HISTORY_FILE"
  RESERVED_TARGET=""

  TMP_LATEST="$LATEST_FILE.$$"
  printf '%s\n' "$run_id" >"$TMP_LATEST" ||
    die_state "run $run_id is published and recorded, but the latest pointer could not be staged. Read it with --run-id $run_id: $LATEST_FILE"
  mv -f "$TMP_LATEST" "$LATEST_FILE" ||
    die_state "run $run_id is published and recorded, but the latest pointer could not be replaced. Read it with --run-id $run_id: $LATEST_FILE"
  TMP_LATEST=""

  printf 'run_id=%s\nstate_key=%s\npath=%s\n' "$run_id" "$STATE_KEY" "$target"
}

no_artifact() {
  printf '%s: no findings are persisted for this project (state key %s) under %s\n' \
    "$PROG" "$STATE_KEY" "$BASE_DIR" >&2
  printf '%s: run the audit first. Nothing outside this key is read: an artifact with no project segment cannot be attributed to this one.\n' \
    "$PROG" >&2
  exit "$EXIT_NO_ARTIFACT"
}

refuse_orphans() {
  local missing="$1" file orphans=()
  for file in "$BASE_DIR"/findings-*.json; do
    if [[ -e "$file" ]]; then
      orphans+=("${file##*/}")
    fi
  done
  if [[ "${#orphans[@]}" -eq 0 ]]; then
    return 0
  fi
  printf '%s: %s is missing, but %d findings file(s) exist under %s. This is an INCOMPLETE PUBLISH, not an absence:\n' \
    "$PROG" "$missing" "${#orphans[@]}" "$BASE_DIR" >&2
  for file in "${orphans[@]}"; do
    printf '%s:   %s\n' "$PROG" "$file" >&2
  done
  printf '%s: read one directly with --run-id <id>, taking the id from the file name.\n' "$PROG" >&2
  exit "$EXIT_STATE"
}

require_readable_file() {
  local path="$1" label="$2"
  if [[ -e "$path" ]] && [[ ! -f "$path" ]]; then
    die_state "$label exists but is not a regular file, so it cannot be read (that is not the same as having none): $path"
  fi
  if [[ -f "$path" ]] && [[ ! -r "$path" ]]; then
    die_state "$label exists but cannot be read (that is not the same as having none): $path"
  fi
}

cmd_read() {
  parse_common_args "read" "$@"
  require_jq
  if [[ "$ARG_FINDINGS_GIVEN" -eq 1 ]]; then
    die "read does not take --findings"
  fi
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    validate_run_id "$ARG_RUN_ID"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"

  if [[ -e "$BASE_DIR" ]] && [[ ! -d "$BASE_DIR" ]]; then
    die_state "the findings directory exists but is not a directory, so nothing here can be read: $BASE_DIR"
  fi
  if [[ ! -d "$BASE_DIR" ]]; then
    no_artifact
  fi

  local run_id="$ARG_RUN_ID"
  if [[ -z "$run_id" ]]; then
    require_readable_file "$LATEST_FILE" "the latest pointer"
    if [[ ! -f "$LATEST_FILE" ]]; then
      refuse_orphans "the latest pointer"
      no_artifact
    fi
    run_id=$(tr -d '\r' <"$LATEST_FILE" | head -1)
    if [[ -z "$run_id" ]]; then
      die_state "the latest pointer is empty, so no run can be served by default: $LATEST_FILE"
    fi
    validate_run_id "$run_id"
  fi

  local target="$BASE_DIR/findings-$run_id.json"
  require_readable_file "$target" "the findings file for run id $run_id"
  if [[ ! -f "$target" ]]; then
    printf '%s: no findings file for run id %s at: %s\n' "$PROG" "$run_id" "$target" >&2
    exit "$EXIT_NO_ARTIFACT"
  fi
  if [[ ! -s "$target" ]]; then
    die_state "the findings file for run id $run_id is empty, so there is nothing to serve (a write may be in flight, or it was truncated): $target"
  fi
  if ! jq -e 'type == "object"' "$target" >/dev/null 2>&1; then
    die_state "the findings file for run id $run_id is not a JSON object, so it cannot be trusted (something outside this script wrote it): $target"
  fi
  cat "$target"
}

cmd_list() {
  parse_common_args "list" "$@"
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]] || [[ "$ARG_FINDINGS_GIVEN" -eq 1 ]]; then
    die "list takes only --plugin-data and --root"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"

  if [[ -e "$BASE_DIR" ]] && [[ ! -d "$BASE_DIR" ]]; then
    die_state "the findings directory exists but is not a directory, so nothing here can be listed: $BASE_DIR"
  fi
  require_readable_file "$HISTORY_FILE" "the history file"

  if [[ ! -f "$HISTORY_FILE" ]]; then
    refuse_orphans "the history file"
    printf '%s: no persisted runs for this project (state key %s)\n' "$PROG" "$STATE_KEY" >&2
    return 0
  fi
  cat "$HISTORY_FILE"
}

main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi
  local command="$1"
  shift
  case "$command" in
  -h | --help)
    usage
    exit 0
    ;;
  paths) cmd_paths "$@" ;;
  write) cmd_write "$@" ;;
  read) cmd_read "$@" ;;
  list) cmd_list "$@" ;;
  *)
    printf '%s: unknown command: %s\n' "$PROG" "$command" >&2
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
