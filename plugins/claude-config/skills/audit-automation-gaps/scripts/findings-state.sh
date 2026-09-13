#!/usr/bin/env bash
# findings-state.sh: persistence for audit-automation-gaps verdicts, so
# `--implement` in a LATER session can read back what a run decided.
#
# WHY THIS EXISTS. The skill takes an `--implement` flag and its Phase 4 acts on
# "user-selected items", but nothing persisted the verdict table, the evidence
# behind each verdict, or the implementation plans a PASS carries. An audit run
# and the implement run that acts on it are two sessions, so without a durable
# artifact `--implement` has nothing to read and the operator re-runs the whole
# audit to recover what was already decided (issue #4146, item 5).
#
# NAMING. `findings-state.sh`, not `findings.sh`: this is the state store for one
# component, the same role `audit-pass`'s `scripts/run-state.sh` fills for that
# skill, and it is the file this one is modelled on. `emit-findings.sh` in
# `audit-instructions` is a different job (composing a report body from scanner
# output) and deliberately resolves no home of its own.
#
# KEYING, WHICH IS NOT OPTIONAL. Everything is written under
#
#   <plugin-data>/audit-automation-gaps/<state-key>/
#
# where `<state-key>` comes from `lib/state-key.sh` and nothing else. That is
# rule 1 of docs/conventions/plugin-data-report-keying/README.md, and the reason
# is the whole point of this file: `${CLAUDE_PLUGIN_DATA}` is keyed to the plugin
# identifier alone, so an unkeyed findings file is one file per MACHINE and a
# later `--implement` would be served another repository's approved items and its
# evidence. The key is derived by RUNNING the shared library (rule 1a), never by
# composing a path here and never by a second derivation of its own (rule 1's
# "do not mint a second scheme").
#
# RETENTION. One file per run plus an appended history line, which is rule 2's
# third row: a same-day rerun must not erase the earlier verdict set, because the
# operator may have approved items from the earlier one. `latest` is a POINTER to
# the newest run id, not the artifact, so `read` with no `--run-id` still serves
# a real per-run file. A findings file is never overwritten: a colliding run id
# gets a `-2`, `-3`, ... suffix and the id actually written is reported back, the
# same non-overwrite naming `audit-instructions/scripts/emit-findings.sh` uses
# for its `--out`.
#
# RULE 3, NEVER SERVE WHAT YOU CANNOT ATTRIBUTE. `read` against a key with no
# artifact exits 4 saying so. It does not look in an unkeyed location, it does
# not adopt a legacy file, and it computes nothing from one.
#
# UNINSTALL FRAGILITY. This tree is the only durable copy of a run's verdicts.
# Uninstalling the plugin from its last scope deletes `${CLAUDE_PLUGIN_DATA}`
# unless `--keep-data` is passed, and that takes every project's findings with
# it. Say so to the operator before treating this as an archive.
#
# `--plugin-data` IS REQUIRED, AND THAT IS THE DESIGN. `${CLAUDE_PLUGIN_DATA}` is
# NOT in the Bash tool's environment: the placeholder substitutes in skill
# CONTENT, and it is exported to hook processes and MCP/LSP subprocesses, none of
# which the Bash tool is. Verified on this host: `printenv CLAUDE_PLUGIN_DATA`
# exits 1 with no output. So the skill passes the already-resolved path it can
# see, and an exported value is honored only where one genuinely exists. Absent
# both, every subcommand exits 2 naming the remedy rather than inventing a
# directory and writing a project's verdicts somewhere nobody will look.
#
# PORTABILITY. coreutils plus `jq` plus `git` and `sha256sum`/`shasum` through
# `lib/state-key.sh`. No GNU-only flags: no `readlink -f`, no in-place `sed`, no
# `date -d`, no `stat` format flags. `jq` is a hard requirement rather than a
# soft one, matching every other jq-using script in this plugin
# (`audit/scripts/*.sh`, `audit-permission-state/scripts/permission-state.sh`): a
# findings payload is a JSON document, and a half-checked document in an artifact
# `--implement` is the only reader of is worse than a refusal naming the tool.
#
# Usage:
#   findings-state.sh paths --plugin-data <dir> [--root <path>]
#   findings-state.sh write --plugin-data <dir> --findings <file|-> [--run-id <id>]
#                           [--root <path>]
#   findings-state.sh read  --plugin-data <dir> [--run-id <id>] [--root <path>]
#   findings-state.sh list  --plugin-data <dir> [--root <path>]
#
# Exit codes:
#   0  the operation succeeded
#   2  usage error, rejected argument, or a missing prerequisite (no
#      --plugin-data, no jq, no lib/state-key.sh)
#   3  `write` only: the findings payload is not well-formed JSON, or does not
#      carry the shape `--implement` reads back. Every problem is listed on
#      stderr and NOTHING is written.
#   4  `read` only: no findings are persisted at this project's derived key.
#      This is an answer, not a failure, and it is deliberately distinct from 2
#      so a caller can tell "nothing audited yet" from "you called me wrong".
set -uo pipefail

