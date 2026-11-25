# shellcheck shell=bash

parse_shard() {
  local spec="$1" i n
  [[ "$spec" =~ ^[0-9]+/[0-9]+$ ]] || return 1
  i="${spec%%/*}"
  n="${spec##*/}"
  i=$((10#$i))
  n=$((10#$n))
  ((n >= 1 && i < n)) || return 1
  # shellcheck disable=SC2034 # read by the sourcing script
  shard_index="$i"
  # shellcheck disable=SC2034 # read by the sourcing script
  shard_total="$n"
}
