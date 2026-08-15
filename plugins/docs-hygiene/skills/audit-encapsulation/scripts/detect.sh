#!/usr/bin/env bash
# Find external citations into private skill internals (.claude/skills/<X>/...,
# plugins/<plugin>/skills/<X>/... in marketplace monorepos, and relative forms
# `skills/<X>/...` / `../`-resolved sibling cites — #2716).
#
# Contract this detector encodes: ../context/public-surface-contract.md
# (bundled with this skill).
# Scan root: the git repository the script runs in (the consumer repo), or the
# current directory when outside a git repo.
# Output TSV: file, line, match-text. Use --apply-filters to drop known
# mechanically-decidable legal hits (self-citation, worktree paths).
#
# This script is a candidate enumerator, not a violation adjudicator. Exit 1
# means candidates exist after mechanical filters — not that those hits are
# illegal. Classify via the skill's filter taxonomy before treating any hit as
# a violation. Do not hard-gate CI on this exit code alone.
# Exit: 0 no candidates, 1 candidates exist, 2 environment error.
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
Usage: audit-encapsulation detect [--include-skills] [--apply-filters]

Enumerate candidate citations into private skill internals.
Output TSV: file, line, match-text.
Exit: 0 no candidates, 1 candidates exist, 2 environment error.

Exit 1 means candidates remain after mechanical filters — not adjudicated
violations. Classify via the skill filter taxonomy before gating. Do not
hard-gate CI on this exit code alone.

Matched path prefixes: .claude/skills/<X>/..., plugins/<plugin>/skills/<X>/...,
and relative forms (skills/<X>/... plugin-README short cites, plus ../-prefixed
cites whose lexical resolution lands on a private skill surface).

  --include-skills  Include .claude/skills/ in scope (intra-skill self-citation review)
  --apply-filters   Drop self-citation and worktree path hits (mechanical filters only)
USAGE
    exit 0
    ;;
  *)
    echo "audit-encapsulation/detect: unknown arg '$arg'" >&2
    exit 2
    ;;
  esac
done

# In-scope authoring surfaces, generalized for any consumer repo and filtered
# to what exists (absent surfaces are skipped silently):
#   - every .claude/ child directory EXCEPT skills/ (intra-skill self-citation
#     is legal; opt back in via --include-skills) and worktrees/ (worktrees
#     share the tracked tree; the same rules apply at the root path)
#   - .github/ (workflows), docs/, .lefthook/ (git-hook scripts), plugins/
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
for d in .github docs .lefthook plugins; do
  [[ -d "$d" ]] && SCOPE_DIRS+=("$d")
done

