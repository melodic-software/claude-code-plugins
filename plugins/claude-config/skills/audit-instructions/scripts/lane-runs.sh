#!/usr/bin/env bash
# lane-runs.sh: the deterministic half of audit-instructions' execution model.
# Phase B's lanes are sized from a token budget, persisted one file per lane
# under a run directory, and resumed by re-running only the lanes whose report
# is incomplete or whose inputs changed. Everything a model would otherwise
# re-derive by hand, and could derive two ways, lives here.
#
#   lane-runs.sh partition --window-tokens <n> --fraction <f> --bytes-per-token <b>
#       stdin: one row per in-scope file, `<group>\t<unit>\t<path>`, where
#       <group> is the atomic packing unit (a plugin, or the memory layer) and
#       <unit> is what an oversized group splits by (a skill, or a file).
#       Packs whole groups into lanes up to the byte budget; a group larger than
#       the budget is split by unit into lanes of its own. Prints `key=value`
#       header lines (budget_tokens, budget_bytes, bytes_per_line, budget_lines,
#       lanes, partition_digest), one `split=<group>:<lanes>` line per split
#       group, then `lane\t<id>\t<bytes>\t<members>` and
#       `file\t<id>\t<path>` rows. A single unit larger than the budget still
#       gets one lane and is named on an `over_budget=<group>/<unit>` line.
#
#   lane-runs.sh digest --partition-digest <d> --param <key>=<value>... -- <file>...
#       Prints `sha256:<hex>` over the ordered file list with each file's
#       content hash, the partition digest, and every --param sorted by key.
#       The keys in REQUIRED_PARAMS must all be present, so a caller cannot
#       leave a behavior-affecting input out of the digest by omission.
#
#   lane-runs.sh marker --lane <id> --digest <d>
#       Prints the completion marker a lane report must end with.
#
#   lane-runs.sh plan --run-dir <dir>
#       stdin: `<lane-id>\t<digest>` rows. Prints `<lane-id>\t<reuse|rerun>\t<reason>`
#       per lane, reason one of complete, missing, incomplete, digest-changed,
#       judged against `<run-dir>/lanes/<lane-id>.md`.
#
#   lane-runs.sh latest --runs-dir <dir>
#       Prints the newest run id (a `YYYYMMDDTHHMMSSZ` directory) under
#       `<plugin-data>/audit-instructions/runs/<state-key>/`.
#
#   lane-runs.sh attach --run-dir <dir>
#       Classifies the run's lease through audit-pass's run-state.sh. A live
#       lease is refused (exit 4) with its heartbeat_at and stale_after_s named;
#       otherwise prints `verdict=<stale|released|missing>` and
#       `next_epoch=<n>` for the adopting `lease acquire --epoch`.
#
# The lease itself is never reimplemented here: acquire, heartbeat, and release
# go straight to audit-pass's run-state.sh, invoked with
# `--plugin-data <plugin-data>/audit-instructions` so its `<plugin-data>/runs/`
# containment pin holds for this skill's tree.
#
# Portability: bash, coreutils, awk, and one of sha256sum / shasum. No jq.
#
# Exit: 0 success; 1 `latest` found no run; 2 usage error; 4 `attach` refused a
# live lease.
set -uo pipefail

PROG="lane-runs.sh"
EXIT_LIVE_LEASE=4
REQUIRED_PARAMS="catalog_version conflict_criteria_version prompt_digest harness_version target_model scope opinion no_stopping_condition"
MARKER_PREFIX="<!-- audit-instructions lane-complete"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_STATE="$SCRIPT_DIR/../../audit-pass/scripts/run-state.sh"

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

usage() {
  sed -n '2,/^set -uo pipefail$/{/^set -uo/d;s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die "neither sha256sum nor shasum is on PATH"
  fi
}

sha256_file() {
  sha256_stdin <"$1"
}

require_positive_number() {
  local name="$1" value="$2"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || awk -v v="$value" 'BEGIN{exit !(v <= 0)}'; then
    die "$name must be a positive number: $value"
  fi
}