PROG="findings-state.sh"

# The component segment of rule 1's `<component>/<state-key>/<filename>`. It is
# the skill's own directory name, so a second component writing under the same
# plugin data root cannot collide with this one.
COMPONENT="audit-automation-gaps"

# Bumped when the on-disk envelope changes shape. `read` hands the whole envelope
# back with this field intact, so a later `--implement` can refuse an artifact it
# does not understand instead of misreading one.
SCHEMA_VERSION=1

# The vocabularies the payload is checked against. Categories are the skill's own
# `argument-hint` filter tokens; verdicts are its three Phase 2 outcomes.
CATEGORIES='["hooks","mcp","skills","subagents","scheduled"]'
VERDICTS='["PASS","CONDITIONAL","REJECT"]'

EXIT_PAYLOAD=3
EXIT_NO_ARTIFACT=4

# Staged files the cleanup trap removes. Globals rather than locals because the
# trap body runs after the function that created them has returned.
TMP_PAYLOAD=""
TMP_ENVELOPE=""

# Set by parse_common_args and the resolvers below.
ARG_PLUGIN_DATA=""
ARG_ROOT=""
ARG_RUN_ID=""
ARG_FINDINGS=""
# "Was the flag given?" is tracked separately from its value. `--run-id ""` must
# be a rejected argument, not a silently omitted one: treating it as omitted
# would quietly serve the newest run to a caller that asked for a specific id.
ARG_RUN_ID_GIVEN=0
ARG_FINDINGS_GIVEN=0
PLUGIN_DATA=""
STATE_KEY=""
BASE_DIR=""
HISTORY_FILE=""
LATEST_FILE=""

cleanup_tmp() {
  if [[ -n "$TMP_PAYLOAD" ]]; then
    rm -f "$TMP_PAYLOAD"
  fi
  if [[ -n "$TMP_ENVELOPE" ]]; then
    rm -f "$TMP_ENVELOPE"
  fi
  return 0
}
trap cleanup_tmp EXIT

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
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

Exit: 0 success; 2 usage or prerequisite; 3 rejected payload (write); 4 no
artifact at this project's key (read).
EOF
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_stamp() { date -u +%Y%m%dT%H%M%SZ; }

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required: the findings payload is a JSON document and this script will not half-check one"
  fi
}

# A run id becomes a FILENAME under the plugin's own tree. Accept only a plain
# segment: no separators, no `..`, no leading dot. `lib/state-key.sh` validates
# its half of the same door (a remote URL that would become traversing directory
# components); this is the other half.
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

