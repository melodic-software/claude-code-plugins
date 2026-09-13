#!/usr/bin/env bash
# findings-state.sh: persistence for audit-automation-gaps verdicts, so
# `--implement` in a LATER session can read back what a run decided.
#
# WHY THIS EXISTS. The skill takes an `--implement` flag and its Phase 4 acts on
# "user-selected items", but nothing persisted the verdict table, the evidence
# behind each verdict, or the implementation plans a PASS carries. An audit run
# and the implement run that acts on it are two sessions, so without a durable
# artifact `--implement` has nothing to read and the operator re-runs the whole
# audit to recover what was already decided.
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
# HOW THAT PROMISE IS KEPT UNDER CONCURRENCY, which a check-then-write cannot.
# Testing `[[ -e "$target" ]]` and publishing afterwards leaves a window in which
# two writers pick the same name and the second `mv` destroys the first verdict
# set while both report success. So the suffix search IS the publish reservation:
# each candidate name is claimed with `set -C` (noclobber) plus a `>` redirect,
# which opens with O_EXCL, so exactly one writer can win a given name and the
# loser moves to the next suffix. The envelope is composed only after a name is
# won and lands on the reserved inode with `mv -f`. No lock file is taken: a
# stale lock would wedge every later run, whereas the history append is one short
# line through `>>` (a single atomic write below PIPE_BUF) and `latest` is
# last-writer-wins by definition. RESIDUAL: O_EXCL is atomic on local POSIX
# filesystems and on NFSv3+, not on NFSv2; a plugin data root on NFSv2 is outside
# what this guards, and is recorded rather than implied.
#
# A PUBLISH IS ALL OR NOTHING. The pointers a publish also owns (the history line
# and `latest`) are pre-flighted before anything is published, so the common
# damaged state refuses up front instead of half-landing. If the history append
# still fails, the findings file is rolled back rather than left as an orphan
# nothing points at. The one residue that cannot be rolled back, a `latest` that
# will not replace after the history line is committed, is REPORTED as an
# incomplete publish naming the run id, and `read`/`list` report orphan findings
# files as an incomplete publish rather than as an absence.
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
# The requirement is checked by the two subcommands that touch a payload, `write`
# and `read`, and by neither `paths` nor `list`, which compute a path and serve
# the history file with `cat`. Checking it is not optional in `read`: it parses
# the stored envelope before serving it, so an absent `jq` is a failed command
# that a caller cannot tell from a document that did not parse, and reporting
# that as exit 5 tells an operator their verdicts were corrupted when the
# artifact is intact and the machine is short a tool.
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
EXIT_STATE=5

# Staged files the cleanup trap removes. Globals rather than locals because the
# trap body runs after the function that created them has returned.
TMP_PAYLOAD=""
TMP_ENVELOPE=""
TMP_LATEST=""
# The findings name this run claimed with O_EXCL. Held for the same reason: the
# trap has to be able to release a name whose envelope never landed, or a failed
# run would burn a suffix and leave a zero-byte file behind.
RESERVED_TARGET=""

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
  if [[ -n "$TMP_LATEST" ]]; then
    rm -f "$TMP_LATEST"
  fi
  # Only ever an EMPTY reservation: once the envelope has landed on it the name
  # is cleared, so a published findings file is never removed from here.
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

# Exit 5: the persisted state is not usable. Separate from `die` because the
# caller did nothing wrong and, for `read` and `list`, separate from exit 4
# because state this script cannot read is not state that is not there.
die_state() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "$EXIT_STATE"
}

# Refuse a damaged pointer BEFORE anything is published. `write` owns three
# artifacts (the findings file, the history line, the pointer) and a failure
# discovered after the first one has landed is the orphan this checks away: a
# findings file on disk that `read` and `list` then report as absent.
preflight_state_file() {
  local path="$1" label="$2"
  if [[ -e "$path" ]] && [[ ! -f "$path" ]]; then
    die_state "$label exists but is not a regular file, so this run cannot be recorded and nothing was written: $path"
  fi
  if [[ -f "$path" ]] && [[ ! -w "$path" ]]; then
    die_state "$label exists but is not writable, so this run cannot be recorded and nothing was written: $path"
  fi
}