lane_id_for() {
  local first="$1" members="$2" slug
  slug=$(printf '%s' "$first" | tr '/' '.' | tr -c 'A-Za-z0-9_.-' '-')
  slug="${slug#[.-]}"
  printf '%s-%s' "${slug:-lane}" "$(printf '%s' "$members" | sha256_stdin | cut -c1-8)"
}

cmd_partition() {
  local window="" fraction="" bpt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --window-tokens)
      [[ $# -ge 2 ]] || die "--window-tokens needs a value"
      window="$2"
      shift 2
      ;;
    --fraction)
      [[ $# -ge 2 ]] || die "--fraction needs a value"
      fraction="$2"
      shift 2
      ;;
    --bytes-per-token)
      [[ $# -ge 2 ]] || die "--bytes-per-token needs a value"
      bpt="$2"
      shift 2
      ;;
    *) die "unknown argument to partition: $1" ;;
    esac
  done
  [[ -n "$window" && -n "$fraction" && -n "$bpt" ]] ||
    die "partition needs --window-tokens, --fraction, and --bytes-per-token"
  [[ "$window" =~ ^[0-9]+$ && "$window" -gt 0 ]] || die "--window-tokens must be a positive integer: $window"
  require_positive_number "--fraction" "$fraction"
  awk -v f="$fraction" 'BEGIN{exit !(f > 1)}' && die "--fraction must be at most 1: $fraction"
  require_positive_number "--bytes-per-token" "$bpt"

  local rows="" group unit path bytes lines total_bytes=0 total_lines=0
  while IFS=$'\t' read -r group unit path || [[ -n "${group:-}" ]]; do
    [[ -z "${group:-}" ]] && continue
    [[ -n "${unit:-}" && -n "${path:-}" ]] || die "input row needs <group>\\t<unit>\\t<path>: $group"
    [[ -f "$path" ]] || die "no such file: $path"
    bytes=$(wc -c <"$path" | tr -d ' ')
    lines=$(wc -l <"$path" | tr -d ' ')
    total_bytes=$((total_bytes + bytes))
    total_lines=$((total_lines + lines))
    rows+="$group"$'\t'"$unit"$'\t'"$path"$'\t'"$bytes"$'\n'
  done
  [[ -n "$rows" ]] || die "partition read no input rows"

  local budget_tokens budget_bytes bytes_per_line budget_lines
  budget_tokens=$(awk -v w="$window" -v f="$fraction" 'BEGIN{printf "%d", w * f}')
  budget_bytes=$(awk -v t="$budget_tokens" -v b="$bpt" 'BEGIN{printf "%d", t * b}')
  [[ "$budget_bytes" -gt 0 ]] || die "the budget rounds to zero bytes"
  bytes_per_line=$(awk -v b="$total_bytes" -v l="$total_lines" 'BEGIN{if (l < 1) l = 1; printf "%.1f", b / l}')
  budget_lines=$(awk -v b="$budget_bytes" -v p="$bytes_per_line" 'BEGIN{if (p <= 0) p = 1; printf "%d", b / p}')

  # Sorted so the partition is a function of the input set, never of the order
  # a caller happened to enumerate it in.
  rows=$(printf '%s' "$rows" | LC_ALL=C sort -t $'\t' -k1,1 -k2,2 -k3,3)

  local plan
  plan=$(printf '%s\n' "$rows" | awk -F '\t' -v budget="$budget_bytes" '
    {
      g = $1; u = $2
      if (!(g in gbytes)) { gorder[++ng] = g }
      gbytes[g] += $4
      key = g SUBSEP u
      if (!(key in ubytes)) { uorder[g, ++nu[g]] = u }
      ubytes[key] += $4
    }
    function close_lane() {
      if (cur_members != "") { print "L\t" cur_bytes "\t" cur_members; nl++ }
      cur_members = ""; cur_bytes = 0
    }
    END {
      cur_members = ""; cur_bytes = 0
      for (i = 1; i <= ng; i++) {
        g = gorder[i]
        if (gbytes[g] <= budget) {
          if (cur_members != "" && cur_bytes + gbytes[g] > budget) close_lane()
          cur_members = (cur_members == "" ? g : cur_members "," g)
          cur_bytes += gbytes[g]
          continue
        }
        close_lane()
        before = nl
        for (j = 1; j <= nu[g]; j++) {
          u = uorder[g, j]; b = ubytes[g SUBSEP u]
          if (b > budget) print "O\t" g "/" u
          if (cur_members != "" && cur_bytes + b > budget) close_lane()
          cur_members = (cur_members == "" ? g "/" u : cur_members "," g "/" u)
          cur_bytes += b
        }
        close_lane()
        print "S\t" g "\t" (nl - before)
      }
      close_lane()
    }')

  local lane_rows="" split_rows="" over_rows="" file_rows="" kind a b members id first n=0
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
    L)
      members="$b"
      first="${members%%,*}"
      id=$(lane_id_for "$first" "$members")
      lane_rows+="lane"$'\t'"$id"$'\t'"$a"$'\t'"$members"$'\n'
      n=$((n + 1))
      local m
      IFS=',' read -r -a member_list <<<"$members"
      for m in "${member_list[@]}"; do
        while IFS=$'\t' read -r group unit path bytes; do
          if [[ "$m" == "$group" || "$m" == "$group/$unit" ]]; then
            file_rows+="file"$'\t'"$id"$'\t'"$path"$'\n'
          fi
        done <<<"$rows"
      done
      ;;
    S) split_rows+="split=$a:$b"$'\n' ;;
    O) over_rows+="over_budget=$a"$'\n' ;;
    esac
  done <<<"$plan"

  local partition_digest
  partition_digest="sha256:$(printf '%s' "$lane_rows$file_rows" | sha256_stdin)"

  printf 'budget_tokens=%s\n' "$budget_tokens"
  printf 'budget_bytes=%s\n' "$budget_bytes"
  printf 'bytes_per_line=%s\n' "$bytes_per_line"
  printf 'budget_lines=%s\n' "$budget_lines"
  printf 'lanes=%s\n' "$n"
  printf 'partition_digest=%s\n' "$partition_digest"
  printf '%s' "$split_rows$over_rows$lane_rows$file_rows"
}

