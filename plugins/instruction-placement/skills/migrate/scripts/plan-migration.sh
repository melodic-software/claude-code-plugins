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

# Codex's project-doc budget.
#
#   Claim: Codex reads at most 32,768 bytes of project docs per turn, and the
#     cap is CUMULATIVE across the AGENTS.md files it loads, not per file. The
#     key is `project_doc_max_bytes`; its default is 32768.
#   Basis: openai/codex `codex-rs/config/defaults.toml` line 8,
#     `project_doc_max_bytes = 32768`, read at tree
#     df7f717c856e0634b04a12f7d4fc9e8ecb3e65be. The cumulative reading is the
#     same repo's `codex-rs/core/src/agents_md.rs:68`, which seeds
#     `let mut remaining = config.project_doc_max_bytes;` once and then
#     decrements it across the loaded set. The published config reference
#     (learn.chatgpt.com/docs/config-file/config-reference, formerly
#     developers.openai.com/codex/config-reference) documents the key's purpose,
#     "Maximum bytes read from `AGENTS.md` when building project instructions",
#     but publishes no default, which is why the source is the basis here.
#   As of: 2026-09-19.
#   Recheck trigger: that defaults.toml line changes, `agents_md.rs` stops
#     carrying one shared remaining-bytes counter, or the config reference
#     starts publishing a default that differs from it.
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

# Every git command below resolves relative to the directory it runs in, so a
# --root pointing at a subdirectory would describe that subtree as if it were
# the whole repository: a silently partial plan. A migration is a
# repository-wide decision, so climb to the toplevel first.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$REPO_ROOT" ]] || {
  echo "plan-migration: not inside a git repository" >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

file_bytes() {
  [[ -f "$1" ]] || {
    printf '0\n'
    return 0
  }
  wc -c <"$1" | tr -d ' \t\r'
}

# An AGENTS.md under another tool's directory is that tool's file. It is not
# paired with a Claude CLAUDE.md in the same directory, and it is not part of
# what a Codex session carries, so it contributes nothing to either row.
ours_agents_bytes() {
  local dir="$1" seg
  for seg in $IP_FOREIGN_AGENT_TREES; do
    case "/$dir/" in
    */"$seg"/*)
      printf '0\n'
      return 0
      ;;
    esac
  done
  if [[ "$dir" == "." ]]; then file_bytes "AGENTS.md"; else file_bytes "$dir/AGENTS.md"; fi
}

# Classify a CLAUDE.md by how far it is from the target shape, which is a file
# that is EXACTLY `@AGENTS.md`. Prints one of:
#
#   shim               nothing but the import: already the target shape
#   shim-with-comment  the import plus HTML comments and nothing else. It loads
#                      the same way, but the comment is content the migration
#                      still has to move or delete, so it is not `shim` and it
#                      is not `both-with-content` either. Both `dotfiles` and
#                      `medley` are in this state today
#   content            anything else
#
# Comments are matched as blocks, so a note spanning several lines counts once.
classify_claude_md() {
  local file="$1" import=0 comment=0 other=0 inblock=0 line trimmed
  [[ -f "$file" ]] || {
    printf 'content\n'
    return 0
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line%$'\r'}"
    trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [[ -z "$trimmed" ]] && continue
    if ((inblock)); then
      comment=1
      [[ "$trimmed" == *"-->"* ]] && inblock=0
      continue
    fi
    case "$trimmed" in
    "@AGENTS.md" | "@./AGENTS.md") import=1 ;;
    "<!--"*"-->") comment=1 ;;
    "<!--"*)
      comment=1
      inblock=1
      ;;
    *) other=1 ;;
    esac
  done <"$file"
  if ((other)) || ((import == 0)); then
    printf 'content\n'
  elif ((comment)); then
    printf 'shim-with-comment\n'
  else
    printf 'shim\n'
  fi
}

# Every directory carrying a tracked CLAUDE.md or AGENTS.md, excluded trees
# dropped. One awk pass, not one subshell per tracked file: Git Bash pays about
# 140 ms a spawn, and a repository of a few thousand files turns a per-file
# `basename` into minutes of wall clock.
instruction_dirs() {
  git ls-files -z 2>/dev/null | tr '\0' '\n' |
    awk -v excluded="$IP_EXCLUDED_TREES" -v foreign="$IP_FOREIGN_AGENT_TREES" '
    BEGIN {
      split(excluded, ex, " "); for (k in ex) skip[ex[k]] = 1
      split(foreign, fo, " "); for (k in fo) theirs[fo[k]] = 1
    }
    $0 == "" { next }
    {
      n = split($0, seg, "/")
      base = seg[n]
      if (base != "CLAUDE.md" && base != "AGENTS.md") next
      for (i = 1; i < n; i++) {
        if (seg[i] in skip) next
        if (base == "AGENTS.md" && seg[i] in theirs) next
      }
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
  [[ "$dir" == "." ]] && claude="CLAUDE.md"
  cb="$(file_bytes "$claude")"
  ab="$(ours_agents_bytes "$dir")"

  if [[ "$cb" -eq 0 && "$ab" -eq 0 ]]; then
    state="zero-byte"
  elif [[ "$cb" -eq 0 ]]; then
    state="agents-only"
  elif [[ "$ab" -eq 0 ]]; then
    state="content-in-claude"
  else
    case "$(classify_claude_md "$claude")" in
    shim) state="shim" ;;
    shim-with-comment) state="shim-with-comment" ;;
    *) state="both-with-content" ;;
    esac
  fi
  printf 'DIR\t%s\t%s\t%s\t%s\n' "$dir" "$state" "$cb" "$ab"

  # Cumulative AGENTS.md bytes along the root-to-this-directory path, which is
  # what a session working in this directory would carry.
  cum=0
  walk="$dir"
  chain=("$walk")
  while [[ "$walk" != "." && "$walk" != "/" ]]; do
    walk="$(dirname "$walk")"
    chain+=("$walk")
  done
  for step in "${chain[@]}"; do
    cum=$((cum + $(ours_agents_bytes "$step")))
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