# A publish that cannot be completed releases its reserved name rather than
# leaving a findings file nothing points at.
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

# A run id becomes a FILENAME under the plugin's own tree. Accept only a plain
# segment: no separators, no leading dot. `lib/state-key.sh` validates its half
# of the same door (a remote URL that would become traversing directory
# components); the regex below is the other half, and it is the regex, not the
# `..` arm after it, that stops traversal: a segment with no `/` cannot climb.
#
# WHAT THE `..` ARM ACTUALLY GUARDS, since it is not traversal. A dot run is
# refused so the id stays a plain readable segment on disk and in the envelope,
# and so the check survives as the second half of the door if the regex is ever
# loosened to admit a separator. It is deliberately stricter than the
# `--plugin-data` rule below, which refuses only a real `..` PATH COMPONENT: a
# directory may legitimately be named `a..b`, a run id may not.
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
  # A `..` PATH COMPONENT is the traversal, and it is the only thing refused
  # here. A directory named `a..b` is a legal name and is accepted; the older
  # substring test refused one, and the message it printed claimed a traversal
  # the path did not contain.
  case "$value" in
  .. | ../* | ..[\\]* | *[/\\].. | *[/\\]..[/\\]*)
    die "--plugin-data must not contain a '..' path component: $value"
    ;;
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
  local file="$1" problems documents
  if ! jq -e 'type' "$file" >/dev/null 2>&1; then
    printf '%s: the findings payload is not well-formed JSON\n' "$PROG" >&2
    jq . "$file" 2>&1 >/dev/null | head -5 >&2
    exit "$EXIT_PAYLOAD"
  fi
  # EXACTLY ONE DOCUMENT, because publication can only carry one. `jq` accepts a
  # stream of concatenated documents and the check below would walk all of them,
  # but the envelope is composed from the FIRST. A two-document stream whose
  # second half holds the real verdicts would otherwise validate in full, report
  # success, and persist only the empty first half: a confident success that
  # stored none of the verdicts. Refusing is the honest half of the choice
  # because merging would have to invent a rule for conflicting keys.
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

  preflight_state_file "$HISTORY_FILE" "the history file"
  preflight_state_file "$LATEST_FILE" "the latest pointer"

  # NEVER OVERWRITE, WHICH MEANS NEVER RACE. Two runs in the same second, or a
  # caller reusing an id, get a suffix instead of silently replacing a verdict
  # set the operator may have already approved items from. The id actually
  # written is reported back so the caller records the one on disk rather than
  # the one it asked for.
  #
  # The search and the publish are ONE atomic reservation per run: each candidate
  # name is claimed by creating it under `set -C`, which is an O_EXCL open, so
  # two concurrent writers cannot both believe they won the same name. A
  # check-then-`mv` would leave a window between them in which the second writer
  # destroys the first verdict set and both report success.
  local target="" candidate="" suffix=1
  while :; do
    if [[ "$suffix" -eq 1 ]]; then
      candidate="$run_id"
    else
      candidate="$run_id-$suffix"
    fi
    target="$BASE_DIR/findings-$candidate.json"
    if (set -C && : >"$target") 2>/dev/null; then
      break
    fi
    # The claim can fail for a reason that is not "somebody holds this name", and
    # walking 99 suffixes to report a cap that is not the problem would bury it.
    if [[ ! -e "$target" ]]; then
      die "cannot reserve the findings file: $target"
    fi
    suffix=$((suffix + 1))
    if [[ "$suffix" -gt 99 ]]; then
      die_state "all 99 suffixed findings names are taken for run id: $run_id"
    fi
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

  # Atomic publish onto the name this run reserved: a reader never observes a
  # half-written findings file, and a crash mid-write leaves the reservation
  # rather than a truncated JSON document `--implement` would fail to parse.
  mv -f "$TMP_ENVELOPE" "$target" || rollback_publish "cannot publish the findings file: $target"
  TMP_ENVELOPE=""

  # The history line is derived FROM the published envelope, so the two can never
  # disagree about counts or timestamps. A failure here rolls the findings file
  # back out rather than leaving one the history does not mention.
  local line
  line=$(jq -c '{schema_version, run_id, written_at, state_key, file, counts}' "$target") ||
    rollback_publish "cannot compose the history line, so the findings file was rolled back: $target"
  printf '%s\n' "$line" >>"$HISTORY_FILE" ||
    rollback_publish "cannot append to the history file, so the findings file was rolled back: $HISTORY_FILE"
  # Committed from here: the run is on disk and in the history, so a later
  # failure is REPORTED rather than rolled back over a record that now exists.
  RESERVED_TARGET=""

  # `latest` is a pointer, not the artifact. Written after the findings file, so
  # a failure never leaves it naming a run that does not exist, and REPLACED
  # rather than copied into: `mv` swaps the name atomically, where `cp` would
  # write through whatever the name already is and let a reader see a half
  # pointer.
  TMP_LATEST="$LATEST_FILE.$$"
  printf '%s\n' "$run_id" >"$TMP_LATEST" ||
    die_state "run $run_id is published and recorded, but the latest pointer could not be staged. Read it with --run-id $run_id: $LATEST_FILE"
  mv -f "$TMP_LATEST" "$LATEST_FILE" ||
    die_state "run $run_id is published and recorded, but the latest pointer could not be replaced. Read it with --run-id $run_id: $LATEST_FILE"
  TMP_LATEST=""

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

# Findings files with no pointer at them are an INCOMPLETE PUBLISH, and saying
# "nothing is persisted" over the top of them is the same lie in a different
# costume: the verdicts are right there on disk. Called only on the paths that
# were about to report absence, so a healthy tree never pays for it.
refuse_orphans() {
  local missing="$1" file count=0
  for file in "$BASE_DIR"/findings-*.json; do
    if [[ -e "$file" ]]; then
      count=$((count + 1))
    fi
  done
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi
  printf '%s: %s is missing, but %d findings file(s) exist under %s. This is an INCOMPLETE PUBLISH, not an absence:\n' \
    "$PROG" "$missing" "$count" "$BASE_DIR" >&2
  for file in "$BASE_DIR"/findings-*.json; do
    if [[ -e "$file" ]]; then
      printf '%s:   %s\n' "$PROG" "${file##*/}" >&2
    fi
  done
  printf '%s: read one directly with --run-id <id>, taking the id from the file name.\n' "$PROG" >&2
  exit "$EXIT_STATE"
}

