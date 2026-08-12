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
#
# `classify` prints one of `live`, `stale`, `released`, `missing` and exits 0 —
# a classification is an answer, not a failure. Acting on it (refusing `--resume`
# against a `live` lease) belongs to the caller, which is the skill.

set -uo pipefail

PROG="run-state.sh"

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
  run-state.sh lease acquire   --run-dir <dir> --run-id <id> [--stale-after <s>]
                               [--skew-grace <s>] [--epoch <n>]
  run-state.sh lease heartbeat --run-dir <dir>
  run-state.sh lease release   --run-dir <dir>
  run-state.sh lease classify  --run-dir <dir>
  run-state.sh partial append  --run-dir <dir> --record <json-line>

`classify` prints live | stale | released | missing on stdout and exits 0.
Exit 2 is a usage error, a rejected argument, or a missing prerequisite.
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

require_positive_int() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer: $value"
  fi
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
  case "$plugin_data" in
  /* | ?:[\\/]*) : ;;
  *) die "--plugin-data must be an absolute path: $plugin_data" ;;
  esac

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
  local skew_grace="$DEFAULT_SKEW_GRACE_S" epoch=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
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
  require_positive_int "--stale-after" "$stale_after"
  require_positive_int "--skew-grace" "$skew_grace"
  require_positive_int "--epoch" "$epoch"
  if [[ -z "$run_dir" ]]; then
    die "--run-dir is required"
  fi

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
  local run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to lease heartbeat: $1" ;;
    esac
  done
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
  local run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to lease release: $1" ;;
    esac
  done
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
  local run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to lease classify: $1" ;;
    esac
  done
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
  local run_dir="" record=""
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
  # unparseable.
  case "$record" in
  *$'\n'*) die "--record must be a single line" ;;
  *) : ;;
  esac
  case "$record" in
  '{'*) : ;;
  *) die "--record must be a JSON object beginning with '{'" ;;
  esac

  local epoch file
  epoch=$(lease_field "$run_dir/lease" owner_epoch)
  if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
    die "lease carries no usable owner_epoch at: $run_dir/lease"
  fi
  file="$run_dir/findings.partial.$epoch.jsonl"

  # Appended, never rewritten. A single JSON document would be rewritten whole on
  # every append, which is exactly the operation an interrupted run leaves
  # half-done.
  printf '%s\n' "$record" >>"$file" || die "cannot append to: $file"
  printf '%s\n' "$file"
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
