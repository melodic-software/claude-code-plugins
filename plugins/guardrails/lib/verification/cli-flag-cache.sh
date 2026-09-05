# shellcheck shell=bash
# Shared by lib/verification/verify-cli-flag.sh and hooks/cli-flag-verify.sh:
# where the `--help` cache lives, how a cache key is spelled, how long an entry
# stays fresh, and the pattern that decides whether a flag appears in a help
# text. Defined ONCE, because the hook answers cache hits in its own process
# and the verifier answers misses in its own, and two hand-copied definitions
# drifted apart on the first review of that split (a `[` fell out of one
# terminator class, so `--flag[=VALUE]` was known cold and unknown warm).
#
# Sourced, never executed (no shebang, like every other sourced library here).
# Every function assigns into a caller-named variable (`printf -v`) rather
# than printing, so no caller pays a command substitution, which is a fork on
# Windows Git Bash.

# Freshness window for a cached `--help`, in minutes (24 h). Read by both
# sourcing scripts, which is why shellcheck sees no use here.
# shellcheck disable=SC2034
CFV_CACHE_WINDOW_MIN=1440

# cfv_cache_dir_to <var>: the cache directory for this host, forward slashes.
cfv_cache_dir_to() {
  if [[ -n "${LOCALAPPDATA:-}" ]]; then
    printf -v "$1" '%s' "${LOCALAPPDATA//\\//}/guardrails/cli-flag-cache"
  else
    printf -v "$1" '%s' "${XDG_CACHE_HOME:-$HOME/.cache}/guardrails/cli-flag-cache"
  fi
}

# cfv_cache_key_to <var> <bin> [<subcmd>...]: bin and subcommands joined by
# `__`, every path-unsafe character slugified to `_`.
# The locals carry a prefix no caller uses, because `printf -v` writes to the
# NAME it is given: a local named like the caller's target would shadow it and
# the assignment would land here instead of in the caller.
cfv_cache_key_to() {
  local cfv__var="$1" cfv__key="$2" cfv__s
  shift 2
  for cfv__s in "$@"; do
    cfv__key="${cfv__key}__${cfv__s}"
  done
  printf -v "$cfv__var" '%s' "${cfv__key//[^a-zA-Z0-9_-]/_}"
}

# cfv_flag_pattern_to <var> <flag-name>: the ERE that matches <flag-name> as a
# whole flag inside a --help text. The flag may appear as:
#   `  --flag         description`            (column-aligned)
#   `  --flag <ARG>   description`            (with metavar)
#   `  --flag=VALUE`                          (equals form)
#   `  --flag[=VALUE]` / `--flag[-suffix]`    (optional-part notation)
#   `  -F, --flag`                            (with short form)
#   `  --flag, -F`                            (reverse short form)
#   `  [--flag]`                              (optional-arg notation)
#   `  [-S|--save|--save-dev|--save-optional]` (pipe-separated synopsis)
#   `--flag` inside a usage line               (rare but valid)
# The leading class (or the start) and the trailing terminator class (or the
# end) prevent a prefix match: `--save-dev` never satisfies `--save-developer`.
# The trailing class lists `]` first (literal), then the POSIX space class and
# the remaining literals, `[` among them. Used with bash `=~` over a whole
# multi-line text, the leading class admits the newline before a line start,
# so it matches exactly where a line-wise `grep -E` would.
cfv_flag_pattern_to() {
  printf -v "$1" '%s' "(^|[^a-zA-Z0-9_-])${2}([][:space:]=,|)[]|\$)"
}

# cfv_flag_in_help <help-text> <flag-name>: 0 when the flag appears.
cfv_flag_in_help() {
  local cfv__pat
  cfv_flag_pattern_to cfv__pat "$2"
  [[ "$1" =~ $cfv__pat ]]
}