# Sets PLUGIN_DATA. A GLOBAL RATHER THAN A PRINTED VALUE, deliberately: `die`
# must terminate the script, and a `$(...)` capture would confine that exit to a
# subshell while the caller carried on with an empty path. The same reasoning
# governs derive_state_key and resolve_locations below.
#
# An exported value is honored only where one genuinely exists (a hook context).
# The refusal names WHY the placeholder is unavailable, because "CLAUDE_PLUGIN_DATA
# is unset" sends a reader looking for an environment bug that is not there.
resolve_plugin_data() {
  local value="$1"
  if [[ -z "$value" ]]; then
    value="${CLAUDE_PLUGIN_DATA:-}"
  fi
  if [[ -z "$value" ]]; then
    die "--plugin-data is required: \${CLAUDE_PLUGIN_DATA} is not exported to the Bash tool, so pass the path substituted into the skill text"
  fi
  require_absolute_path "--plugin-data" "$value"
  case "$value" in
  *..*) die "--plugin-data must not contain '..': $value" ;;
  *) : ;;
  esac
  PLUGIN_DATA="$value"
}

# Sets STATE_KEY by RUNNING the shared library (rule 1a). Nothing here
# reimplements the scheme, and nothing composes a path from a placeholder.
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

# The physical repo root for the derived key, recorded in the envelope as an
# operator-facing breadcrumb. It is NOT the key, and nothing reads it back to
# decide attribution; the key does that.
derive_repo_root() {
  local here="${1:-}"
  if [[ -z "$here" ]]; then
    here="."
  fi
  (cd "$here" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null | tr -d '\r') || true
}

# Sets BASE_DIR, HISTORY_FILE, LATEST_FILE, STATE_KEY, PLUGIN_DATA.
resolve_locations() {
  resolve_plugin_data "$1"
  derive_state_key "$2"
  BASE_DIR="$PLUGIN_DATA/$COMPONENT/$STATE_KEY"
  HISTORY_FILE="$BASE_DIR/history.jsonl"
  LATEST_FILE="$BASE_DIR/latest"
}

# The jq program that judges a payload. It returns one line per problem and
# nothing at all for a conforming document, so the caller needs no exit-code
# contract from jq beyond "it parsed".
#
# WHAT IT REQUIRES, and why each field is here rather than left to the caller:
# `candidates` is the verdict table; `evidence` is what backed each verdict and
# is the half an operator cannot reconstruct from the table alone; `plan` is
# required on PASS and CONDITIONAL because that is precisely what `--implement`
# reads back. An empty `candidates` array is legal: the skill's own quality
# principles make a clean bill of health a valid outcome, and persisting that is
# a result, not an absence.
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
  local file="$1" problems
  if ! jq -e 'type' "$file" >/dev/null 2>&1; then
    printf '%s: the findings payload is not well-formed JSON\n' "$PROG" >&2
    jq . "$file" 2>&1 >/dev/null | head -5 >&2
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
  printf 'plugin_data=%s\n' "$PLUGIN_DATA"
  printf 'state_key=%s\n' "$STATE_KEY"
  printf 'dir=%s\n' "$BASE_DIR"
  printf 'history=%s\n' "$HISTORY_FILE"
  printf 'latest=%s\n' "$LATEST_FILE"
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

  # WRITE IS THE ONLY SUBCOMMAND THAT CREATES ANYTHING, so containment is
  # established here. Every path segment below the plugin data root is already
  # constrained: COMPONENT is a literal, the state key is validated by
  # lib/state-key.sh (which hashes any identity that is not a plain lowercase
  # segment path), and the run id is validated above. So the directory is
  # derived, never accepted from a caller, and there is no caller-supplied run
  # directory to contain.
  #
  # DISCLOSED RESIDUAL: a symlink planted INSIDE the plugin's own data directory
  # could still redirect the write, and this does not resolve physical paths to
  # catch that. An attacker with write access there can write the findings file
  # directly, so the guard would be moot; recorded rather than implied, because
  # an unstated limit reads as no limit.
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

  local run_id
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    run_id="$ARG_RUN_ID"
  else
    run_id=$(now_stamp)
  fi

  # NEVER OVERWRITE. Two runs in the same second, or a caller reusing an id, get
  # a suffix instead of silently replacing a verdict set the operator may have
  # already approved items from. The id actually written is reported back so the
  # caller records the one on disk rather than the one it asked for.
  local target="$BASE_DIR/findings-$run_id.json" suffix=2
  if [[ -e "$target" ]]; then
    while [[ -e "$BASE_DIR/findings-$run_id-$suffix.json" ]]; do
      suffix=$((suffix + 1))
      if [[ "$suffix" -gt 99 ]]; then
        die "more than 99 findings files already exist for run id: $run_id"
      fi
    done
    run_id="$run_id-$suffix"
    target="$BASE_DIR/findings-$run_id.json"
  fi

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

  # Atomic publish: a reader never observes a half-written findings file, and a
  # crash mid-write leaves nothing at the target rather than a truncated JSON
  # document `--implement` would fail to parse.
  mv -f "$TMP_ENVELOPE" "$target" || die "cannot publish the findings file: $target"
  TMP_ENVELOPE=""

  # The history line is derived FROM the published envelope, so the two can never
  # disagree about counts or timestamps.
  local line
  line=$(jq -c '{schema_version, run_id, written_at, state_key, file, counts}' "$target") ||
    die "cannot compose the history line for: $target"
  printf '%s\n' "$line" >>"$HISTORY_FILE" || die "cannot append to: $HISTORY_FILE"

  # `latest` is a pointer, not the artifact. Written after the findings file, so
  # a failure never leaves it naming a run that does not exist.
  printf '%s\n' "$run_id" >"$LATEST_FILE.$$" || die "cannot write the latest pointer"
  mv -f "$LATEST_FILE.$$" "$LATEST_FILE" || die "cannot replace the latest pointer"

  printf 'run_id=%s\n' "$run_id"
  printf 'state_key=%s\n' "$STATE_KEY"
  printf 'path=%s\n' "$target"
}

