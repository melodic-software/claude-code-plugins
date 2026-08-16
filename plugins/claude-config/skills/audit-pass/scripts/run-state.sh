#!/usr/bin/env bash
# run-state.sh — the executable half of `audit-pass`'s run-state contract:
# where a run's state lives, the lease that tells a live run from an abandoned
# one, and the append-only partial `--resume` reads.
#
# WHY THIS EXISTS. `reference/run-state-and-resumability.md` specifies a lease
# (path, contents, refresh discipline, a two-sided liveness window, a `released`
# tombstone) and an epoch-scoped append-only partial, and
# `reference/report-location-and-schema.md` §7 makes `--resume` read that partial
# rather than the report. Until this script, all of it was prose: the skill
# shipped no `scripts/` directory at all, while its four sibling audit skills in
# this plugin each ship one with tests, and `lib/state-key.sh` — whose own header
# says the scheme is "`audit-pass`'s, reused rather than reinvented" — was called
# by three OTHER skills and never by the one that specified it. A contract that
# reads as enforced while nothing enforces it is the defect; this closes the half
# a script can close, and the skill's own §3 now states plainly which clauses
# remain model discipline rather than mechanism.
#
# WHAT IT DOES NOT DO, deliberately. Stale-lease adoption (`owner_epoch`
# compare-and-set) and report assembly (highest-epoch, highest-terminated-attempt
# selection) are NOT implemented here. They are specified in §3 and §7 and are
# carried out by the run itself. This script writes `owner_epoch` into the lease
# and names the partial after it, so the epoch is a real value on disk rather
# than a notion — but nothing here increments it or fences a previous holder.
# Claiming otherwise would put the same "reads as enforced" defect back one layer
# down.
#
# `--epoch <n>` is the seam that boundary leaves behind, and it is named here so
# it does not read as a feature. On `lease acquire`, an ADOPTING run records the
# epoch it won; a fresh run omits it and gets 1. On `partial append`, a writer
# passes the epoch IT HOLDS, and the record lands in that epoch's file no matter
# what the lease now says — which is what gives a fenced writer its own
# superseded file instead of letting it interleave into the adopter's. Omitting
# it there falls back to the lease's current epoch, correct only for a run whose
# epoch nothing has moved. The compare-and-set that decides who won is §3's,
# performed by the run, not by this script.
#
# `lease acquire` also requires `--plugin-data`: it is the only command that
# CREATES a directory, so it is where the write tree is pinned. A run dir outside
# `<plugin-data>/runs/` is refused rather than created.
#
# SCOPE OF WRITES. Everything this script writes goes under the run directory it
# derives, which is `<plugin-data>/runs/<state-key>/<run-id>/`. It never writes
# into a target repository, so it does not widen the skill's report-only contract
# (`disallowed-tools: Edit, NotebookEdit`; `Write` and Bash kept for exactly this
# state). Both path segments it contributes are validated before use:
# `lib/state-key.sh` already refuses a remote URL that would become traversing
# directory components, and `--run-id` here is accepted only as a plain segment.
# An unvalidated id would walk the run directory out of the plugin's namespace
# through the same door that library documents defending.
#
# PORTABILITY. No jq, no GNU-only flags: coreutils plus `git` (only through
# `lib/state-key.sh`) plus one of `sha256sum` / `shasum` (again, only through
# that library). Timestamps use `date -u +%s` and `date -u +%Y-%m-%dT%H:%M:%SZ`.
#
# Usage:
#   run-state.sh paths          --plugin-data <dir> --run-id <id> [--root <path>]
#   run-state.sh lease acquire  --run-dir <dir> --run-id <id> [--stale-after <s>]
#                               [--skew-grace <s>] [--epoch <n>]
#   run-state.sh lease heartbeat --run-dir <dir>
#   run-state.sh lease release   --run-dir <dir>
#   run-state.sh lease classify  --run-dir <dir>
#   run-state.sh partial append  --run-dir <dir> --record <json-line>
#
# `--plugin-data` is required because `${CLAUDE_PLUGIN_DATA}` is NOT in the Bash
# tool's environment (plugins reference: the three placeholders are exported to
# hook processes and to MCP/LSP subprocesses, and the Bash tool is none of
# those). It DOES substitute in skill content, so the skill passes the already-
# resolved path it can see. `$CLAUDE_PLUGIN_DATA` from the environment is honored
# where one genuinely exists (a hook context); absent both, this exits 2 naming
# the remedy rather than guessing a directory.
#
# Exit codes:
#   0  the operation succeeded (for `classify`, the verdict is on stdout)
#   2  usage error, rejected argument, or a missing environment prerequisite
#   3  `partial append` only — FENCED. The record WAS written, to the writer's own
#      epoch file so nothing interleaves, but the lease has moved on: this run has
#      been superseded and must stop dispatching. Carried in the exit code rather
#      than only in a stderr string, because a control that announces an abort
#      nobody enforces is the defect this file exists to remove.
#
# `classify` prints one of `live`, `stale`, `released`, `missing` and exits 0 —
# a classification is an answer, not a failure. Acting on it (refusing `--resume`
# against a `live` lease) belongs to the caller, which is the skill.

