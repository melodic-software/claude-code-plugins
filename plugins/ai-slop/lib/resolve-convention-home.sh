#!/usr/bin/env bash
# GENERATED from lib/resolve-convention-home.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
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
# as its owner. The behavior follows docs/adr/0075 (fixes 1, 2, 4, 5, 6, 13).
#
# GRAMMAR. The root instruction file carries a region delimited by two marker
# lines (surrounding whitespace, a leading UTF-8 BOM, and a trailing carriage
# return are ignored; nothing else may share the line):
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
# parse. A line inside the region that is exactly `declined` (surrounding
# whitespace ignored) records that the repository declined a home: the caller
# must not ask again. A `declined` line beside a pointer line is a FAIL.
#
# WHICH FILE. `AGENTS.md` is canonical; `CLAUDE.md` is consulted when AGENTS.md
# carries no region. A CLAUDE.md whose only non-blank content is `@AGENTS.md` is
# a pure import shim and is never consulted. The two files are compared
# physically (realpath): when one is a symlink to the other they are one file,
# read once, and nothing is reported. When two distinct files both carry a
# region, AGENTS.md supplies the printed value and CLAUDE.md's copy is reported
# on stderr as `duplicate:` — the doctrine calls that a finding with a
# remediation (remove the copy), not a hard stop, so the exit stays 0.
#
# WHERE A HOME CAN APPLY. The root is classified first. It is "not applicable"
# (exit 5) when it is $HOME, an ancestor of $HOME, or not inside a git work
# tree: a home directory or a loose folder is not a repository that binds a
# home. With no --root the root is the git toplevel of CLAUDE_PROJECT_DIR (else
# of the current directory), one home per git root: CLAUDE_PROJECT_DIR only says
# where to look, so a subdirectory of a repository never reads a file of its own.
#
# WHAT IS READ. By default the working tree. `--ref <ref>` reads AGENTS.md,
# CLAUDE.md and the home directory as committed at <ref>, so a lane resolves the
# pointer at the base commit: a 40-hex commit id or `origin/<name>`, validated
# before any git call and passed to git after --end-of-options. A file that is a
# symlink at <ref> is not read. `-` reads the region from stdin as the text of
# AGENTS.md instead (a remote reader passes text it fetched itself); it names no
# tree, so the root is not classified and the home directory is not checked.
#
# UNTRUSTED INPUT. The root file is consumer prose. Nothing read from it is
# evaluated, expanded, or interpolated into a command: a candidate token is only
# ever compared against the grammar and joined onto --root for a `-d` test.
# Every line is stripped of `\r` and truncated to MAX_LINE bytes before parsing.
#
# Usage:
#   resolve-convention-home.sh [--root <repo>] [--ref <ref>] [--explain] [--help] [-]
#
#   --root <repo>  the repository root (default: the git toplevel of
#                  ${CLAUDE_PROJECT_DIR}, else of the current directory)
#   --ref <ref>    read the committed files at <ref> (40-hex id or origin/<name>)
#   -              read the AGENTS.md text from stdin (not with --root or --ref)
#   --explain      write which file, region, and token were used to stderr
#
# Exit:
#   0  exactly one usable pointer resolved and the directory exists; the
#      repo-relative home is printed on stdout (a `duplicate:` warning on
#      stderr does not change this)
#   1  no region, or a region with no pointer line, in any consulted root file
#      — the caller asks the operator; nothing is inferred here
#   2  usage error, an unusable --root, or an invalid or unresolvable --ref
#   3  FAIL, each with a distinct stderr message: two pointer lines in one
#      region; an unterminated or nested region; an invalid pointer path; a
#      pointer whose target directory is missing; `declined` beside a pointer
#   4  a region holds a `declined` line: the repository declined a home, so the
#      caller uses the bundled defaults and does not ask again
#   5  not applicable: the root is $HOME, an ancestor of it, or not a git work
#      tree; no home applies and nothing is asked
#
# A pointer with no concern file under the home is not an error here: the home
# resolves, and the cascade reports the missing file's layer as absent so the
# bundled default applies (config-cascade.mjs).
#
# Shared source: lib/resolve-convention-home.sh at the marketplace repo root is the canonical source; the copies in the plugins
# that carry it are generated by scripts/sync-shared-copies.sh and registered in
# scripts/shared-copies.txt. Bash 3.2-compatible on purpose: no associative
# arrays, no mapfile, no jq.

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
  resolve-convention-home.sh [--root <repo>] [--ref <ref>] [--explain] [--help] [-]

  --root <repo>  repository root (default: git toplevel of CLAUDE_PROJECT_DIR, else cwd)
  --ref <ref>    read the files as committed at <ref> (40-hex id or origin/<name>)
  -              read the AGENTS.md text from stdin (not with --root or --ref)
  --explain      write the file, region, and token used to stderr

Exit: 0 resolved (home on stdout); 1 no pointer anywhere (ask); 2 usage;
      3 FAIL — two pointers in one region, unterminated region, invalid path,
      target directory missing, or `declined` beside a pointer;
      4 declined (a `declined` line in the region; do not ask again);
      5 not applicable (root is $HOME, an ancestor of it, or not a git work tree).
