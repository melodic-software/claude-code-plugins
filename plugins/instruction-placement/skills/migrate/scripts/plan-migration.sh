#!/usr/bin/env bash
# plan-migration.sh — what a repository's move to AGENTS.md would touch.
#
# Read-only. `--dry-run` is the only mode there is, and it is the default: this
# script never writes, moves or deletes a file, so the flag exists to say so at
# the call site rather than to select a behavior. The skill body owns every
# judgment (what content is always-relevant, what becomes a pointer, what
# becomes a path-scoped rule); this script owns only what a machine can decide.
#
# Emits tagged TSV to stdout, one row kind per concern:
#
#   DIR       <path>  <state>  <claude-bytes>  <agents-bytes>
#             One state per directory that carries a Claude-audience instruction
#             file: content-in-claude, shim, agents-only, both-with-content, or
#             zero-byte.
#   BUDGET    <dir>  <cumulative-bytes>  <OK|OVER>
#             AGENTS.md bytes summed along the root-to-directory path, against
#             Codex's 32,768-byte project-doc budget. The path sum is the
#             stricter of the two readings of that budget for a deep tree.
#   CASE      <path>
#             A file whose name differs from CLAUDE.md / AGENTS.md only by case.
#             Claude Code matches the name exactly; NTFS does not, so a repo can
#             carry one and behave differently per developer.
#   SUPPRESS  <path>  <exists>
#             A bare ~/CLAUDE.md or ~/CLAUDE.local.md. Either is read instead of
#             AGENTS.md in every directory below home, whatever a repository does.
#   PATHDET   <file>:<line>  <text>
#             Code or script that locates a path by the existence of CLAUDE.md.
#             Each one breaks when the shim comes out.
#   CITE      <file>:<line>  <text>
#             A heading or path citation that resolves into CLAUDE.md.
#   DOCSHOME  <dir>  <found|absent>
#             The repository's existing documentation home, where a pointer
#             target lands. Detected, never imposed: the first tracked directory
#             of `docs`, `doc`, `documentation`, `Documentation`. `absent` means
#             the repository has none and the skill creates `docs/`.
#   ACTION    <workflow>:<line>  <pin>
#             Every claude-code-action pin under .github/workflows/. Each pin
#             decides which CLI version CI runs, and so whether CI reads
#             AGENTS.md at all.
#
# Directory states:
#   content-in-claude   CLAUDE.md carries content; AGENTS.md is absent or empty
#   shim                CLAUDE.md is nothing but @AGENTS.md, beside a non-empty
#                       AGENTS.md: the target shape while shims are needed
#   agents-only         a non-empty AGENTS.md with no CLAUDE.md beside it
#   both-with-content   both carry content; the split has to be decided
#   zero-byte           every instruction file here is empty
#
# Discovery is tracked files only (git ls-files), minus the excluded trees this
# plugin defines once as `IP_EXCLUDED_TREES` in `lib/discover.sh`: another
# tool's instruction files are that tool's, and must never be given a Claude
# shim.
#
# Usage:
#   plan-migration.sh [--dry-run] [--root <dir>] [--home <dir>]
#   plan-migration.sh --help
#
# Exit: 0 the plan printed; 1 not a git repository; 2 usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The excluded-tree list is this plugin's, defined once in lib/discover.sh so
# the plan, the index and the wiring gate cannot disagree about whose files a
# directory holds.
# shellcheck source=../../../scripts/lib/discover.sh
source "$SCRIPT_DIR/../../../scripts/lib/discover.sh"

CODEX_PROJECT_DOC_BUDGET=32768

ROOT="."
HOME_DIR="${HOME:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    cat <<'EOF'
plan-migration.sh — what a repository's move to AGENTS.md would touch.

Usage: plan-migration.sh [--dry-run] [--root <dir>] [--home <dir>] [--help]

  --dry-run     the only mode; read-only, and the default
  --root <dir>  the repository to plan (default: the current directory)
  --home <dir>  where to look for the bare ~/CLAUDE.md suppressors (default: $HOME)
  --help        this message