set -uo pipefail

PROG="run-state.sh"

# A fenced append is neither success nor a usage error, so it gets its own code:
# the record was written (to the writer's own epoch file), and the run that wrote
# it has been superseded and must stop.
EXIT_FENCED=3

# Defaults for the liveness window. Stated here rather than left to the caller
# because "live or abandoned" is a classification two implementations must reach
# identically or `--resume` is nondeterministic — and every lease records the
# values its writer committed to, so `classify` reads them from the artifact
# instead of assuming its own.
#
# 1800s, not the 300s the prose carried before this script existed. That number
# was derived from a 60-second wall-clock heartbeat, and a skill-driven run has
# no timer: it acts between tool calls, so it can only refresh at boundaries it
# actually reaches — acquire, each lane's persistence point, release. A single
# delegated lane can outlast five minutes, and a threshold shorter than a lane
# makes a *running* pass classify as abandoned, which is the one direction that
# is unsafe. Longer only ever costs an operator a wait, and the `released`
# tombstone removes that cost from every clean exit.
DEFAULT_STALE_AFTER_S=1800
# One refresh boundary of tolerance for a clock that jumped forward and was
# corrected. A heartbeat further ahead than this is a clock artifact, not
# evidence of life.
DEFAULT_SKEW_GRACE_S=60

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
run-state.sh — run directory, lease, and append-only partial for audit-pass.

  run-state.sh paths           --plugin-data <dir> --run-id <id> [--root <path>]
  run-state.sh lease acquire   --run-dir <dir> --run-id <id> --plugin-data <dir>
                               [--stale-after <s>] [--skew-grace <s>] [--epoch <n>]
  run-state.sh lease heartbeat --run-dir <dir>
  run-state.sh lease release   --run-dir <dir>
  run-state.sh lease classify  --run-dir <dir>
  run-state.sh partial append  --run-dir <dir> --record <json-line> [--epoch <n>]

`classify` prints live | stale | released | missing on stdout and exits 0.
Exit 2 is a usage error, a rejected argument, or a missing prerequisite.

`--stale-after` and `--epoch` must be >= 1; `--skew-grace` may be 0. A
stale_after_s of 0 would make the lease classify stale the moment it is written.
`--epoch` is for an ADOPTING run to record the epoch it won — the compare-and-set
that decides who won is the run's, not this script's (see §3).
EOF
}

