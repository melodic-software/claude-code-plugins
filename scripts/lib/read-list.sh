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
#   read_list::into_text <out-array> <text> --comments inline|leading
#
# The same parse over a string already in hand. It exists for the one consumer
# whose list is not a working-tree file: check-contract-slice-prune.sh reads its
# baseline out of a git rev, so there is no path to open. Reading a rev through
# a temp file only to reopen it would put the parse back in two places, which is
# the divergence this library removes.
#
# THE STALE-ENTRY GUARD
#
# Every list here is an exemption list, and an exemption must not outlive what
# it excuses: an entry whose target is gone or fixed would silently re-authorize
# the next thing that lands on that name. Thirteen gates enforced that
# themselves, in five consumed-tracking shapes and under eight diagnostic
# prefixes, so an operator reading CI could not tell one gate's stale entry from
# another's. The facility is:
#
#   read_list::mark_used <entry>...     the entry is still doing its job
#   read_list::stale_to <out-array> <list-array>
#                                       the entries never marked, in list order
#   read_list::stale_line <label> <entry> <reason>
#                                       one unified diagnostic line on stderr
#   read_list::report_stale <list-array> <label> <reason>
#                                       stale_to plus stale_line for each; 1 when
#                                       any entry was stale
#   read_list::reset_used               forget every mark
#
# STALE BASELINE is the prefix, because it is the one the most gates already
# printed. `stale_line` is public so a gate whose entries go stale for DIFFERENT
# reasons (a baseline name that gained a CHANGELOG versus one that never named a
# plugin) still prints the one prefix instead of re-typing it.
#
# The marks live in one process-wide set keyed by the entry text, not per list.
# A gate holding two lists marks into the same set, which is correct as long as
# the two lists do not share an entry string; the lists in this repo hold
# disjoint kinds of token (paths, slugs, finding kinds). `reset_used` is there
# for a caller that reuses one entry string across two lists, and for tests.
#
# Every local carries the `_rl_` prefix, and that is a correctness requirement
# rather than a naming style. A bash nameref resolves its target in the scope
# where it is USED, so an unprefixed local sharing the caller's chosen out-var
# name shadows that caller's variable for the rest of the call -- measured on
# scripts/lib/changed-files.sh before #3144, two plausible names came back
# SILENTLY EMPTY. Do not introduce an unprefixed local here.

# _read_list::mode <out-var> <arg>...
# Resolves the shared `--comments` option for both public readers.
_read_list::mode() {
  local -n _rl_mode_out="$1"
  shift
  _rl_mode_out=""
  while (($# > 0)); do
    case "$1" in
    --comments)
      _rl_mode_out="${2-}"
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
  case "$_rl_mode_out" in
  inline | leading) return 0 ;;
  "")
    printf 'read-list: --comments is required (inline|leading); there is no default\n' >&2
    return 2
    ;;
  *)
    printf 'read-list: unknown --comments mode %s (want inline|leading)\n' "$_rl_mode_out" >&2
    return 2
    ;;
  esac
}

