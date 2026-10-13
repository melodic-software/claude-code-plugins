#!/usr/bin/env bash
# version.sh: dotted-version helpers shared by this plugin's scripts.
#
# WHY ONE COMPARATOR. `skills/migrate/scripts/cutover-check.sh` and
# `remove-shims.sh` compare CLI versions against a floor, and
# `scripts/precompute.sh` compares the installed CLI against the newest version
# the loading-mechanics record was measured on. Separate copies of the
# comparison would be separate places for a leading-zero or missing-component
# bug to be fixed in one and not the others.
#
# Sourced, never executed. Every function returns a status or prints a value;
# none exits, so a caller in a skill header keeps its own degradation rules.

# `a >= b` over dotted numeric versions. `sort -V` would do it and is GNU-only.
# A missing component counts as 0, and 10# keeps a leading zero from reading as
# octal. Either side not a dotted number returns 2 before any comparison, so a
# malformed later component cannot ride on an earlier one that already decided
# the order, and no component reaches the arithmetic, where bash would evaluate
# it as an expression: a version read from a plugin manifest is not trusted
# text. Callers that test only for success fail closed.
ip_ver_ge() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ && "$2" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 2
  local -a a b
  local i x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}

# `a > b`, strictly. Returns 2, not success, when either side is not numeric.
ip_ver_gt() {
  ip_ver_ge "$1" "$2" || return
  ! ip_ver_ge "$2" "$1"
}

# The first X.Y.Z in a line such as `2.1.288 (Claude Code)`, or nothing.
ip_version_in() {
  [[ "$1" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
  return 0
}

# The newest Claude Code version a first-party measurement in the record at
# path $1 names, or nothing when the file is unreadable or names none.
#
# A measurement is stamped inside an italic citation marker, `*(measured
# 2.1.268)*`, `*(doc, measured 2.1.238 and 2.1.278)*`. Only the versions after
# the word `measured`, up to the marker's next comma, count: in `*(changelog
# 2.1.288, measured 2.1.268)*` the 2.1.288 is a release note, not a
# measurement, and reading it would hide a stale record behind a version
# nothing was measured on. A version-less `*(measured)*` names nothing. The
# first standalone `measured` in a marker is the stamp: a later word such as
# `unmeasured` does not move the cut past it.
ip_mechanics_measured_max() {
  local file="$1" max="" marker rest v
  [[ -r "$file" ]] || return 0
  while IFS= read -r marker; do
    [[ "$marker" =~ (^|[^[:alnum:]-])measured([^,]*) ]] || continue
    rest="${BASH_REMATCH[2]}"
    while [[ "$rest" =~ ([0-9]+\.[0-9]+\.[0-9]+)(.*) ]]; do
      v="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"
      if [[ -z "$max" ]] || ip_ver_gt "$v" "$max"; then max="$v"; fi
    done
  done < <(grep -oE '\*\([^)]*\)\*' "$file" 2>/dev/null)
  printf '%s' "$max"
}
