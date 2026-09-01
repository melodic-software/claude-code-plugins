#!/usr/bin/env bash
# Resolve a consumer repository's convention home from the pointer line in its
# root instruction file.
#
# WHY. The config-cascade expression doctrine (docs/conventions/config-cascade/
# README.md § Expression doctrine) binds a consumer's convention home with ONE
# pointer line inside a marked, machine-owned region of the root instruction
# file. The line IS the binding: there is no binding file, so every plugin that
# needs the home reads the same line. Eight plugins each parsing that line in
# their own prose would drift exactly the way retirement detection drifted, so
# the grammar lives here, once, tested, and the doctrine doc cites this helper
# as its owner.
#
# GRAMMAR. The root instruction file carries a region delimited by two marker
# lines (surrounding whitespace and a trailing carriage return are ignored;
# nothing else may share the line):
#
#   <!-- BEGIN GENERATED: convention-home -->
#   Team conventions live in `docs/conventions` — read the topic doc there
#   before changing a governed surface.
#   <!-- END GENERATED: convention-home -->
#
# Inside the region, a POINTER LINE is any line that contains a backticked
# token; the FIRST backticked token on that line is the home. Lines in the
# region with no backticks are prose and are ignored. A backticked path
# anywhere outside the region is not a pointer. The home is a repo-relative
# directory: one or more segments of [A-Za-z0-9._-]+ joined by `/`, no segment
# equal to `.` or `..`, an optional trailing `/` which is dropped on output.
# Anything else — an absolute path, a leading `~`, a backslash, a drive letter,
# whitespace, or an empty token — is an invalid pointer, never a best-effort
# parse.
#
# WHICH FILE. `AGENTS.md` is canonical; `CLAUDE.md` is consulted when AGENTS.md
# carries no region. A CLAUDE.md whose only non-blank content is `@AGENTS.md` is
# a pure import shim and is never consulted. When BOTH files carry a region,
# AGENTS.md supplies the printed value and CLAUDE.md's copy is reported on
# stderr as `duplicate:` — the doctrine calls that a finding with a remediation
# (remove the copy), not a hard stop, so the exit stays 0.
#
# UNTRUSTED INPUT. The root file is consumer prose. Nothing read from it is
# evaluated, expanded, or interpolated into a command: a candidate token is only
# ever compared against the grammar and joined onto --root for a `-d` test.
# Every line is stripped of `\r` and truncated to MAX_LINE bytes before parsing.
#
# Usage:
#   resolve-convention-home.sh [--root <repo>] [--explain] [--help]
#
#   --root <repo>  the repository root (default: ${CLAUDE_PROJECT_DIR}, else the
#                  git toplevel, else the current directory)
#   --explain      write which file, region, and token were used to stderr
#
# Exit:
#   0  exactly one usable pointer resolved and the directory exists; the
#      repo-relative home is printed on stdout (a `duplicate:` warning on
#      stderr does not change this)
#   1  no region, or a region with no pointer line, in any consulted root file
#      — the caller asks the operator; nothing is inferred here
#   2  usage error or an unusable --root
#   3  FAIL, each with a distinct stderr message: two pointer lines in one
#      region; an unterminated or nested region; an invalid pointer path; a
#      pointer whose target directory is missing
#
# Shared source: this is the canonical copy (claude-config). It is NOT yet
# registered in scripts/cross-plugin-source-registry.txt and has no sync
# script; the first consuming plugin adds both in the same change that copies
# it. Bash 3.2-compatible on purpose: no associative arrays, no mapfile, no jq.

set -uo pipefail
# The grammar's character class is ASCII by definition; a collating locale
# would let a bracket range admit letters outside it.
export LC_ALL=C

BEGIN_MARKER='<!-- BEGIN GENERATED: convention-home -->'
END_MARKER='<!-- END GENERATED: convention-home -->'
MAX_LINE=4096