EOF
}

ROOT_ARG=""
HAS_ROOT=0
REF=""
HAS_REF=0
STDIN_MODE=0
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
    HAS_ROOT=1
    shift 2
    ;;
  --ref)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --ref needs a commit id or origin/<name>" >&2
      exit 2
    fi
    HAS_REF=1
    REF="$2"
    shift 2
    ;;
  -)
    STDIN_MODE=1
    shift
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

if [[ $STDIN_MODE -eq 1 && ( $HAS_ROOT -eq 1 || $HAS_REF -eq 1 ) ]]; then
  echo "ERROR: - (stdin) names no tree; it cannot be combined with --root or --ref" >&2
  exit 2
fi
if [[ $HAS_REF -eq 1 ]]; then
  # Only a full commit id or origin/<name> passes; nothing that git could read
  # as an option, a revision range or a path.
  if ! [[ "$REF" =~ ^[0-9a-f]{40}$ || ("$REF" =~ ^origin/[A-Za-z0-9._/-]+$ && "$REF" != *..* && "$REF" != origin/-*) ]]; then
    echo "ERROR: invalid --ref; expected a 40-hex commit id or origin/<name>" >&2
    exit 2
  fi
fi

explain() { [[ $EXPLAIN -eq 1 ]] && echo "$*" >&2; return 0; }

SCRATCH=""
cleanup() { [[ -z "$SCRATCH" ]] || rm -rf "$SCRATCH"; }
trap cleanup EXIT

ROOT=""
if [[ $STDIN_MODE -eq 0 ]]; then
  if [[ $HAS_ROOT -eq 1 ]]; then
    ROOT="$ROOT_ARG"
  else
    START="${CLAUDE_PROJECT_DIR:-$PWD}"
    # tr -d '\r': Git on Windows can return a CRLF-terminated path.
    ROOT="$(git -C "$START" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
    [[ -n "$ROOT" ]] || ROOT="$START"
  fi
  if [[ ! -d "$ROOT" ]]; then
    echo "ERROR: --root is not a directory: $ROOT" >&2
    exit 2
  fi
fi