cmd_digest() {
  local partition="" params=() files=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --partition-digest)
      [[ $# -ge 2 ]] || die "--partition-digest needs a value"
      partition="$2"
      shift 2
      ;;
    --param)
      [[ $# -ge 2 ]] || die "--param needs <key>=<value>"
      [[ "$2" == *=* && "${2%%=*}" =~ ^[a-z_]+$ ]] || die "--param must be <key>=<value> with a lowercase key: $2"
      params+=("$2")
      shift 2
      ;;
    --)
      shift
      files=("$@")
      break
      ;;
    *) die "unknown argument to digest: $1" ;;
    esac
  done
  [[ -n "$partition" ]] || die "digest needs --partition-digest"
  [[ ${#files[@]} -gt 0 ]] || die "digest needs at least one file after --"

  local key p found missing=""
  for key in $REQUIRED_PARAMS; do
    found=0
    for p in "${params[@]}"; do
      [[ "${p%%=*}" == "$key" ]] && found=1
    done
    [[ "$found" -eq 1 ]] || missing+=" $key"
  done
  [[ -z "$missing" ]] || die "digest is missing required --param keys:$missing"

  local f body=""
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || die "no such file: $f"
    body+="file"$'\t'"$f"$'\t'"$(sha256_file "$f")"$'\n'
  done
  body+="partition"$'\t'"$partition"$'\n'
  body+=$(printf '%s\n' "${params[@]}" | LC_ALL=C sort | sed 's/^/param\t/')
  printf 'sha256:%s\n' "$(printf '%s\n' "$body" | sha256_stdin)"
}

marker_line() {
  printf '%s lane=%s digest=%s -->' "$MARKER_PREFIX" "$1" "$2"
}

cmd_marker() {
  local lane="" digest=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --lane)
      [[ $# -ge 2 ]] || die "--lane needs a value"
      lane="$2"
      shift 2
      ;;
    --digest)
      [[ $# -ge 2 ]] || die "--digest needs a value"
      digest="$2"
      shift 2
      ;;
    *) die "unknown argument to marker: $1" ;;
    esac
  done
  [[ -n "$lane" && -n "$digest" ]] || die "marker needs --lane and --digest"
  marker_line "$lane" "$digest"
  printf '\n'
}

cmd_plan() {
  local run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to plan: $1" ;;
    esac
  done
  [[ -n "$run_dir" ]] || die "plan needs --run-dir"

  local lane digest report last
  while IFS=$'\t' read -r lane digest || [[ -n "${lane:-}" ]]; do
    [[ -z "${lane:-}" ]] && continue
    [[ "$lane" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die "lane id must be a plain path segment: $lane"
    [[ -n "${digest:-}" ]] || die "plan row needs <lane-id>\\t<digest>: $lane"
    report="$run_dir/lanes/$lane.md"
    if [[ ! -f "$report" ]]; then
      printf '%s\trerun\tmissing\n' "$lane"
      continue
    fi
    # The marker counts only as the report's last non-blank line: a lane cut
    # off mid-write can carry an earlier marker it never finished past.
    last=$(awk 'NF {l = $0} END {print l}' "$report")
    if [[ "$last" == "$(marker_line "$lane" "$digest")" ]]; then
      printf '%s\treuse\tcomplete\n' "$lane"
    elif [[ "$last" == "$MARKER_PREFIX lane=$lane digest="*" -->" ]]; then
      printf '%s\trerun\tdigest-changed\n' "$lane"
    else
      printf '%s\trerun\tincomplete\n' "$lane"
    fi
  done
}

cmd_latest() {
  local runs_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --runs-dir)
      [[ $# -ge 2 ]] || die "--runs-dir needs a path"
      runs_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to latest: $1" ;;
    esac
  done
  [[ -n "$runs_dir" ]] || die "latest needs --runs-dir"
  local d name newest=""
  if [[ -d "$runs_dir" ]]; then
    for d in "$runs_dir"/*/; do
      [[ -d "$d" ]] || continue
      name="${d%/}"
      name="${name##*/}"
      [[ "$name" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || continue
      [[ "$name" > "$newest" ]] && newest="$name"
    done
  fi
  if [[ -z "$newest" ]]; then
    printf '%s: no run under %s\n' "$PROG" "$runs_dir" >&2
    return 1
  fi
  printf '%s\n' "$newest"
}

lease_field() {
  awk -v k="$2" 'index($0, k "=") == 1 {print substr($0, length(k) + 2)}' "$1"
}

cmd_attach() {
  local run_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --run-dir)
      [[ $# -ge 2 ]] || die "--run-dir needs a path"
      run_dir="$2"
      shift 2
      ;;
    *) die "unknown argument to attach: $1" ;;
    esac
  done
  [[ -n "$run_dir" ]] || die "attach needs --run-dir"
  [[ -f "$RUN_STATE" ]] || die "cannot find audit-pass run-state.sh at: $RUN_STATE"

  local verdict epoch
  verdict=$(bash "$RUN_STATE" lease classify --run-dir "$run_dir") || die "run-state.sh lease classify failed for: $run_dir"
  if [[ "$verdict" == "live" ]]; then
    printf '%s: refusing to attach: the run at %s holds a live lease (heartbeat_at=%s, stale_after_s=%s); resume once it is released or older than stale_after_s\n' \
      "$PROG" "$run_dir" \
      "$(lease_field "$run_dir/lease" heartbeat_at_iso)" \
      "$(lease_field "$run_dir/lease" stale_after_s)" >&2
    return "$EXIT_LIVE_LEASE"
  fi
  epoch=0
  if [[ -f "$run_dir/lease" ]]; then
    epoch=$(lease_field "$run_dir/lease" owner_epoch)
    [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
  fi
  printf 'verdict=%s\n' "$verdict"
  printf 'next_epoch=%s\n' "$((epoch + 1))"
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 2
  }
  local command="$1"
  shift
  case "$command" in
  -h | --help) usage ;;
  partition) cmd_partition "$@" ;;
  digest) cmd_digest "$@" ;;
  marker) cmd_marker "$@" ;;
  plan) cmd_plan "$@" ;;
  latest) cmd_latest "$@" ;;
  attach) cmd_attach "$@" ;;
  *) die "unknown command: $command" ;;
  esac
}

main "$@"