usage() {
  cat <<'EOF'
resolve-convention-home.sh — read the convention-home pointer line.

Prints the repo-relative convention home named by the first backticked token
inside the `<!-- BEGIN GENERATED: convention-home -->` region of AGENTS.md
(canonical) or CLAUDE.md (unless it is a pure `@AGENTS.md` shim).

Usage:
  resolve-convention-home.sh [--root <repo>] [--explain] [--help]

  --root <repo>  repository root (default: CLAUDE_PROJECT_DIR, git toplevel, cwd)
  --explain      write the file, region, and token used to stderr

Exit: 0 resolved (home on stdout); 1 no pointer anywhere (ask); 2 usage;
      3 FAIL — two pointers in one region, unterminated region, invalid path,
      or target directory missing.
EOF
}

ROOT_ARG=""
EXPLAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a path" >&2
      exit 2
    fi
    ROOT_ARG="$2"
    shift 2
    ;;
  --explain)
    EXPLAIN=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -n "$ROOT_ARG" ]]; then
  ROOT="$ROOT_ARG"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  # tr -d '\r': Git on Windows can return a CRLF-terminated path.
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$ROOT" ]] || ROOT="$PWD"
fi
if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: --root is not a directory: $ROOT" >&2
  exit 2
fi

explain() { [[ $EXPLAIN -eq 1 ]] && echo "$*" >&2; return 0; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# is_pure_shim <file>: every non-blank line, after CR strip and trim, is
# `@AGENTS.md`, and there is at least one such line.
is_pure_shim() {
  local line seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "$line" == "@AGENTS.md" ]] || return 1
    seen=1
  done <"$1"
  [[ $seen -eq 1 ]]
}