now_epoch() { date -u +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# A run id becomes a directory component. Accept only a plain segment: no
# separators, no `..`, no leading dot, no absolute path. Rejecting here is what
# keeps a caller-supplied id from walking the run directory out of the plugin's
# own namespace — the same class of defect lib/state-key.sh validates a remote
# URL against.
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

# Physical (symlink-resolved) form of a directory that exists. `pwd -P` is the
# portable resolver; `readlink -f` is GNU-only and this must run on BSD userland.
physical_path() {
  (cd "$1" 2>/dev/null && pwd -P) || return 1
}

# Physical form of the deepest existing ancestor of a path, which is the only
# part of it a symlink can be in before the path is created.
physical_existing_prefix() {
  local p="$1" guard=0
  while [[ ! -d "$p" ]]; do
    p="${p%/*}"
    if [[ -z "$p" ]]; then
      p="/"
    fi
    guard=$((guard + 1))
    if [[ "$guard" -gt 64 ]]; then
      return 1
    fi
  done
  physical_path "$p"
}

require_absolute_path() {
  local name="$1" value="$2"
  case "$value" in
  /* | ?:[\\/]*) : ;;
  *) die "$name must be an absolute path: $value" ;;
  esac
}

require_non_negative_int() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer: $value"
  fi
}

# `--stale-after 0` and `--epoch 0` are not merely odd values, they invert the
# mechanism. A lease carrying stale_after_s=0 satisfies `delta >= stale_after`
# on the very first classify, so it is born abandoned: acquire it and `--resume`
# will adopt it out from under the live run that just wrote it. Zero has to be
# refused rather than clamped, because a clamp would silently give the caller a
# threshold it did not ask for and `classify` would then report a window nobody
# chose — the shape of defect this script exists to remove. `--skew-grace 0` is
# left legal: it means "tolerate no forward clock jump", which is a coherent
# choice and inverts nothing.
# `--epoch 0` is refused for a different reason — epochs start at 1, so 0 names no
# writer's file — which is why the reason travels as an argument rather than being
# hardcoded to the staleness case.
require_int_at_least_one() {
  local name="$1" value="$2" why="${3:-}"
  require_non_negative_int "$name" "$value"
  if [[ "$value" -lt 1 ]]; then
    if [[ -n "$why" ]]; then
      die "$name must be at least 1: $value ($why)"
    fi
    die "$name must be at least 1: $value"
  fi
}

# Is this string one well-formed single-line JSON object?
#
# `case "$record" in '{'*)` was not enough: it accepts `{bad json}`, and a
# malformed row in an append-only artifact is permanent — resume and assembly
# then cannot parse the record stream they are the only readers of, so a
# serialization slip in the caller costs the run's persisted state rather than
# one record. The check has to fire on construction errors, not just on obviously
# non-JSON input.
#
# THREE RUNGS, AND THE WEAKEST ONE SAYS SO. `jq` answers definitively where it is
# installed; `python3` answers definitively where it is not (and this plugin
# already depends on it elsewhere), so the structural rung is reached only on a
# host with neither. That rung tracks string context and escapes to verify
# brace/bracket balance, string termination, and that the object opens with a
# quoted key or closes empty — which rejects `{bad json}`, truncated rows and
# unbalanced ones, but NOT every malformed object: `{"a" garbage}` balances and
# opens with a quoted key, and no non-parser catches it. So the structural rung
# ANNOUNCES itself on stderr rather than passing for the real thing. A check that
# claims more than it verifies is the defect this whole file exists to remove.
#
# Neither parser is made a hard requirement: this is the run's state-persistence
# path, and failing it closed on a missing optional tool would cost the artifact
# the check exists to protect. The residual is disclosed instead of hidden.
record_is_json_object() {
  local s="$1"
  case "$s" in
  '{'*) : ;;
  *) return 1 ;;
  esac
  case "$s" in
  *'}') : ;;
  *) return 1 ;;
  esac

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$s" | jq -e 'type == "object"' >/dev/null 2>&1
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$s" |
      python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,dict) else 1)' \
        >/dev/null 2>&1
    return
  fi
  printf '%s: no jq or python3 on PATH — the record was checked structurally only; a string that balances but is not JSON (%s) can pass\n' \
    "$PROG" '{"a" garbage}' >&2

  local i ch in_str=0 esc=0 depth=0 len=${#s}
  for ((i = 0; i < len; i++)); do
    ch="${s:i:1}"
    if [[ "$in_str" -eq 1 ]]; then
      if [[ "$esc" -eq 1 ]]; then
        esc=0
      elif [[ "$ch" == "\\" ]]; then
        esc=1
      elif [[ "$ch" == '"' ]]; then
        in_str=0
      fi
      continue
    fi
    case "$ch" in
    '"') in_str=1 ;;
    '{' | '[') depth=$((depth + 1)) ;;
    '}' | ']')
      depth=$((depth - 1))
      if [[ "$depth" -lt 0 ]]; then
        return 1
      fi
      ;;
    *) : ;;
    esac
  done
  if [[ "$in_str" -eq 1 ]] || [[ "$depth" -ne 0 ]]; then
    return 1
  fi

  # After the opening brace, the first non-space character must open a quoted key
  # or close an empty object. `{bad json}` fails here even though it balances.
  local rest="${s:1}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$rest" in
  '"'*) return 0 ;;
  '}') return 0 ;;
  *) return 1 ;;
  esac
}

# Read one key=value field out of a lease file. Prints the value, or nothing.
lease_field() {
  local file="$1" key="$2" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
    "$key="*) printf '%s\n' "${line#"$key="}" ;;
    *) : ;;
    esac
  done <"$file"
}

# Replace the lease atomically: a reader never observes a half-written lease,
# and a crash mid-write leaves the previous lease intact rather than a truncated
# one that would classify as unreadable.
write_lease_atomic() {
  local dir="$1" body="$2" tmp
  tmp="$dir/.lease.$$"
  printf '%s' "$body" >"$tmp" || die "cannot write lease under: $dir"
  mv -f "$tmp" "$dir/lease" || die "cannot replace lease under: $dir"
}

# parse_run_dir_arg <context> [args…] — the argument loop shared by the three
# lease commands that take nothing but `--run-dir`. Sets RUN_DIR; <context> is
# the subcommand name that appears in an unknown-argument refusal. It sets a
# global rather than printing because `die` must exit the script, and a command
# substitution would confine that exit to a subshell.
#
# Post-parse validation stays with each command: heartbeat and release require
# an existing run dir, while classify must answer `missing` for one that is not
# there rather than refusing.
parse_run_dir_arg() {
  local context="$1"
  shift
  RUN_DIR=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      RUN_DIR="$2"
      shift 2
      ;;
    *) die "unknown argument to $context: $1" ;;
    esac
  done
}

require_run_dir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    die "--run-dir is required"
  fi
  if [[ ! -d "$dir" ]]; then
    die "--run-dir is not a directory: $dir"
  fi
}

cmd_paths() {
  local plugin_data="" run_id="" root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --plugin-data)
      [[ $# -ge 2 ]] || die "--plugin-data needs a path"
      plugin_data="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id needs a value"
      run_id="$2"
      shift 2
      ;;
    --root)
      [[ $# -ge 2 ]] || die "--root needs a path"
      root="$2"
      shift 2
      ;;
    *) die "unknown argument to paths: $1" ;;
    esac
  done

  if [[ -z "$plugin_data" ]]; then
    plugin_data="${CLAUDE_PLUGIN_DATA:-}"
  fi
  if [[ -z "$plugin_data" ]]; then
    die "--plugin-data is required: \${CLAUDE_PLUGIN_DATA} is not exported to the Bash tool, so pass the path substituted into the skill text"
  fi
  require_absolute_path "--plugin-data" "$plugin_data"

  validate_run_id "$run_id"

  local plugin_root state_key_lib state_key
  plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "${BASH_SOURCE[0]%/*}/../../.." && pwd)}"
  state_key_lib="$plugin_root/lib/state-key.sh"
  if [[ ! -f "$state_key_lib" ]]; then
    die "cannot find lib/state-key.sh at: $state_key_lib"
  fi

  if [[ -n "$root" ]]; then
    state_key=$(bash "$state_key_lib" --root "$root")
  else
    state_key=$(bash "$state_key_lib")
  fi
  if [[ -z "$state_key" ]]; then
    die "lib/state-key.sh produced no state key"
  fi

  printf 'plugin_data=%s\n' "$plugin_data"
  printf 'state_key=%s\n' "$state_key"
  printf 'run_dir=%s\n' "$plugin_data/runs/$state_key/$run_id"
}

cmd_lease_acquire() {
  local run_dir="" run_id="" stale_after="$DEFAULT_STALE_AFTER_S"
  local skew_grace="$DEFAULT_SKEW_GRACE_S" epoch=1 plugin_data=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    --plugin-data)
      [[ $# -ge 2 ]] || die "--plugin-data needs a path"
      plugin_data="$2"
      shift 2
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id needs a value"
      run_id="$2"
      shift 2
      ;;
    --stale-after)
      [[ $# -ge 2 ]] || die "--stale-after needs seconds"
      stale_after="$2"
      shift 2
      ;;
    --skew-grace)
      [[ $# -ge 2 ]] || die "--skew-grace needs seconds"
      skew_grace="$2"
      shift 2
      ;;
    --epoch)
      [[ $# -ge 2 ]] || die "--epoch needs an integer"
      epoch="$2"
      shift 2
      ;;
    *) die "unknown argument to lease acquire: $1" ;;
    esac
  done

  validate_run_id "$run_id"
  require_int_at_least_one "--stale-after" "$stale_after" \
    "0 would make the lease classify stale the moment it is written"
  require_non_negative_int "--skew-grace" "$skew_grace"
  require_int_at_least_one "--epoch" "$epoch" "epochs start at 1"
  if [[ -z "$run_dir" ]]; then
    die "--run-dir is required"
  fi

  # ACQUIRE IS THE ONLY COMMAND THAT CREATES A DIRECTORY, so it is where
  # containment is established — every later command operates on a run dir this
  # one already validated. Without the check, a caller that hands over a wrong or
  # invented `--run-dir` gets that directory created and a `lease` written into
  # it, and the skill keeps Bash specifically for state writes while promising a
  # bare audit writes nothing into the target: passing the target root here would
  # have broken that promise silently. So the run directory must lie under
  # `<plugin-data>/runs/`, which is the only tree this script may write.
  if [[ -z "$plugin_data" ]]; then
    plugin_data="${CLAUDE_PLUGIN_DATA:-}"
  fi
  if [[ -z "$plugin_data" ]]; then
    die "--plugin-data is required so --run-dir can be checked for containment; pass the same value given to 'paths'"
  fi
  require_absolute_path "--plugin-data" "$plugin_data"
  require_absolute_path "--run-dir" "$run_dir"
  case "$run_dir" in
  *..*) die "--run-dir must not contain '..': $run_dir" ;;
  *) : ;;
  esac
  case "$run_dir" in
  "$plugin_data"/runs/*) : ;;
  *) die "--run-dir is not under \$plugin-data/runs/ — refusing to write outside the plugin's own tree: $run_dir" ;;
  esac

  # A LEXICAL PREFIX CHECK IS NOT CONTAINMENT WHILE SYMLINKS EXIST. With
  # `runs/link -> /tmp/outside`, the path `<plugin-data>/runs/link/run` passes the
  # comparison above and then `mkdir` and the lease write follow the link straight
  # out of the plugin tree — the guarantee would hold on the string and fail on
  # the filesystem. So both sides are canonicalized physically before they are
  # compared: `pwd -P` resolves every symlink in a path that exists, and
  # `readlink -f` is not used because it is GNU-only.
  #
  # `--run-dir` usually does not exist yet, which is the point of `mkdir` below,
  # so its deepest EXISTING ancestor is what gets resolved — the only part a
  # symlink can be in.
  #
  # DISCLOSED RESIDUAL: this is check-then-act, so a symlink planted between the
  # resolution and the `mkdir` is not covered. Closing that needs an atomic
  # create-and-verify no portable shell offers, and the attacker would already
  # need write access inside the plugin's own data directory — at which point they
  # can write the lease themselves and the guard is moot. Recorded rather than
  # implied, because a guard whose limits are unstated reads as one without any.
  # THE PLUGIN DATA ROOT IS CREATED FIRST, because on a plugin's very first run it
  # does not exist yet and `pwd -P` cannot resolve a directory that is not there —
  # resolving before creating would have made `acquire` fail for exactly the run
  # that has never succeeded before, which no test with a pre-made fixture would
  # ever catch. Creating the plugin's OWN data root is inside this script's
  # mandate and is not a target write; it is the tree everything below is then
  # confined to.
  mkdir -p "$plugin_data" || die "cannot create the plugin data directory: $plugin_data"

  local real_plugin_data real_prefix
  real_plugin_data=$(physical_path "$plugin_data") ||
    die "--plugin-data cannot be resolved: $plugin_data"
  real_prefix=$(physical_existing_prefix "$run_dir") ||
    die "--run-dir cannot be resolved: $run_dir"
  case "$real_prefix" in
  "$real_plugin_data" | "$real_plugin_data"/*) : ;;
  *) die "--run-dir resolves outside the plugin's own tree (symlinked component): $run_dir -> $real_prefix" ;;
  esac

  mkdir -p "$run_dir" || die "cannot create run directory: $run_dir"

  local now iso
  now=$(now_epoch)
  iso=$(now_iso)
  write_lease_atomic "$run_dir" "run_id=$run_id
pid=$$
state=active
owner_epoch=$epoch
started_at=$iso
heartbeat_at=$now
heartbeat_at_iso=$iso
stale_after_s=$stale_after
skew_grace_s=$skew_grace
"
  printf '%s\n' "$run_dir/lease"
}

cmd_lease_heartbeat() {
  parse_run_dir_arg "lease heartbeat" "$@"
  local run_dir="$RUN_DIR"
  require_run_dir "$run_dir"
  if [[ ! -f "$run_dir/lease" ]]; then
    die "no lease to refresh at: $run_dir/lease"
  fi

  local run_id epoch started stale_after skew_grace previous now next
  run_id=$(lease_field "$run_dir/lease" run_id)
  epoch=$(lease_field "$run_dir/lease" owner_epoch)
  started=$(lease_field "$run_dir/lease" started_at)
  stale_after=$(lease_field "$run_dir/lease" stale_after_s)
  skew_grace=$(lease_field "$run_dir/lease" skew_grace_s)
  previous=$(lease_field "$run_dir/lease" heartbeat_at)
  now=$(now_epoch)

  # max(now, previous): a clock adjustment that rewinds must not make a live run
  # read stale. The runaway-forward case this admits is caught on the read side
  # by the lower bound in classify, not by refusing to write here.
  next="$now"
  if [[ "$previous" =~ ^[0-9]+$ ]] && [[ "$previous" -gt "$now" ]]; then
    next="$previous"
  fi

  local next_iso
  next_iso=$(now_iso)
  write_lease_atomic "$run_dir" "run_id=$run_id
pid=$$
state=active
owner_epoch=$epoch
started_at=$started
heartbeat_at=$next
heartbeat_at_iso=$next_iso
stale_after_s=$stale_after
skew_grace_s=$skew_grace
"
  printf '%s\n' "$next"
}

cmd_lease_release() {
  parse_run_dir_arg "lease release" "$@"
  local run_dir="$RUN_DIR"
  require_run_dir "$run_dir"
  if [[ ! -f "$run_dir/lease" ]]; then
    die "no lease to release at: $run_dir/lease"
  fi

  local run_id epoch started stale_after skew_grace iso
  run_id=$(lease_field "$run_dir/lease" run_id)
  epoch=$(lease_field "$run_dir/lease" owner_epoch)
  started=$(lease_field "$run_dir/lease" started_at)
  stale_after=$(lease_field "$run_dir/lease" stale_after_s)
  skew_grace=$(lease_field "$run_dir/lease" skew_grace_s)
  iso=$(now_iso)

  # The tombstone, not a deletion. A run that finished normally while
  # deliberately leaving a lane incomplete — the /doctor handoff is exactly this
  # — would otherwise look live for the whole staleness window, and the operator
  # who does the fastest correct thing is the one refused.
  write_lease_atomic "$run_dir" "run_id=$run_id
pid=$$
state=released
owner_epoch=$epoch
started_at=$started
released_at=$iso
heartbeat_at=$(lease_field "$run_dir/lease" heartbeat_at)
heartbeat_at_iso=$(lease_field "$run_dir/lease" heartbeat_at_iso)
stale_after_s=$stale_after
skew_grace_s=$skew_grace
"
  printf '%s\n' "released"
}

cmd_lease_classify() {
  parse_run_dir_arg "lease classify" "$@"
  local run_dir="$RUN_DIR"
  if [[ -z "$run_dir" ]]; then
    die "--run-dir is required"
  fi

  # A lease that is missing or unreadable is not evidence of life. Say `missing`
  # rather than erroring: the absence of a heartbeat is itself the answer resume
  # needs, and treating it as a failure would make an interrupted run
  # unresumable.
  if [[ ! -f "$run_dir/lease" ]] || [[ ! -r "$run_dir/lease" ]]; then
    printf '%s\n' "missing"
    return 0
  fi

  local state heartbeat stale_after skew_grace now delta
  state=$(lease_field "$run_dir/lease" state)
  heartbeat=$(lease_field "$run_dir/lease" heartbeat_at)
  stale_after=$(lease_field "$run_dir/lease" stale_after_s)
  skew_grace=$(lease_field "$run_dir/lease" skew_grace_s)

  if [[ "$state" == "released" ]]; then
    printf '%s\n' "released"
    return 0
  fi

  if [[ ! "$heartbeat" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "missing"
    printf '%s: lease carries no usable heartbeat_at; treating as missing\n' "$PROG" >&2
    return 0
  fi
  [[ "$stale_after" =~ ^[0-9]+$ ]] || stale_after="$DEFAULT_STALE_AFTER_S"
  [[ "$skew_grace" =~ ^[0-9]+$ ]] || skew_grace="$DEFAULT_SKEW_GRACE_S"

  now=$(now_epoch)
  delta=$((now - heartbeat))

  # Two-sided, and both sides are load-bearing. The upper bound is the ordinary
  # staleness test. The LOWER bound is what keeps a forward clock jump from
  # pinning a dead run live forever: liveness tested only as
  # `now - heartbeat < stale_after` reads a future timestamp as live for the
  # whole skew interval even after the process is gone, so every --resume refuses
  # an abandoned run indefinitely — the failure that costs the artifact rather
  # than a re-run.
  if [[ "$delta" -lt $((-skew_grace)) ]]; then
    printf '%s\n' "stale"
    printf '%s: heartbeat_at is %ss in the future (grace %ss) — clock skew, not life\n' \
      "$PROG" "$((-delta))" "$skew_grace" >&2
    return 0
  fi
  if [[ "$delta" -ge "$stale_after" ]]; then
    printf '%s\n' "stale"
    return 0
  fi
  printf '%s\n' "live"
}

cmd_partial_append() {
  local run_dir="" record="" held_epoch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    --record)
      [[ $# -ge 2 ]] || die "--record needs a JSON line"
      record="$2"
      shift 2
      ;;
    --epoch)
      [[ $# -ge 2 ]] || die "--epoch needs an integer"
      held_epoch="$2"
      shift 2
      ;;
    *) die "unknown argument to partial append: $1" ;;
    esac
  done
  require_run_dir "$run_dir"

  # A record with no lease could not be classified on resume — resume reads the
  # lease before it reads the partial — so the partial is never written without
  # one. This is also what makes the epoch in the filename a real value rather
  # than a default.
  if [[ ! -f "$run_dir/lease" ]]; then
    die "no lease at $run_dir/lease — acquire one before appending to the partial"
  fi

  if [[ -z "$record" ]]; then
    die "--record must not be empty"
  fi
  # One JSON object per line is the whole point of an append-only artifact: a
  # record carrying a newline would split into two rows, and the second would be
  # unparsable.
  case "$record" in
  *$'\n'*) die "--record must be a single line" ;;
  *) : ;;
  esac
  if ! record_is_json_object "$record"; then
    die "--record must be a well-formed single-line JSON object: $record"
  fi

  local epoch file
  epoch=$(lease_field "$run_dir/lease" owner_epoch)
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    die "lease carries no usable owner_epoch at: $run_dir/lease"
  fi

  # THE EPOCH IN THE FILENAME IS THE WRITER'S, NEVER THE LEASE'S CURRENT ONE.
  # Reading it from the lease at append time is what defeats the isolation §3
  # describes: a stale holder that wakes after an adopter incremented the epoch
  # would read the adopter's value and append into the adopter's file, so two
  # writers interleave under one attempt ordinal — the one failure the attempt
  # machinery cannot absorb. A writer that knows the epoch it holds passes it,
  # and it lands in its OWN superseded file no matter what the lease now says.
  # Omitting the flag is only correct for a run whose epoch nothing has moved.
  local fenced=0
  if [[ -n "$held_epoch" ]]; then
    require_int_at_least_one "--epoch" "$held_epoch" "epochs start at 1"
    if [[ "$held_epoch" != "$epoch" ]]; then
      fenced=1
      printf '%s: FENCED — lease owner_epoch is %s but this writer holds %s; the record lands in the writer'"'"'s own epoch file and this run must stop (exit %s)\n' \
        "$PROG" "$epoch" "$held_epoch" "$EXIT_FENCED" >&2
    fi
    epoch="$held_epoch"
  fi
  file="$run_dir/findings.partial.$epoch.jsonl"

  # Appended, never rewritten. A single JSON document would be rewritten whole on
  # every append, which is exactly the operation an interrupted run leaves
  # half-done.
  printf '%s\n' "$record" >>"$file" || die "cannot append to: $file"
  printf '%s\n' "$file"

  # THE FENCE IS ENFORCED BY THE EXIT CODE, NOT BY THE MESSAGE. A diagnostic on
  # stderr saying "this run must abort" is a control announcing a state it never
  # establishes: it depends on the caller noticing a substring, and it is
  # indistinguishable in form from any other diagnostic. `classify` already puts
  # its machine-actionable answer on stdout for exactly that reason. So a fenced
  # append exits EXIT_FENCED — the record IS written (to the writer's own file,
  # so nothing interleaves) and the caller is told, in the one channel it cannot
  # miss, that it has been superseded and must stop dispatching.
  if [[ "$fenced" -eq 1 ]]; then
    return "$EXIT_FENCED"
  fi
}

dispatch_lease() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi
  local action="$1"
  shift
  case "$action" in
  acquire) cmd_lease_acquire "$@" ;;
  heartbeat) cmd_lease_heartbeat "$@" ;;
  release) cmd_lease_release "$@" ;;
  classify) cmd_lease_classify "$@" ;;
  *) die "unknown lease action: $action" ;;
  esac
}

dispatch_partial() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
  fi
  local action="$1"
  shift
  case "$action" in
  append) cmd_partial_append "$@" ;;
  *) die "unknown partial action: $action" ;;
  esac
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
  lease) dispatch_lease "$@" ;;
  partial) dispatch_partial "$@" ;;
  *)
    printf '%s: unknown command: %s\n' "$PROG" "$command" >&2
    usage >&2
    exit 2
    ;;
  esac
}

main "$@"