# `-f` alone answers "can this be served?" with a yes for a readable regular
# file and a no for everything else, and the two nos are not the same answer.
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
  # THE SAME PREREQUISITE CHECK `write` USES, and for a sharper reason here.
  # `read` parses the stored envelope with `jq` before serving it, and a machine
  # without `jq` fails that command with exit 127. Without this gate the failure
  # is indistinguishable from a document that did not parse, so a perfectly
  # valid persisted run is reported as damaged state under exit 5 and the
  # operator is told an external writer corrupted their verdicts. A missing tool
  # is a missing prerequisite: it exits 2 and names `jq`.
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

  local run_id=""
  if [[ "$ARG_RUN_ID_GIVEN" -eq 1 ]]; then
    run_id="$ARG_RUN_ID"
  fi
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
    # VALIDATED EVEN THOUGH THIS SCRIPT WROTE IT. The pointer is a file on disk
    # under a directory anything with write access can reach, so a poisoned
    # `latest` is a caller-supplied run id by another route, and the name below
    # is built from it.
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
  # PARSED BEFORE IT IS SERVED, even though this script wrote it. Publication is
  # staged and renamed, so this script cannot leave a corrupt file behind, but
  # the tree is an ordinary directory that a foreign writer or a stray editor
  # can reach. Serving bytes that do not parse would hand the caller something
  # unusable under exit 0, which is the opposite of the promise exit 5 makes:
  # state that exists but cannot be trusted is reported, never returned.
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
  # A history file that exists but cannot be read is reported as itself, not as
  # an empty listing: "no persisted runs" would send a caller off to re-run the
  # whole audit over a verdict set that is sitting right there.
  require_readable_file "$HISTORY_FILE" "the history file"

  # An empty listing is an ANSWER, not a failure: "this project has no persisted
  # runs" is exactly what a caller deciding whether to audit or to implement
  # needs, so stdout is empty and the exit code stays 0. Only `read`, which was
  # asked for a specific artifact, treats absence as exit 4.
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
