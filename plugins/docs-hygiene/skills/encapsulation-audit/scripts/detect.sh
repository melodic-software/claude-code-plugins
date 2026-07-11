#!/usr/bin/env bash
# Find external citations into private skill internals (.claude/skills/<X>/...).
#
# Contract this detector encodes: ../context/public-surface-contract.md
# (bundled with this skill).
# Scan root: the git repository the script runs in (the consumer repo), or the
# current directory when outside a git repo.
# Output TSV: file, line, match-text. Use --apply-filters to drop known legal hits.
# Exit: 0 clean, 1 violations, 2 environment error.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || pwd)"
cd "$REPO_ROOT"

INCLUDE_SKILLS=0
APPLY_FILTERS=0
for arg in "$@"; do
  case "$arg" in
  --include-skills) INCLUDE_SKILLS=1 ;;
  --apply-filters) APPLY_FILTERS=1 ;;
  --help | -h)
    cat <<'USAGE'
Usage: encapsulation-audit detect [--include-skills] [--apply-filters]

Find external citations into private skill internals.
Output TSV: file, line, match-text.
Exit: 0 clean, 1 violations, 2 environment error.

  --include-skills  Include .claude/skills/ in scope (intra-skill self-citation review)
  --apply-filters   Drop self-citation, plugin cache, and worktree path hits
USAGE
    exit 0
    ;;
  *)
    echo "encapsulation-audit/detect: unknown arg '$arg'" >&2
    exit 2
    ;;
  esac
done