# scan_file <file>: sets SCAN_STATE to one of
#   none      no region in the file
#   empty     a region exists but holds no pointer line
#   one       exactly one pointer line; SCAN_TOKEN holds its first backticked token
#   many      two or more pointer lines
#   unterminated / nested   a BEGIN with no END, or a BEGIN inside a region
scan_file() {
  local file="$1" line in_region=0 regions=0 pointers=0 rest
  SCAN_STATE="none"
  SCAN_TOKEN=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line:0:$MAX_LINE}"
    case "$(trim "$line")" in
    "$BEGIN_MARKER")
      if [[ $in_region -eq 1 ]]; then
        SCAN_STATE="nested"
        return 0
      fi
      in_region=1
      regions=$((regions + 1))
      continue
      ;;
    "$END_MARKER")
      in_region=0
      continue
      ;;
    *) ;;
    esac
    [[ $in_region -eq 1 ]] || continue
    case "$line" in
    *\`*\`*)
      pointers=$((pointers + 1))
      if [[ $pointers -eq 1 ]]; then
        rest="${line#*\`}"
        SCAN_TOKEN="${rest%%\`*}"
      fi
      ;;
    *) ;;
    esac
  done <"$file"
  if [[ $in_region -eq 1 ]]; then
    SCAN_STATE="unterminated"
  elif [[ $regions -eq 0 ]]; then
    SCAN_STATE="none"
  elif [[ $pointers -eq 0 ]]; then
    SCAN_STATE="empty"
  elif [[ $pointers -eq 1 ]]; then
    SCAN_STATE="one"
  else
    SCAN_STATE="many"
  fi
}

# valid_home <token>: the grammar above. Returns 1 with a reason in
# INVALID_REASON otherwise.
valid_home() {
  local t="$1" seg rest backslash
  backslash=$(printf '%b' '\134')
  INVALID_REASON=""
  if [[ -z "$t" ]]; then INVALID_REASON="empty"; return 1; fi
  case "$t" in
  /*) INVALID_REASON="absolute path" ;;
  '~'*) INVALID_REASON="home-relative (~) path" ;;
  *"$backslash"*) INVALID_REASON="backslash" ;;
  *:*) INVALID_REASON="drive letter or colon" ;;
  *) ;;
  esac
  [[ -z "$INVALID_REASON" ]] || return 1
  t="${t%/}"
  if [[ -z "$t" ]]; then INVALID_REASON="empty"; return 1; fi
  rest="$t/"
  while [[ -n "$rest" ]]; do
    seg="${rest%%/*}"
    rest="${rest#*/}"
    case "$seg" in
    "") INVALID_REASON="empty path segment"; return 1 ;;
    . | ..) INVALID_REASON="dot segment ($seg)"; return 1 ;;
    *[!A-Za-z0-9._-]*) INVALID_REASON="characters outside [A-Za-z0-9._/-]"; return 1 ;;
    *) ;;
    esac
  done
  return 0
}

# TOKEN here is the parser sense: the pointer line scan_file lifts out of a
# convention-home region, never a credential. gitleaks' generic-api-key rule
# keys on the identifier and then takes the next line it can reach as the
# value, so it reports CLAUDE_SHIM=0 as the secret. Annotated rather than
# renamed, because the name is right for what the variable holds.
AGENTS_STATE="none"; AGENTS_TOKEN=""
CLAUDE_STATE="none"; CLAUDE_TOKEN="" # gitleaks:allow
CLAUDE_SHIM=0

if [[ -f "$ROOT/AGENTS.md" ]]; then
  scan_file "$ROOT/AGENTS.md"
  AGENTS_STATE="$SCAN_STATE"; AGENTS_TOKEN="$SCAN_TOKEN"
fi
if [[ -f "$ROOT/CLAUDE.md" ]]; then
  if is_pure_shim "$ROOT/CLAUDE.md"; then
    CLAUDE_SHIM=1
  else
    scan_file "$ROOT/CLAUDE.md"
    CLAUDE_STATE="$SCAN_STATE"; CLAUDE_TOKEN="$SCAN_TOKEN"
  fi
fi

explain "root:      $ROOT"
explain "AGENTS.md: $AGENTS_STATE"
if [[ $CLAUDE_SHIM -eq 1 ]]; then
  explain "CLAUDE.md: pure @AGENTS.md shim (not consulted)"
else
  explain "CLAUDE.md: $CLAUDE_STATE"
fi

# AGENTS.md is canonical whenever it carries a region at all, even a broken one:
# a FAIL in the canonical file is not something CLAUDE.md gets to paper over.
if [[ "$AGENTS_STATE" != "none" ]]; then
  CHOSEN="AGENTS.md"; STATE="$AGENTS_STATE"; TOKEN="$AGENTS_TOKEN"
  if [[ "$CLAUDE_STATE" != "none" ]]; then
    echo "duplicate: CLAUDE.md also carries a convention-home region; AGENTS.md is canonical, remove the CLAUDE.md copy" >&2
  fi
else
  CHOSEN="CLAUDE.md"; STATE="$CLAUDE_STATE"; TOKEN="$CLAUDE_TOKEN"
fi
explain "chosen:    $CHOSEN ($STATE)"

case "$STATE" in
none)
  echo "no convention-home region in AGENTS.md or CLAUDE.md under $ROOT; ask the operator for the home" >&2
  exit 1
  ;;
empty)
  echo "convention-home region in $CHOSEN has no pointer line; ask the operator for the home" >&2
  exit 1
  ;;
many)
  echo "FAIL: two pointer lines in one convention-home region ($CHOSEN); keep exactly one" >&2
  exit 3
  ;;
unterminated)
  echo "FAIL: convention-home region in $CHOSEN has a BEGIN marker with no END marker" >&2
  exit 3
  ;;
nested)
  echo "FAIL: convention-home region in $CHOSEN opens a second BEGIN marker before its END" >&2
  exit 3
  ;;
*) ;;
esac

if ! valid_home "$TOKEN"; then
  echo "FAIL: invalid pointer path in $CHOSEN (${INVALID_REASON}); a home is a repo-relative directory of [A-Za-z0-9._-] segments" >&2
  exit 3
fi
HOME_DIR="${TOKEN%/}"
explain "token:     $TOKEN"

if [[ ! -d "$ROOT/$HOME_DIR" ]]; then
  echo "FAIL: pointer target directory missing: $HOME_DIR (named in $CHOSEN, not found under $ROOT)" >&2
  exit 3
fi

printf '%s\n' "$HOME_DIR"