Row kinds: DIR, BUDGET, CASE, SUPPRESS, PATHDET, CITE, ACTION. Every row is a
fact about the repository; the content split is judgment and stays in the skill.

Exit: 0 printed, 1 not a git repository, 2 usage error.
EOF
    exit 0
    ;;
  --dry-run) shift ;;
  --root)
    [[ $# -ge 2 ]] || {
      echo "plan-migration: --root needs a directory" >&2
      exit 2
    }
    ROOT="$2"
    shift 2
    ;;
  --home)
    [[ $# -ge 2 ]] || {
      echo "plan-migration: --home needs a directory" >&2
      exit 2
    }
    HOME_DIR="$2"
    shift 2
    ;;
  *)
    echo "plan-migration: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

cd "$ROOT" 2>/dev/null || {
  echo "plan-migration: cannot enter $ROOT" >&2
  exit 2
}

git rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "plan-migration: not inside a git repository" >&2
  exit 1
}

file_bytes() {
  [[ -f "$1" ]] || {
    printf '0\n'
    return 0
  }
  wc -c <"$1" | tr -d ' \t\r'
}

# A pure shim is a file whose every non-blank, non-comment line is an @import of
# the AGENTS.md beside it. An HTML comment above the import still makes it a
# shim for loading purposes; the target shape drops the comment, which the skill
# body handles as content, not as a state.
is_pure_shim() {
  local file="$1" seen=0 line trimmed
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line%$'\r'}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    [[ "$trimmed" == "<!--"*"-->" ]] && continue
    case "$trimmed" in
    "@AGENTS.md" | "@./AGENTS.md") seen=1 ;;
    *) return 1 ;;
    esac
  done <"$file"
  [[ "$seen" -eq 1 ]]
}

# Every directory carrying a tracked CLAUDE.md or AGENTS.md, excluded trees
# dropped. One awk pass, not one subshell per tracked file: Git Bash pays about
# 140 ms a spawn, and a repository of a few thousand files turns a per-file
# `basename` into minutes of wall clock.
instruction_dirs() {
  git ls-files -z 2>/dev/null | tr '\0' '\n' | awk -v excluded="$IP_EXCLUDED_TREES" '
    BEGIN { split(excluded, ex, " "); for (k in ex) skip[ex[k]] = 1 }
    $0 == "" { next }
    {
      n = split($0, seg, "/")
      if (seg[n] != "CLAUDE.md" && seg[n] != "AGENTS.md") next
      for (i = 1; i < n; i++) if (seg[i] in skip) next
      if (n == 1) { print "."; next }
      dir = seg[1]
      for (i = 2; i < n; i++) dir = dir "/" seg[i]
      print dir
    }
  ' | LC_ALL=C sort -u
}

# --- DIR and BUDGET -------------------------------------------------------
while IFS= read -r dir; do
  [[ -n "$dir" ]] || continue
  claude="$dir/CLAUDE.md"
  agents="$dir/AGENTS.md"
  [[ "$dir" == "." ]] && claude="CLAUDE.md" && agents="AGENTS.md"
  cb="$(file_bytes "$claude")"
  ab="$(file_bytes "$agents")"

  if [[ "$cb" -eq 0 && "$ab" -eq 0 ]]; then
    state="zero-byte"
  elif [[ "$cb" -eq 0 ]]; then
    state="agents-only"
  elif [[ "$ab" -eq 0 ]]; then
    state="content-in-claude"
  elif is_pure_shim "$claude"; then
    state="shim"
  else
    state="both-with-content"
  fi
  printf 'DIR\t%s\t%s\t%s\t%s\n' "$dir" "$state" "$cb" "$ab"

  # Cumulative AGENTS.md bytes along the root-to-this-directory path, which is
  # what a session working in this directory would carry.
  cum=0
  walk="$dir"
  chain=("$walk")
  while [[ "$walk" != "." && "$walk" != "/" ]]; do
    walk="$(dirname -- "$walk")"
    chain+=("$walk")
  done
  for step in "${chain[@]}"; do
    if [[ "$step" == "." ]]; then
      cum=$((cum + $(file_bytes "AGENTS.md")))
    else
      cum=$((cum + $(file_bytes "$step/AGENTS.md")))
    fi
  done
  verdict="OK"
  [[ "$cum" -gt "$CODEX_PROJECT_DOC_BUDGET" ]] && verdict="OVER"
  printf 'BUDGET\t%s\t%s\t%s\n' "$dir" "$cum" "$verdict"