# _read_list::parse <out-array> <mode>, list on stdin.
# The one copy of the parse. Both public readers redirect their source into it,
# so a file and a string in hand cannot answer differently.
_read_list::parse() {
  local -n _rl_parse_out="$1"
  local _rl_parse_mode="$2"

  _rl_parse_out=()
  local _rl_line
  # The `|| [[ -n "$_rl_line" ]]` tail keeps a final line with no trailing
  # newline: `read` returns non-zero there even though it filled the variable,
  # and dropping that entry would be a silent under-read of the list.
  while IFS= read -r _rl_line || [[ -n "$_rl_line" ]]; do
    _rl_line="${_rl_line%$'\r'}"
    if [[ "$_rl_parse_mode" == inline ]]; then
      _rl_line="${_rl_line%%#*}"
    fi
    # Trim both ends. Done after inline stripping so `entry   # note` loses the
    # whitespace the comment left behind, and before the leading-# test so an
    # indented comment is still recognised as one.
    _rl_line="${_rl_line#"${_rl_line%%[![:space:]]*}"}"
    _rl_line="${_rl_line%"${_rl_line##*[![:space:]]}"}"
    [[ -n "$_rl_line" ]] || continue
    if [[ "$_rl_parse_mode" == leading && "$_rl_line" == '#'* ]]; then
      continue
    fi
    _rl_parse_out+=("$_rl_line")
  done
  return 0
}

# read_list::into <out-array> <file> --comments inline|leading
read_list::into() {
  local _rl_name="$1"
  local _rl_file="$2"
  shift 2

  local _rl_mode
  _read_list::mode _rl_mode "$@" || return 2

  if [[ ! -f "$_rl_file" ]]; then
    printf 'read-list: list file not found: %s\n' "$_rl_file" >&2
    return 1
  fi
  if [[ ! -r "$_rl_file" ]]; then
    printf 'read-list: list file not readable: %s\n' "$_rl_file" >&2
    return 1
  fi

  _read_list::parse "$_rl_name" "$_rl_mode" <"$_rl_file"
}

# read_list::into_text <out-array> <text> --comments inline|leading
read_list::into_text() {
  local _rl_name="$1"
  local _rl_text="$2"
  shift 2

  local _rl_mode
  _read_list::mode _rl_mode "$@" || return 2

  _read_list::parse "$_rl_name" "$_rl_mode" <<<"$_rl_text"
}

# ---------------------------------------------------------------------------
# Stale-entry guard. See the header for why it lives here.

# `-g` so the set survives at the sourcing shell's top level regardless of which
# function first touches it, and `=()` so `set -u` never sees it unbound: a
# declared-but-unassigned associative array is UNBOUND in bash, and the
# zero-marks case is exactly the state a shrinking list is driving toward.
declare -gA _RL_USED=()

# read_list::mark_used <entry>...
read_list::mark_used() {
  local _rl_entry
  for _rl_entry in "$@"; do
    _RL_USED["$_rl_entry"]=1
  done
}

# read_list::reset_used
read_list::reset_used() {
  _RL_USED=()
}

# read_list::stale_to <out-array> <list-array>
# Fills <out-array> with the entries of <list-array> that were never marked
# used, in list order and de-duplicated.
read_list::stale_to() {
  local -n _rl_stale_out="$1"
  local -n _rl_stale_list="$2"
  _rl_stale_out=()
  local -A _rl_seen=()
  local _rl_entry
  for _rl_entry in ${_rl_stale_list[@]+"${_rl_stale_list[@]}"}; do
    [[ -n "${_RL_USED[$_rl_entry]:-}" ]] && continue
    [[ -n "${_rl_seen[$_rl_entry]:-}" ]] && continue
    _rl_seen["$_rl_entry"]=1
    _rl_stale_out+=("$_rl_entry")
  done
  return 0
}

# read_list::stale_line <label> <entry> <reason>
# The single spelling of the diagnostic. <label> names the list (its path, or
# whatever the gate calls it) and <reason> says what the entry stopped doing.
read_list::stale_line() {
  printf "STALE BASELINE: %s: '%s' %s\n" "$1" "$2" "$3" >&2
}

# read_list::report_stale <list-array> <label> <reason>
# Reports every unmarked entry under the one prefix. Returns 1 when the list
# held at least one stale entry, 0 when it held none.
read_list::report_stale() {
  local _rl_list_name="$1" _rl_label="$2" _rl_reason="$3"
  local -a _rl_stale=()
  read_list::stale_to _rl_stale "$_rl_list_name"
  ((${#_rl_stale[@]} > 0)) || return 0
  local _rl_entry
  for _rl_entry in "${_rl_stale[@]}"; do
    read_list::stale_line "$_rl_label" "$_rl_entry" "$_rl_reason"
  done
  return 1
}