# In-scope authoring surfaces, generalized for any consumer repo and filtered
# to what exists (absent surfaces are skipped silently):
#   - every .claude/ child directory EXCEPT skills/ (intra-skill self-citation
#     is legal; opt back in via --include-skills) and worktrees/ (worktrees
#     share the tracked tree; the same rules apply at the root path)
#   - .github/ (workflows), docs/, .lefthook/ (git-hook scripts)
#   - root instruction/config files plus .claude/ top-level files
# CI/hook surfaces stay IN-SCOPE for hit detection; the scripts/ entry-surface
# carve-out and the filter taxonomy decide legality downstream, not exclusion.
SCOPE_DIRS=()
for d in .claude/*/; do
  d="${d%/}"
  [[ -d "$d" ]] || continue
  if [[ "$d" == ".claude/skills" && "$INCLUDE_SKILLS" -eq 0 ]]; then
    continue
  fi
  if [[ "$d" == ".claude/worktrees" ]]; then
    continue
  fi
  SCOPE_DIRS+=("$d")
done
for d in .github docs .lefthook; do
  [[ -d "$d" ]] && SCOPE_DIRS+=("$d")
done

SCOPE_FILES=()
for f in AGENTS.md CLAUDE.md README.md CONTRIBUTING.md lefthook.yml \
  .claude/*.md .claude/*.json .claude/*.yml .claude/*.yaml; do
  [[ -f "$f" ]] && SCOPE_FILES+=("$f")
done

if [[ ${#SCOPE_DIRS[@]} -eq 0 && ${#SCOPE_FILES[@]} -eq 0 ]]; then
  echo "encapsulation-audit: no in-scope dirs or files present" >&2
  exit 2
fi

# Private-surface pattern per ../context/public-surface-contract.md: any
# subdir under a skill root is private; *.schema.json at any depth is
# private; <skill>/SKILL.md#<anchor> heading-anchor cites are private.
# Three alternations (BRE form, escaped): # spellchecker:disable-line
#   1. `<skill>/<subdir>/`          — any kebab-style subdir name
#   2. `<skill>/SKILL.md#<anchor>`  — heading-anchor cites
#   3. `<skill>/<file>.schema.json` — schema files at any depth
# Subdir char class `[a-z][a-z0-9_-]+` matches kebab-style names and
# excludes `SKILL.md` (uppercase) so bare `<skill>/SKILL.md` path cites
# pass (discouraged-but-legal). Does NOT match plain-JSON data files at
# skill root (`<skill>/catalog.json`) per the data-file carve-out.
PATTERN='\.claude/skills/[a-z][a-z0-9-]\+/[a-z][a-z0-9_-]\+/\|\.claude/skills/[a-z][a-z0-9-]\+/SKILL\.md#\|\.claude/skills/[a-z][a-z0-9-]\+/[^/]\+\.schema\.json'

# scripts/ entry-surface carve-out: a skill's `scripts/` is its declared ENTRY
# surface — harness / CI / hooks / workflow registries MAY path-cite it. Like
# the data-file and bare-SKILL.md public surfaces, scripts/ cites are never
# private, so they are dropped here rather than emitted as raw hits. PATTERN
# still matches scripts/ (the subdir alternation; BRE has no lookahead to # spellchecker:disable-line
# exclude one name), so the carve-out is a post-grep exclusion. The scan grep
# below uses `-o` to emit ONE record per cite, so this `grep -vE` drops only
# the scripts/ cite — a line co-citing a scripts/ entry script AND another
# skill's private subdir keeps the genuine cite instead of dropping the whole
# line. The skill-to-skill half of the asymmetry (a sibling SKILL.md citing
# another skill's scripts/ stays slash-only) is out of this inbound audit's
# scope — see the contract file.
SCRIPTS_RE='\.claude/skills/[a-z][a-z0-9-]+/scripts/'

HITS_FILE="$(mktemp)"
trap 'rm -f "$HITS_FILE"' EXIT

# Aggregate hits, then drop scripts/ entry-surface cites (carve-out above).
{
  if [[ ${#SCOPE_DIRS[@]} -gt 0 ]]; then
    grep -rno "$PATTERN" \
      --include='*.md' --include='*.sh' --include='*.json' \
      --include='*.yml' --include='*.yaml' \
      "${SCOPE_DIRS[@]}" 2>/dev/null || true
  fi
  if [[ ${#SCOPE_FILES[@]} -gt 0 ]]; then
    # -H forces the file prefix even when only one file exists.
    grep -Hno "$PATTERN" "${SCOPE_FILES[@]}" 2>/dev/null || true
  fi
} | grep -vE "$SCRIPTS_RE" >"$HITS_FILE" || true

if [[ ! -s "$HITS_FILE" ]]; then
  if [[ "$APPLY_FILTERS" -eq 1 ]]; then
    printf 'Summary: raw=0 legal=0 illegal=0\n' >&2
  fi
  exit 0
fi

# Convert grep "file:line:match" → "file<TAB>line<TAB>match". The `-o` scan
# emits only the matched path text, which contains no colons, so colon
# splitting is unambiguous. Under --apply-filters, drop the known-legal hit
# shapes: self-citation (a skill citing its own internals), plugin cache
# (upstream territory), and worktree paths (shared tree; same rules apply at
# the root path).
raw=0
illegal=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  raw=$((raw + 1))
  file="${line%%:*}"
  rest="${line#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
  if [[ "$APPLY_FILTERS" -eq 1 ]]; then
    legal=0
    if [[ "$file" =~ ^\.claude/skills/([^/]+)/ ]] &&
      [[ "$text" == *".claude/skills/${BASH_REMATCH[1]}/"* ]]; then
      legal=1
    elif [[ "$text" == *"plugins/cache/"* ]]; then
      legal=1
    elif [[ "$file" == *".worktrees/"* || "$text" == *".worktrees/"* ]]; then
      legal=1
    elif [[ "$file" == *".claude/worktrees/"* || "$text" == *".claude/worktrees/"* ]]; then
      legal=1
    elif [[ "$file" == *".git/worktrees/"* || "$text" == *".git/worktrees/"* ]]; then
      legal=1
    fi
    if [[ "$legal" -eq 1 ]]; then
      continue
    fi
  fi
  illegal=$((illegal + 1))
  printf '%s\t%s\t%s\n' "$file" "$line_no" "$text"
done <"$HITS_FILE"

if [[ "$APPLY_FILTERS" -eq 1 ]]; then
  legal=$((raw - illegal))
  printf 'Summary: raw=%s legal=%s illegal=%s\n' "$raw" "$legal" "$illegal" >&2
fi

if [[ "$illegal" -eq 0 ]]; then
  exit 0
fi
exit 1