done < <(instruction_dirs)

# --- CASE -----------------------------------------------------------------
# Claude Code matches the names exactly; a case-folding filesystem does not, so
# a variant behaves differently per developer and is a migration hazard.
git ls-files -z 2>/dev/null | tr '\0' '\n' | awk '
  $0 == "" { next }
  {
    n = split($0, seg, "/")
    base = seg[n]
    if (base == "CLAUDE.md" || base == "AGENTS.md" || base == "CLAUDE.local.md") next
    lower = tolower(base)
    if (lower == "claude.md" || lower == "agents.md" || lower == "claude.local.md")
      printf "CASE\t%s\n", $0
  }
'

# --- SUPPRESS -------------------------------------------------------------
# A bare ~/CLAUDE.md or ~/CLAUDE.local.md is read instead of AGENTS.md in every
# directory below home, so no repository-side change can make AGENTS.md load
# there. Measured 2026-09-19 on Claude Code 2.1.278; recheck when
# code.claude.com/docs/en/memory changes which names count for that check.
if [[ -n "$HOME_DIR" ]]; then
  for suppressor in "$HOME_DIR/CLAUDE.md" "$HOME_DIR/CLAUDE.local.md"; do
    if [[ -f "$suppressor" ]]; then
      printf 'SUPPRESS\t%s\tyes\n' "$suppressor"
    else
      printf 'SUPPRESS\t%s\tno\n' "$suppressor"
    fi
  done
fi

# --- PATHDET --------------------------------------------------------------
# Code that finds a directory by the existence of CLAUDE.md. Each one keeps
# working while the shim exists and breaks the day it comes out, which is why
# this is a plan row rather than a cutover surprise.
git grep -n -I -E '(File\.Exists|isFile|-f |test -f|os\.path\.exists|fs\.existsSync|Files\.exists)[^;]{0,40}CLAUDE\.md' \
  -- ':!*.md' ':!.claude/*' 2>/dev/null |
  grep -vE ':[0-9]+:[[:space:]]*(#|//|\*)' |
  while IFS= read -r hit; do
    printf 'PATHDET\t%s\n' "$hit"
  done

# --- CITE -----------------------------------------------------------------
# Citations that RESOLVE into CLAUDE.md: a markdown link target, with or without
# a heading anchor. Each one has to be retargeted when the content moves. Prose
# that merely names the file is not a citation and is deliberately not matched:
# a row a reader has to dismiss is a row they stop reading.
git grep -n -I -E '\]\([^)]*CLAUDE\.md(#[A-Za-z0-9_-]+)?\)' -- '*.md' 2>/dev/null |
  while IFS= read -r hit; do
    printf 'CITE\t%s\n' "$hit"
  done

# --- DOCSHOME -------------------------------------------------------------
# Pointer targets go to the documentation home the repository already keeps.
# Detection only: the skill creates `docs/` solely where there is nothing to
# find, and never relocates an existing home.
docs_home="absent"
for candidate in docs doc documentation Documentation; do
  if [[ -d "$candidate" ]] && git ls-files --error-unmatch "$candidate" >/dev/null 2>&1; then
    docs_home="$candidate"
    break
  fi
done
if [[ "$docs_home" == "absent" ]]; then
  printf 'DOCSHOME\tdocs\tabsent\n'
else
  printf 'DOCSHOME\t%s\tfound\n' "$docs_home"
fi

# --- ACTION ---------------------------------------------------------------
# Every claude-code-action pin. The pin decides the CLI version CI installs,
# and so whether a CI session reads AGENTS.md at all.
if [[ -d ".github/workflows" ]]; then
  grep -rn -E 'claude-code-action@' .github/workflows 2>/dev/null |
    while IFS= read -r hit; do
      printf 'ACTION\t%s\n' "$hit"
    done
fi

exit 0