# phys <path>: the physical path of an existing file or directory, symlinks
# resolved (realpath, else a readlink walk for macOS before 13).
phys() {
  local p="$1" dir n=0 target
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$p" 2>/dev/null && return 0
  fi
  while [[ -L "$p" && $n -lt 40 ]]; do
    target="$(readlink "$p")" || return 1
    case "$target" in
    /*) p="$target" ;;
    *) p="$(dirname "$p")/$target" ;;
    esac
    n=$((n + 1))
  done
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
  else
    dir="$(cd "$(dirname "$p")" && pwd -P)" || return 1
    printf '%s/%s\n' "$dir" "$(basename "$p")"
  fi
}

# classify_root: exit 5 when no home can apply to $ROOT.
classify_root() {
  local root_p home_p why=""
  root_p="$(CDPATH='' cd -- "$ROOT" && pwd -P)" || return 0
  if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
    home_p="$(CDPATH='' cd -- "$HOME" && pwd -P)"
    if [[ "$root_p" == "$home_p" ]]; then
      why="the root is \$HOME"
    elif [[ "$root_p" == "/" || "$home_p/" == "$root_p/"* ]]; then
      why="the root is an ancestor of \$HOME"
    fi
  fi
  if [[ -z "$why" ]] && ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    why="the root is not inside a git work tree"
  fi
  if [[ -n "$why" ]]; then
    echo "not applicable: $why ($root_p); no convention home applies" >&2
    exit 5
  fi
}

trim() {
  local s="$1"
  # UTF-8 BOM is U+FEFF encoded EF BB BF at the start of the file, so on
  # line 1 it is the first three bytes of this string. POSIX [:space:] /
  # isspace(3) is space, FF, NL, CR, HT, VT, not BOM.
  # https://www.unicode.org/faq/utf_bom.html
  s="${s#$'\xEF\xBB\xBF'}"
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
#   declined  a `declined` line and no pointer line
#   mixed     a `declined` line beside a pointer line
#   unterminated / nested   a BEGIN with no END, or a BEGIN inside a region
scan_file() {
  local file="$1" line in_region=0 regions=0 pointers=0 declined=0 rest
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
    declined)
      [[ $in_region -eq 1 ]] && declined=1
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
  elif [[ $declined -eq 1 && $pointers -gt 0 ]]; then
    SCAN_STATE="mixed"
  elif [[ $declined -eq 1 ]]; then
    SCAN_STATE="declined"
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

# committed_file <name> <dest>: copy <name> as committed at $REF into <dest>.
# Returns 1 when it is absent or not a regular file at $REF (a symlink is not read).
committed_file() {
  local entry mode
  entry="$(git -C "$ROOT" ls-tree "$REF" -- "$1" 2>/dev/null)" || return 1
  mode="${entry%% *}"
  # ./ keeps the path relative to $ROOT, as ls-tree reads it, when $ROOT is below the toplevel.
  case "$mode" in
  100644 | 100755) git -C "$ROOT" show --end-of-options "$REF:./$1" >"$2" 2>/dev/null ;;
  *) return 1 ;;
  esac
}

# TOKEN here is the parser sense: the pointer line scan_file lifts out of a
# convention-home region, never a credential. gitleaks' generic-api-key rule
# keys on the identifier and then takes the next line it can reach as the
# value, so it reports CLAUDE_SHIM=0 as the secret. Annotated rather than
# renamed, because the name is right for what the variable holds.
AGENTS_STATE="none"; AGENTS_TOKEN=""
CLAUDE_STATE="none"; CLAUDE_TOKEN="" # gitleaks:allow
CLAUDE_SHIM=0 # gitleaks:allow
CLAUDE_SAME=0 # gitleaks:allow
AGENTS_FILE=""
CLAUDE_FILE="" # gitleaks:allow

if [[ $STDIN_MODE -eq 1 ]]; then
  SCRATCH="$(mktemp -d)" || exit 2
  cat >"$SCRATCH/AGENTS.md"
  AGENTS_FILE="$SCRATCH/AGENTS.md"
else
  classify_root
  if [[ $HAS_REF -eq 1 ]]; then
    if ! git -C "$ROOT" rev-parse --verify --quiet --end-of-options "$REF^{commit}" >/dev/null; then
      echo "ERROR: --ref does not resolve to a commit: $REF" >&2
      exit 2
    fi
    SCRATCH="$(mktemp -d)" || exit 2
    committed_file AGENTS.md "$SCRATCH/AGENTS.md" && AGENTS_FILE="$SCRATCH/AGENTS.md"
    committed_file CLAUDE.md "$SCRATCH/CLAUDE.md" && CLAUDE_FILE="$SCRATCH/CLAUDE.md"
  else
    [[ -f "$ROOT/AGENTS.md" ]] && AGENTS_FILE="$ROOT/AGENTS.md"
    [[ -f "$ROOT/CLAUDE.md" ]] && CLAUDE_FILE="$ROOT/CLAUDE.md"
    if [[ -n "$AGENTS_FILE" && -n "$CLAUDE_FILE" && "$(phys "$AGENTS_FILE")" == "$(phys "$CLAUDE_FILE")" ]]; then
      CLAUDE_SAME=1
      CLAUDE_FILE=""
    fi
  fi
fi

if [[ -n "$AGENTS_FILE" ]]; then
  scan_file "$AGENTS_FILE"
  AGENTS_STATE="$SCAN_STATE"; AGENTS_TOKEN="$SCAN_TOKEN"
fi
if [[ -n "$CLAUDE_FILE" ]]; then
  if is_pure_shim "$CLAUDE_FILE"; then
    CLAUDE_SHIM=1
  else
    scan_file "$CLAUDE_FILE"
    CLAUDE_STATE="$SCAN_STATE"; CLAUDE_TOKEN="$SCAN_TOKEN"
  fi
fi

if [[ $STDIN_MODE -eq 1 ]]; then
  explain "source:    stdin"
elif [[ $HAS_REF -eq 1 ]]; then
  explain "root:      $ROOT at $REF"
else
  explain "root:      $ROOT"
fi
explain "AGENTS.md: $AGENTS_STATE"
if [[ $CLAUDE_SAME -eq 1 ]]; then
  explain "CLAUDE.md: the same file as AGENTS.md (not read twice)"
elif [[ $CLAUDE_SHIM -eq 1 ]]; then
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
[[ $STDIN_MODE -eq 1 ]] && CHOSEN="stdin"
explain "chosen:    $CHOSEN ($STATE)"

case "$STATE" in
none)
  echo "no convention-home region in AGENTS.md or CLAUDE.md under ${ROOT:-stdin}; ask the operator for the home" >&2
  exit 1
  ;;
empty)
  echo "convention-home region in $CHOSEN has no pointer line; ask the operator for the home" >&2
  exit 1
  ;;
declined)
  echo "declined: convention-home region in $CHOSEN records that this repository declined a home; use the bundled defaults and do not ask again" >&2
  exit 4
  ;;
mixed)
  echo "FAIL: convention-home region in $CHOSEN holds both a declined line and a pointer line; keep one" >&2
  exit 3
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

if [[ $STDIN_MODE -eq 1 ]]; then
  : # no tree to check the directory against
elif [[ $HAS_REF -eq 1 ]]; then
  if [[ "$(git -C "$ROOT" cat-file -t "$REF:./$HOME_DIR" 2>/dev/null)" != "tree" ]]; then
    echo "FAIL: pointer target directory missing: $HOME_DIR (named in $CHOSEN, not found at $REF)" >&2
    exit 3
  fi
elif [[ ! -d "$ROOT/$HOME_DIR" ]]; then
  echo "FAIL: pointer target directory missing: $HOME_DIR (named in $CHOSEN, not found under $ROOT)" >&2
  exit 3
fi

printf '%s\n' "$HOME_DIR"
