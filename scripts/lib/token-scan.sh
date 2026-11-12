# shellcheck shell=bash
# Shared token-list loading and awk-operand handling for the token-list scanners.
# Sourced, never executed.
#
# check-shell-portability.sh and check-skill-portability.sh are twins: both load
# a `<token> <ere>` data file with awk's `FNR == NR` idiom and then scan a file
# per invocation, passing BOTH as awk operands. That shape has a silent
# fail-open:
#
#   awk parses an operand shaped like identifier=value as a command-line
#   VARIABLE ASSIGNMENT, not as a file to open. A token list reached through
#   `SHELL_PORTABILITY_TOKENS=tokens=custom.txt` is therefore never opened, the
#   loading pass never runs, NO patterns are active, every scanned file reports
#   clean, and awk still exits 0. The gate passes while gating nothing, and the
#   scanner-fault check cannot see it because nothing faulted.
#
# The fix is one line -- prefix an unrooted operand with `./`, which is never a
# valid awk identifier lead character, so the operand can only parse as a
# filename -- and it lives here so neither twin can drop it.
#
# WHAT IS DELIBERATELY NOT HERE. The mode dispatch (`<base-ref>` / `--all` /
# `--paths`) and the awk programs stay in the two gates. They are not near-
# duplicates the way the operand guard was: the scanners select over different
# pathspecs, apply different scannability predicates, and only
# check-shell-portability.sh consults a skill-markdown baseline. Hoisting a
# parameterized dispatcher over those differences would trade a real duplicate
# for a fake abstraction -- so this file owns what the two genuinely share: the
# operand guard and the token-list load. The load calls read_list::into, so a
# caller sources read-list.sh too.

# token_scan::awk_operand <path>
#
# Prints <path> in a form awk cannot mistake for a variable assignment. Use it
# on EVERY operand handed to awk -- both the data file and the scanned file.
token_scan::awk_operand() {
  case "$1" in
  ./* | /*) printf '%s' "$1" ;;
  *) printf './%s' "$1" ;;
  esac
}

# token_scan::require_token_file <path>
#
# Validates that <path> exists. Returns 1 (caller exits 2) with the diagnostic
# both gates already printed verbatim when the file is missing -- a token list
# that is absent must fail the gate closed, for the same reason one that is
# silently unopened must: a scan with no patterns is not a clean scan.
token_scan::require_token_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Error: token list not found: %s\n' "$1" >&2
    return 1
  fi
}

# token_scan::load_active <token-file> <active-var> <operand-var>
#
# Loads <token-file>'s active patterns into a temp file, names that file in the
# caller's <active-var>, and puts its awk operand in <operand-var>. Returns
# non-zero (caller exits 2) when the file is missing, unreadable, yields no
# active patterns, or the temp file cannot be made.
#
# Comment and blank lines go through the shared rule in read-list.sh (#3161) in
# `leading` mode: an entry is an ERE (or a `!class` token) and may contain a
# `#`, so only a line that BEGINS with one is a comment. `!class` lines count as
# active. The empty-set guard is why the list is resolved in the shell: a list
# with no active patterns makes every file report clean while awk exits 0, the
# gate passing while gating nothing (#1513).
#
# Call it plainly, never inside `$(...)`: it sets the EXIT trap that removes the
# temp file, and a subshell would drop both the trap and the variables. The trap
# names <active-var>, read at exit, so both variables must be top-level ones the
# caller declares before the call, named outside this function's `_ts_` prefix.
token_scan::load_active() {
  local _ts_src="$1"
  local -n _ts_active="$2" _ts_operand="$3"
  local _ts_patterns=()
  token_scan::require_token_file "$_ts_src" || return 1
  read_list::into _ts_patterns "$_ts_src" --comments leading || return 1
  if ((${#_ts_patterns[@]} == 0)); then
    printf 'Error: token list loaded no active patterns: %s\n' "$_ts_src" >&2
    return 1
  fi
  _ts_active="$(mktemp)" || return 1
  # shellcheck disable=SC2064 # the variable NAME is fixed now; its value expands at exit
  trap "rm -f \"\$$2\"" EXIT
  printf '%s\n' "${_ts_patterns[@]}" >"$_ts_active"
  _ts_operand="$(token_scan::awk_operand "$_ts_active")"
}