no_artifact() {
  printf '%s: no findings are persisted for this project (state key %s) under %s\n' \
    "$PROG" "$STATE_KEY" "$BASE_DIR" >&2
  printf '%s: run the audit first. Nothing outside this key is read: an artifact with no project segment cannot be attributed to this one.\n' \
    "$PROG" >&2
  exit "$EXIT_NO_ARTIFACT"
}

cmd_read() {
  parse_common_args "read" "$@"
  if [[ "$ARG_FINDINGS_GIVEN" -eq 1 ]]; then
    die "read does not take --findings"
  fi
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    validate_run_id "$ARG_RUN_ID"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"

  if [[ ! -d "$BASE_DIR" ]]; then
    no_artifact
  fi

  local run_id=""
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    run_id="$ARG_RUN_ID"
  fi
  if [[ -z "$run_id" ]]; then
    if [[ ! -f "$LATEST_FILE" ]]; then
      no_artifact
    fi
    run_id=$(tr -d '\r' <"$LATEST_FILE" | head -1)
    if [[ -z "$run_id" ]]; then
      no_artifact
    fi
    validate_run_id "$run_id"
  fi

  local target="$BASE_DIR/findings-$run_id.json"
  if [[ ! -f "$target" ]]; then
    printf '%s: no findings file for run id %s at: %s\n' "$PROG" "$run_id" "$target" >&2
    exit "$EXIT_NO_ARTIFACT"
  fi
  cat "$target"
}

cmd_list() {
  parse_common_args "list" "$@"
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]] || [[ "$ARG_FINDINGS_GIVEN" -eq 1 ]]; then
    die "list takes only --plugin-data and --root"
  fi
  resolve_locations "$ARG_PLUGIN_DATA" "$ARG_ROOT"

  # An empty listing is an ANSWER, not a failure: "this project has no persisted
  # runs" is exactly what a caller deciding whether to audit or to implement
  # needs, so stdout is empty and the exit code stays 0. Only `read`, which was
  # asked for a specific artifact, treats absence as exit 4.
  if [[ ! -f "$HISTORY_FILE" ]]; then
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
