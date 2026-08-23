# shellcheck shell=bash
# Shared awk-operand handling for the token-list scanners. Sourced, never executed.
#
# check-shell-portability.sh and check-skill-portability.sh are twins: both load
# a `<token> <ere>` data file with awk's `FNR == NR` idiom and then scan a file
# per invocation, passing BOTH as awk operands. That shape has a silent
# fail-open, fixed once in #1513 and then not propagated -- the divergence
# #2914 (finding 2) filed:
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
# filename -- and the bug was that one line living in one of the two twins. At
# extraction time check-shell-portability.sh guarded both its token list and
# each scanned file, while check-skill-portability.sh guarded only the scanned
# file and left its token list exposed to exactly the #1513 fail-open.
#
# WHAT IS DELIBERATELY NOT HERE. The mode dispatch (`<base-ref>` / `--all` /
# `--paths`) and the awk programs stay in the two gates. They are not near-
# duplicates the way the operand guard was: the scanners select over different
# pathspecs, apply different scannability predicates, and only
# check-shell-portability.sh consults a skill-markdown baseline. Hoisting a
# parameterized dispatcher over those differences would trade a real duplicate
# for a fake abstraction -- so this file owns the one thing the two genuinely
# share, and the rest of finding 2's remediation is left as filed.

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

# token_scan::require_token_file <out-var> <path>
#
# Validates that <path> exists and assigns the operand-safe form to <out-var>.
# Returns 1 (caller exits 2) with the diagnostic both gates already printed
# verbatim when the file is missing -- a token list that is absent must fail the
# gate closed, for the same reason one that is silently unopened must: a scan
# with no patterns is not a clean scan.
token_scan::require_token_file() {
  local -n _ts_tokens_out="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    printf 'Error: token list not found: %s\n' "$path" >&2
    return 1
  fi
  _ts_tokens_out="$(token_scan::awk_operand "$path")"
  return 0
}
