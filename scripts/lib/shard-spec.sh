# shellcheck shell=bash
# The `--shard <i>/<n>` spec reader shared by scripts/affected-tests.sh and
# scripts/run-plugin-tests.sh. Sourced, never executed. Each caller keeps its
# own error line for a rejected spec.
#
#   parse_shard <spec>
#
# Accepts exactly `<i>/<n>` with i and n decimal, n >= 1 and 0 <= i < n, and
# sets the caller's shard_index and shard_total. Returns 1 and sets nothing for
# any other spec, the empty string included. A spec this function cannot read
# must never become leg 0 of 1, which RUNS EVERYTHING and would report a full
# pass from a typo'd fan-out.

parse_shard() {
  local spec="$1" i n
  [[ "$spec" =~ ^[0-9]+/[0-9]+$ ]] || return 1
  i="${spec%%/*}"
  n="${spec##*/}"
  # Strip leading zeros so `08` is 8 rather than an octal parse error.
  i=$((10#$i))
  n=$((10#$n))
  ((n >= 1 && i < n)) || return 1
  # shellcheck disable=SC2034 # read by the sourcing script
  shard_index="$i"
  # shellcheck disable=SC2034 # read by the sourcing script
  shard_total="$n"
}