SCOPE_FILES=()
for f in AGENTS.md CLAUDE.md README.md CONTRIBUTING.md lefthook.yml \
  .claude/*.md .claude/*.json .claude/*.yml .claude/*.yaml; do
  [[ -f "$f" ]] && SCOPE_FILES+=("$f")
done

if [[ ${#SCOPE_DIRS[@]} -eq 0 && ${#SCOPE_FILES[@]} -eq 0 ]]; then
  echo "audit-encapsulation: no in-scope dirs or files present" >&2
  exit 2
fi

# Private-surface pattern per ../context/public-surface-contract.md: any
# subdir under a skill root is private; *.schema.json at any depth is
# private; <skill>/SKILL.md#<anchor> heading-anchor cites are private.
# Alternations (ERE form via grep -E):
#   1. `<skill>/<subdir>/`          — any subdirectory name (contract: all
#      subdirs regardless of name; excludes bare SKILL.md by requiring `/`)
#   2. `<skill>/SKILL.md#<anchor>`  — heading-anchor cites
#   3. `<skill>/<file>.schema.json` — schema files at any depth
# Skill and subdir segments are `[A-Za-z0-9_.-]+` so uppercase, single-char,
# digit-leading, and underscore-leading names match, while whitespace and prose
# punctuation between roots cannot span a false multi-root match. Bare
# `<skill>/SKILL.md` path cites still pass (discouraged-but-legal) because they
# lack `#` and a trailing subdir slash. Does NOT match plain-JSON data files at
# skill root (`<skill>/catalog.json`) per the data-file carve-out.
# Skill-root layouts the detector matches (absolute + relative, #2716):
#   - consumer-installed: `.claude/skills/<skill>/...`
#   - marketplace monorepo: `plugins/<plugin>/skills/<skill>/...`
#   - plugin-relative / short: `skills/<skill>/...` (README links, and the
#     `skills/` suffix of `../`-prefixed paths that still name a skills root)
# Absolute alternations are listed first so grep -o prefers the longer
# leftmost match over the bare `skills/` suffix of the same path.
PATTERN='\.claude/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|\.claude/skills/[A-Za-z0-9_.-]+/SKILL\.md#|\.claude/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/SKILL\.md#|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json|skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/|skills/[A-Za-z0-9_.-]+/SKILL\.md#|skills/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.schema\.json'

# scripts/ entry-surface carve-out: a skill's `scripts/` is its declared ENTRY
# surface — harness / CI / hooks / workflow registries MAY path-cite it. Like
# the data-file and bare-SKILL.md public surfaces, scripts/ cites are never
# private, so they are dropped here rather than emitted as raw hits. PATTERN
# still matches scripts/ (the subdir alternation; ERE has no lookahead to
# exclude one name), so the carve-out is a post-grep exclusion. The scan grep
# below uses `-o` to emit ONE record per cite, so this carve-out drops only
# the scripts/ cite — a line co-citing a scripts/ entry script AND another
# skill's private subdir keeps the genuine cite instead of dropping the whole
# line. Bare `skills/<x>/scripts/` is included so plugin-relative entry cites
# stay carved out too (#2716). Filter on the matched *citation text* only —
# never on the citing file's path — so a file that itself lives under
# `skills/<x>/scripts/` does not have every citation it makes swallowed.
# The skill-to-skill half of the asymmetry (a sibling SKILL.md citing
# another skill's scripts/ stays slash-only) is out of this inbound audit's
# scope — see the contract file.
SCRIPTS_RE='^(\.claude/skills/[A-Za-z0-9_.-]+/scripts/|plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+/scripts/|skills/[A-Za-z0-9_.-]+/scripts/)'

# Lexically resolve a repo-relative path with `.` / `..` segments. Returns 1 if
# the path escapes the repo root. Used by the `../` relative-cite pass (#2716).
lex_resolve() {
  local raw="$1" seg
  [[ "$raw" == /* ]] && return 1
  local -a out=()
  while IFS= read -r seg; do
    case "$seg" in
    '' | '.') continue ;;
    '..')
      ((${#out[@]})) || return 1
      out=("${out[@]:0:${#out[@]}-1}")
      ;;
    *) out+=("$seg") ;;
    esac
  done < <(printf '%s\n' "${raw//\//$'\n'}")
  local joined="" part
  for part in ${out[@]+"${out[@]}"}; do
    joined="${joined:+$joined/}$part"
  done
  printf '%s' "$joined"
}

# True when a resolved path is a private skill surface (subdir / SKILL.md#
# / *.schema.json), matching the same contract as PATTERN. Trailing slash is
# optional — lex_resolve drops a final empty segment.
is_private_skill_path() {
  local p="$1"
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/scripts(/|$) ]] && return 1
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/|$) ]] && return 0
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/SKILL\.md# ]] && return 0
  [[ "$p" =~ ^(\.claude/skills/|plugins/[^/]+/skills/)[A-Za-z0-9_.-]+/[^/]+\.schema\.json ]] && return 0
  return 1
}

# True when citation text is a scripts/ entry-surface carve-out (text field only).
is_scripts_carveout() {
  local text="$1"
  [[ "$text" =~ $SCRIPTS_RE ]]
}

# When grep -o emitted only a bare `skills/<x>/...` suffix of a `../`-prefixed
# cite, recover the leading `../...` span from the source line so resolution
# can see the real target (cross-plugin same-leaf-name defense).
recover_dotdot_prefix() {
  local file="$1" line_no="$2" text="$3" src before
  src="$(sed -n "${line_no}p" "$file" 2>/dev/null || true)"
  [[ -n "$src" && "$src" == *"$text"* ]] || return 1
  before="${src%%"$text"*}"
  if [[ "$before" =~ ((\.\./)+([A-Za-z0-9_.-]+/)*)$ ]]; then
    printf '%s%s' "${BASH_REMATCH[1]}" "$text"
    return 0
  fi
  return 1
}

HITS_FILE="$(mktemp)"
DOTDOT_RAW="$(mktemp)"
RAW_HITS="$(mktemp)"
trap 'rm -f "$HITS_FILE" "$DOTDOT_RAW" "$RAW_HITS"' EXIT

# Aggregate hits, then drop scripts/ entry-surface cites (carve-out above).
{
  if [[ ${#SCOPE_DIRS[@]} -gt 0 ]]; then
    grep -Erno "$PATTERN" \
      --include='*.md' --include='*.sh' --include='*.json' \
      --include='*.yml' --include='*.yaml' \
      "${SCOPE_DIRS[@]}" 2>/dev/null || true
  fi
  if [[ ${#SCOPE_FILES[@]} -gt 0 ]]; then
    # -H forces the file prefix even when only one file exists.
    grep -EHno "$PATTERN" "${SCOPE_FILES[@]}" 2>/dev/null || true
  fi
} >"$RAW_HITS" || true

: >"$HITS_FILE"
if [[ -s "$RAW_HITS" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    text="${line#*:*:}"
    # shellcheck disable=SC2310  # is_scripts_carveout is a pure predicate; both branches handled
    if is_scripts_carveout "$text"; then
      continue
    fi
    printf '%s\n' "$line" >>"$HITS_FILE"
  done <"$RAW_HITS"
fi

# Second pass (#2716): `../`-prefixed cites whose lexical resolution lands on
# a private skill surface. Covers sibling-skill links like
# `../other-skill/reference/...` that never spell `skills/` in the cite text.
# Candidates already matched by the bare `skills/` alternation (paths that
# still contain a `skills/` segment after `../`) are skipped here to avoid
# duplicate rows.
DOTDOT_PATTERN='(\.\./)+([A-Za-z0-9_.-]+/)+([A-Za-z0-9_.-]+/|SKILL\.md#|[A-Za-z0-9_.-]+\.schema\.json)'
{
  if [[ ${#SCOPE_DIRS[@]} -gt 0 ]]; then
    grep -Erno "$DOTDOT_PATTERN" \
      --include='*.md' --include='*.sh' --include='*.json' \
      --include='*.yml' --include='*.yaml' \
      "${SCOPE_DIRS[@]}" 2>/dev/null || true
  fi
  if [[ ${#SCOPE_FILES[@]} -gt 0 ]]; then
    grep -EHno "$DOTDOT_PATTERN" "${SCOPE_FILES[@]}" 2>/dev/null || true
  fi
} >"$DOTDOT_RAW" || true

if [[ -s "$DOTDOT_RAW" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    line_no="${rest%%:*}"
    text="${rest#*:}"
    # Already covered by the skills/-segment alternation.
    [[ "$text" == *"/skills/"* || "$text" == skills/* ]] && continue
    rel="$text"
    # shellcheck disable=SC2310  # lex_resolve returns status; continue is the handled miss
    resolved="$(lex_resolve "$(dirname "$file")/$rel")" || continue
    # shellcheck disable=SC2310  # is_private_skill_path is a pure predicate; both branches handled
    is_private_skill_path "$resolved" || continue
    printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
  done <"$DOTDOT_RAW"
fi

if [[ ! -s "$HITS_FILE" ]]; then
  if [[ "$APPLY_FILTERS" -eq 1 ]]; then
    printf 'Summary: raw=0 mech-filtered=0 candidates=0\n' >&2
  fi
  exit 0
fi

# Convert grep "file:line:match" → "file<TAB>line<TAB>match". The `-o` scan
# emits only the matched path text, which contains no colons, so colon
# splitting is unambiguous. Under --apply-filters, drop the known
# mechanically-decidable legal hit shapes: self-citation (a skill citing its
# own internals — absolute, bare skills/<self>/, or ../-resolved into the same
# skill root) and worktree paths (shared tree; same rules apply at the root
# path). Plugin-cache cites that only match via the bare `skills/` suffix are
# still candidates for in-session Plugin-cache taxonomy judgment (#2776); the
# mechanical cache branch stays absent.
raw=0
candidates=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  raw=$((raw + 1))
  file="${line%%:*}"
  rest="${line#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
  if [[ "$APPLY_FILTERS" -eq 1 ]]; then
    mech_filtered=0
    if [[ "$file" =~ ^\.claude/skills/([^/]+)/ ]]; then
      self="${BASH_REMATCH[1]}"
      if [[ "$text" == *".claude/skills/${self}/"* ]]; then
        mech_filtered=1
      elif [[ "$text" == "skills/${self}/"* ]]; then
        # Bare skills/<self>/ may be the suffix of a ../-prefixed cross-root
        # cite; only treat as self-citation when there is no ../ prefix or
        # resolution lands back in this skill.
        full=""
        # shellcheck disable=SC2310  # recover miss → bare plugin-relative cite
        full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || full=""
        if [[ -z "$full" ]]; then
          mech_filtered=1
        else
          # shellcheck disable=SC2310  # lex_resolve miss → leave as candidate
          resolved="$(lex_resolve "$(dirname "$file")/$full")" || resolved=""
          if [[ -n "$resolved" && "$resolved" == ".claude/skills/${self}/"* ]]; then
            mech_filtered=1
          fi
        fi
      elif [[ "$text" == ../* ]]; then
        # shellcheck disable=SC2310  # lex_resolve miss → empty; not a filter hit
        resolved="$(lex_resolve "$(dirname "$file")/$text")" || resolved=""
        if [[ -n "$resolved" && "$resolved" == ".claude/skills/${self}/"* ]]; then
          mech_filtered=1
        fi
      fi
    elif [[ "$file" =~ ^(plugins/[^/]+)/skills/([^/]+)/ ]]; then
      plugin="${BASH_REMATCH[1]}"
      self="${BASH_REMATCH[2]}"
      # Require same plugin root for absolute self-cites so a cross-plugin
      # `.../other/skills/<same-name>/...` match cannot vacate as self-citation
      # merely by skill leaf name (#2716 review).
      if [[ "$text" == "${plugin}/skills/${self}/"* ||
        "$text" == *"/${plugin}/skills/${self}/"* ]]; then
        mech_filtered=1
      elif [[ "$text" == "skills/${self}/"* ]]; then
        full=""
        # shellcheck disable=SC2310  # recover miss → bare same-plugin short cite
        full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || full=""
        if [[ -z "$full" ]]; then
          mech_filtered=1
        else
          # shellcheck disable=SC2310  # lex_resolve miss → leave as candidate
          resolved="$(lex_resolve "$(dirname "$file")/$full")" || resolved=""
          if [[ -n "$resolved" && "$resolved" == "${plugin}/skills/${self}/"* ]]; then
            mech_filtered=1
          fi
        fi
      elif [[ "$text" == ../* ]]; then
        # shellcheck disable=SC2310  # lex_resolve miss → empty; not a filter hit
        resolved="$(lex_resolve "$(dirname "$file")/$text")" || resolved=""
        if [[ -n "$resolved" && "$resolved" == "${plugin}/skills/${self}/"* ]]; then
          mech_filtered=1
        fi
      fi
    elif [[ "$file" == *".worktrees/"* || "$text" == *".worktrees/"* ]]; then
      mech_filtered=1
    elif [[ "$file" == *".claude/worktrees/"* || "$text" == *".claude/worktrees/"* ]]; then
      mech_filtered=1
    elif [[ "$file" == *".git/worktrees/"* || "$text" == *".git/worktrees/"* ]]; then
      mech_filtered=1
    fi
    if [[ "$mech_filtered" -eq 1 ]]; then
      continue
    fi
  fi
  candidates=$((candidates + 1))
  printf '%s\t%s\t%s\n' "$file" "$line_no" "$text"
done <"$HITS_FILE"

if [[ "$APPLY_FILTERS" -eq 1 ]]; then
  mech_filtered=$((raw - candidates))
  printf 'Summary: raw=%s mech-filtered=%s candidates=%s\n' \
    "$raw" "$mech_filtered" "$candidates" >&2
fi

if [[ "$candidates" -eq 0 ]]; then
  exit 0
fi
exit 1
