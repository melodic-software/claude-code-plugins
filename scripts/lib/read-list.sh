# shellcheck shell=bash
# Shared reader for the `scripts/*.txt` list files. Sourced, never executed.
#
# Fifteen data files under scripts/ share one job -- one active entry per line,
# with comments and blanks ignored -- and eight parsers implemented it, in four
# spellings across TWO different comment semantics (#3161):
#
#   inline  `sed -E 's/#.*//'` or bash `${line%%#*}`, then trim, then drop empty.
#           A `#` ANYWHERE on the line starts a comment.
#           Was: check-docs-only.sh, check-orphaned-fixtures.sh,
#                check-shell-portability.sh (skill-md baseline),
#                check-changelog-parity.sh, affected-tests.sh
#   leading trim, then drop the line only if it is empty or BEGINS with `#`.
#           An inline `#` is kept as data.
#           Was: the awk `FNR == NR` token loaders in check-shell-portability.sh
#                and check-skill-portability.sh, and check-hook-userconfig-argv.sh
#
# THE TWO SEMANTICS ARE BOTH CORRECT AND MUST STAY DISTINCT. Token-list entries
# are EREs, and a regex may legitimately contain `#`; applying the inline rule to
# a token list would truncate such a pattern, or empty it entirely. An emptied
# pattern in a token list is the #1513 shape -- a gate that enforces nothing and
# still exits 0. So `--comments` is REQUIRED and has no default: a caller must
# say which family its file belongs to, exactly as `changed_files::into` makes
# `--include-deleted` an explicit per-call-site decision rather than a default
# that silently suits one caller and corrupts another.
#
# Measured at extraction time: no active line in any of the fifteen files
# contains a non-leading `#`, so the divergence was LATENT, not live. This
# library exists so it stays that way once one does.
#
# NO ESCAPE SYNTAX, deliberately. A `\#` escape in the inline mode was
# considered and rejected: no current file needs it, adding it would silently
# change how an existing entry containing `\#` parses, and the leading mode
# already covers "the `#` is data". A file that needs a literal non-leading `#`
# belongs in the leading family.
#
# CR TOLERANCE is unconditional. `.gitattributes` pins `* text=auto eol=lf`, so a
# trailing CR should never reach a checkout -- but check-hook-userconfig-argv.sh
# stripped one anyway and the other seven did not, and a lone CR silently
# defeats the exact-match every one of these consumers performs. Doing it here
# costs nothing and removes the last of the four-way divergence.
#
# Usage:
#
#   read_list::into <out-array> <file> --comments inline|leading
#
# Returns non-zero (with a diagnostic on stderr) when <file> is missing or
# unreadable. It never reports an empty list for a file it could not read: an
# empty active set means a gate enforcing nothing, which is the failure mode
# these files exist to prevent.
#
# Every local carries the `_rl_` prefix, and that is a correctness requirement
# rather than a naming style. A bash nameref resolves its target in the scope
# where it is USED, so an unprefixed local sharing the caller's chosen out-var
# name shadows that caller's variable for the rest of the call -- measured on
# scripts/lib/changed-files.sh before #3144, two plausible names came back
# SILENTLY EMPTY. Do not introduce an unprefixed local here.

# read_list::into <out-array> <file> --comments inline|leading
read_list::into() {
  local -n _rl_out="$1"
  local _rl_file="$2"
  shift 2

  local _rl_mode=""
  while (($# > 0)); do
    case "$1" in
    --comments)
      _rl_mode="${2-}"
      # Shift only what is actually there. `shift 2` with `--comments` as the
      # LAST argument shifts nothing and returns non-zero, and the `|| true`
      # this replaces swallowed that: `$#` stayed at 1 and the loop reprocessed
      # `--comments` forever (#3363) instead of ever reaching the rc-2 branch
      # below. Draining to `$# == 0` lets a bare `--comments` fall through to
      # the existing "mode is required" error, the same answer `--comments ''`
      # already gave.
      shift $(($# > 1 ? 2 : 1))
      ;;
    *)
      printf 'read-list: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  case "$_rl_mode" in
  inline | leading) ;;
  "")
    printf 'read-list: --comments is required (inline|leading); there is no default\n' >&2
    return 2
    ;;
  *)
    printf 'read-list: unknown --comments mode %s (want inline|leading)\n' "$_rl_mode" >&2
    return 2
    ;;
  esac

  if [[ ! -f "$_rl_file" ]]; then
    printf 'read-list: list file not found: %s\n' "$_rl_file" >&2
    return 1
  fi
  if [[ ! -r "$_rl_file" ]]; then
    printf 'read-list: list file not readable: %s\n' "$_rl_file" >&2
    return 1
  fi

  _rl_out=()
  local _rl_line
  # The `|| [[ -n "$_rl_line" ]]` tail keeps a final line with no trailing
  # newline: `read` returns non-zero there even though it filled the variable,
  # and dropping that entry would be a silent under-read of the list.
  while IFS= read -r _rl_line || [[ -n "$_rl_line" ]]; do
    _rl_line="${_rl_line%$'\r'}"
    if [[ "$_rl_mode" == inline ]]; then
      _rl_line="${_rl_line%%#*}"
    fi
    # Trim both ends. Done after inline stripping so `entry   # note` loses the
    # whitespace the comment left behind, and before the leading-# test so an
    # indented comment is still recognised as one.
    _rl_line="${_rl_line#"${_rl_line%%[![:space:]]*}"}"
    _rl_line="${_rl_line%"${_rl_line##*[![:space:]]}"}"
    [[ -n "$_rl_line" ]] || continue
    if [[ "$_rl_mode" == leading && "$_rl_line" == '#'* ]]; then
      continue
    fi
    _rl_out+=("$_rl_line")
  done <"$_rl_file"
  return 0
}
