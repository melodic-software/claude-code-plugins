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
ALLOWLIST_FILE="docs/conventions/audit-encapsulation-allowlist.tsv"
while [[ $# -gt 0 ]]; do
  arg="$1"
  shift
  case "$arg" in
  --include-skills) INCLUDE_SKILLS=1 ;;
  --apply-filters) APPLY_FILTERS=1 ;;
  --allowlist)
    if [[ $# -eq 0 ]]; then
      echo "audit-encapsulation/detect: --allowlist needs a file" >&2
      exit 2
    fi
    ALLOWLIST_FILE="$1"
    shift
    ;;
  --help | -h)
    cat <<'USAGE'
Usage: audit-encapsulation detect [--include-skills] [--apply-filters] [--allowlist <file>]

Enumerate candidate citations into private skill internals.
Output TSV: file, line, match-text.
Exit: 0 no candidates, 1 candidates exist, 2 environment error.

Exit 1 means candidates remain after mechanical filters — not adjudicated
violations. Classify via the skill filter taxonomy before gating. Do not
hard-gate CI on this exit code alone.

Matched path prefixes: .claude/skills/<X>/..., plugins/<plugin>/skills/<X>/...,
and relative forms (skills/<X>/... plugin-README short cites, plus ../-prefixed
cites whose lexical resolution lands on a private skill surface). Every text
file type under the scanned surfaces is read.

In a marketplace monorepo (plugins/ present), a file under plugins/<q>/ that
cites another plugin's skill folder is flagged for the skill root, a bare
SKILL.md, and the scripts/ entry surface, whether spelled as a path, a ../ path
or a github.com tree/blob or raw.githubusercontent.com URL. A cite inside the
same plugin stays legal. When .claude-plugin/marketplace.json names the
marketplace, <plugin>@<marketplace-id> outside an install recipe line is flagged.

  --include-skills    Include .claude/skills/ in scope (intra-skill self-citation review)
  --apply-filters     Drop self-citation and worktree path hits (mechanical filters only)
  --allowlist <file>  Rows of `path<TAB>reason` (path or dir/ prefix) the scan skips;
                      default docs/conventions/audit-encapsulation-allowlist.tsv
USAGE
    exit 0
    ;;
  *)
    echo "audit-encapsulation/detect: unknown arg '$arg'" >&2
    exit 2
    ;;
  esac
done

# Allowlist: one `path<TAB>reason` row per exempt path (a file, or a directory
# prefix ending in `/`); blank lines and `#` comments are skipped. A row with no
# reason is an error: the file records why each path is exempt.
ALLOW_PATHS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  allow_n=0
  while IFS= read -r allow_line || [[ -n "$allow_line" ]]; do
    allow_n=$((allow_n + 1))
    allow_line="${allow_line%$'\r'}"
    [[ -z "${allow_line//[[:space:]]/}" || "$allow_line" == '#'* ]] && continue
    allow_path="${allow_line%%$'\t'*}"
    allow_reason=""
    [[ "$allow_line" == *$'\t'* ]] && allow_reason="${allow_line#*$'\t'}"
    if [[ -z "$allow_path" || -z "${allow_reason//[[:space:]]/}" ]]; then
      echo "audit-encapsulation/detect: $ALLOWLIST_FILE:$allow_n needs a path and a reason, tab-separated" >&2
      exit 2
    fi
    ALLOW_PATHS+=("$allow_path")
  done <"$ALLOWLIST_FILE"
elif [[ "$ALLOWLIST_FILE" != "docs/conventions/audit-encapsulation-allowlist.tsv" ]]; then
  echo "audit-encapsulation/detect: allowlist '$ALLOWLIST_FILE' not found" >&2
  exit 2
fi

is_allowlisted() {
  local file="$1" p
  for p in ${ALLOW_PATHS[@]+"${ALLOW_PATHS[@]}"}; do
    if [[ "$p" == */ ]]; then
      [[ "$file" == "$p"* ]] && return 0
    else
      [[ "$file" == "$p" ]] && return 0
    fi
  done
  return 1
}

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
# the data-file public surface, scripts/ cites from callers outside plugins/
# are never private, so they are dropped here rather than emitted as raw hits;
# a file under plugins/<q>/ citing another plugin's scripts/ is not carved out
# (is_cross_plugin_scripts). PATTERN
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

# True when a RELATIVE cite resolves back inside the citing file's own skill
# root ($4, e.g. `.claude/skills/foo/` or `plugins/demo/skills/alpha/`). Both
# relative shapes land here: a `../`-prefixed path resolves directly, while a
# bare `skills/<self>/` short cite resolves through its recovered `../` prefix.
# A bare short cite with no prefix to recover counts as self-citation outright,
# because a plugin-relative cite names the citing file's own root.
resolves_into_self() {
  local file="$1" line_no="$2" text="$3" self_root="$4"
  local full resolved
  if [[ "$text" == ../* ]]; then
    full="$text"
  else
    # shellcheck disable=SC2310  # recover miss → bare same-root short cite
    full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || return 0
  fi
  # shellcheck disable=SC2310  # lex_resolve miss → leave as candidate
  resolved="$(lex_resolve "$(dirname "$file")/$full")" || return 1
  [[ -n "$resolved" && "$resolved" == "$self_root"* ]]
}

# The plugin a repo path belongs to (`plugins/<q>/...` → q); status 1 when the
# path is outside plugins/.
plugin_of() {
  [[ "$1" =~ ^plugins/([^/]+)/ ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# Path of the skill folder a cite names, resolved against the citing file:
# an absolute `plugins/<p>/skills/...` cite is itself; a `../`-prefixed cite, or
# a bare `skills/...` one with a recoverable `../` prefix, resolves lexically.
# Status 1 when the cite cannot be placed under a plugin.
cite_target() {
  local file="$1" line_no="$2" text="$3" full
  if [[ "$text" == plugins/* ]]; then
    printf '%s' "$text"
    return 0
  fi
  if [[ "$text" == ../* ]]; then
    full="$text"
  else
    # shellcheck disable=SC2310  # recover miss → no target
    full="$(recover_dotdot_prefix "$file" "$line_no" "$text")" || return 1
  fi
  # shellcheck disable=SC2310  # lex_resolve miss → no target
  lex_resolve "$(dirname "$file")/$full" || return 1
}

# True when a scripts/ cite comes from a file under plugins/<q>/ and lands in
# another plugin p≠q. The entry-surface carve-out holds for callers outside
# plugins/ (CI workflows, repo hooks) and for a plugin's own files.
is_cross_plugin_scripts() {
  local file="$1" line_no="$2" text="$3" q p target
  # shellcheck disable=SC2310  # status 1 = file outside plugins/
  q="$(plugin_of "$file")" || return 1
  # shellcheck disable=SC2310  # status 1 = unplaceable cite
  target="$(cite_target "$file" "$line_no" "$text")" || return 1
  [[ "$target" =~ ^plugins/([^/]+)/skills/ ]] || return 1
  p="${BASH_REMATCH[1]}"
  [[ "$p" != "$q" ]]
}

# Skill-root and bare-SKILL.md cites (no trailing subdirectory, so PATTERN
# misses them) from a file under plugins/<q>/ into plugins/<p>/skills/<s> with
# p≠q. $1 = file, $2 = line, $3 = matched text. Prints nothing and returns 1
# for any other shape; subdirectory, scripts/ and anchor cites are other passes'.
is_cross_plugin_surface() {
  local file="$1" line_no="$2" text="$3" q p rest target
  [[ "$text" == *'#' ]] && return 1
  # shellcheck disable=SC2310  # status 1 = file outside plugins/
  q="$(plugin_of "$file")" || return 1
  # shellcheck disable=SC2310  # status 1 = unplaceable cite
  target="$(cite_target "$file" "$line_no" "$text")" || return 1
  [[ "$target" =~ ^plugins/([^/]+)/skills/[^/]+(/.*)?$ ]] || return 1
  p="${BASH_REMATCH[1]}"
  rest="${BASH_REMATCH[2]}"
  [[ "$p" != "$q" ]] || return 1
  [[ -z "$rest" || "$rest" == "/SKILL.md" ]]
}

HITS_FILE="$(mktemp)"
DOTDOT_RAW="$(mktemp)"
RAW_HITS="$(mktemp)"
CROSS_RAW="$(mktemp)"
trap 'rm -f "$HITS_FILE" "$DOTDOT_RAW" "$RAW_HITS" "$CROSS_RAW"' EXIT

# Emit "file:line:match" hits for a pattern across every in-scope surface.
# Every text file type is read (-I skips binaries). Always returns 0: a
# pattern with no hits is an ordinary outcome, not a failure.
scan_scope() {
  local pattern="$1"
  if [[ ${#SCOPE_DIRS[@]} -gt 0 ]]; then
    grep -ErnoI --exclude-dir=node_modules --exclude-dir=.git \
      "$pattern" "${SCOPE_DIRS[@]}" 2>/dev/null || true
  fi
  if [[ ${#SCOPE_FILES[@]} -gt 0 ]]; then
    # -H forces the file prefix even when only one file exists.
    grep -EHnoI "$pattern" "${SCOPE_FILES[@]}" 2>/dev/null || true
  fi
}

# Aggregate hits, then drop scripts/ entry-surface cites (carve-out above)
# unless a plugin file reaches into another plugin's scripts/.
scan_scope "$PATTERN" >"$RAW_HITS"

: >"$HITS_FILE"
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file="${line%%:*}"
  rest="${line#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
  # shellcheck disable=SC2310  # pure predicates; both branches handled
  if is_scripts_carveout "$text" && ! is_cross_plugin_scripts "$file" "$line_no" "$text"; then
    continue
  fi
  printf '%s\n' "$line" >>"$HITS_FILE"
done <"$RAW_HITS"

# Cross-plugin pass: skill-root and bare-SKILL.md cites, which PATTERN misses
# for want of a trailing subdirectory. Absolute paths (a github.com tree/blob or
# raw.githubusercontent.com URL contains one) and ../-prefixed paths with a
# `skills/` segment; a trailing `#` keeps an anchor cite out (PATTERN has it).
CROSS_PATTERN='plugins/[A-Za-z0-9_.-]+/skills/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*#?|(\.\./)+([A-Za-z0-9_.-]+/)*skills/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*#?'
scan_scope "$CROSS_PATTERN" >"$CROSS_RAW"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file="${line%%:*}"
  rest="${line#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
  # A trailing dot is sentence punctuation, not part of the name.
  text="${text%"${text##*[!.]}"}"
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  is_cross_plugin_surface "$file" "$line_no" "$text" || continue
  printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
done <"$CROSS_RAW"

# Own-marketplace-id pass: `<plugin>@<id>` for the id this repo's marketplace
# manifest declares, outside install-recipe lines. Third-party ids never match.
MARKETPLACE_ID=""
if [[ -f .claude-plugin/marketplace.json ]]; then
  MARKETPLACE_ID="$(sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    .claude-plugin/marketplace.json | head -n 1 || true)"
  [[ "$MARKETPLACE_ID" =~ ^[A-Za-z0-9_.-]+$ ]] || MARKETPLACE_ID=""
fi
if [[ -n "$MARKETPLACE_ID" ]]; then
  ID_ESCAPED="${MARKETPLACE_ID//./\\.}"
  RECIPE_RE='plugin[[:space:]]+(install|uninstall|update|enable|disable)'
  scan_scope "[A-Za-z0-9_.-]+@${ID_ESCAPED}\\.?([^A-Za-z0-9_.-]|\$)" >"$CROSS_RAW"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    file="${line%%:*}"
    rest="${line#*:}"
    line_no="${rest%%:*}"
    text="${rest#*:}"
    [[ "$text" =~ [^A-Za-z0-9_.-]$ ]] && text="${text%?}"
    text="${text%"${text##*[!.]}"}"
    src="$(sed -n "${line_no}p" "$file" 2>/dev/null || true)"
    [[ "$src" =~ $RECIPE_RE ]] && continue
    printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
  done <"$CROSS_RAW"
fi

# Second pass (#2716): `../`-prefixed cites whose lexical resolution lands on
# a private skill surface. Covers sibling-skill links like
# `../other-skill/reference/...` that never spell `skills/` in the cite text.
# Candidates already matched by the bare `skills/` alternation (paths that
# still contain a `skills/` segment after `../`) are skipped here to avoid
# duplicate rows.
DOTDOT_PATTERN='(\.\./)+([A-Za-z0-9_.-]+/)+([A-Za-z0-9_.-]+/|SKILL\.md#|[A-Za-z0-9_.-]+\.schema\.json)'
scan_scope "$DOTDOT_PATTERN" >"$DOTDOT_RAW"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file="${line%%:*}"
  rest="${line#*:}"
  line_no="${rest%%:*}"
  text="${rest#*:}"
  # Already covered by the skills/-segment alternation.
  [[ "$text" == *"/skills/"* || "$text" == skills/* ]] && continue
  # shellcheck disable=SC2310  # lex_resolve returns status; continue is the handled miss
  resolved="$(lex_resolve "$(dirname "$file")/$text")" || continue
  # shellcheck disable=SC2310  # is_private_skill_path is a pure predicate; both branches handled
  is_private_skill_path "$resolved" || continue
  printf '%s:%s:%s\n' "$file" "$line_no" "$text" >>"$HITS_FILE"
done <"$DOTDOT_RAW"

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
  # shellcheck disable=SC2310  # pure predicate; both branches handled
  if is_allowlisted "$file"; then
    raw=$((raw - 1))
    continue
  fi
  if [[ "$APPLY_FILTERS" -eq 1 ]]; then
    mech_filtered=0
    if [[ "$file" =~ ^\.claude/skills/([^/]+)/ ]]; then
      self="${BASH_REMATCH[1]}"
      self_root=".claude/skills/${self}/"
      if [[ "$text" == *"$self_root"* ]]; then
        mech_filtered=1
      # A bare skills/<self>/ may be the suffix of a ../-prefixed cross-root
      # cite, so both relative shapes go through lexical resolution.
      elif [[ "$text" == "skills/${self}/"* || "$text" == ../* ]]; then
        # shellcheck disable=SC2310  # pure predicate; both branches handled
        if resolves_into_self "$file" "$line_no" "$text" "$self_root"; then
          mech_filtered=1
        fi
      fi
    elif [[ "$file" =~ ^(plugins/[^/]+)/skills/([^/]+)/ ]]; then
      plugin="${BASH_REMATCH[1]}"
      self="${BASH_REMATCH[2]}"
      self_root="${plugin}/skills/${self}/"
      # Require same plugin root for absolute self-cites so a cross-plugin
      # `.../other/skills/<same-name>/...` match cannot vacate as self-citation
      # merely by skill leaf name (#2716 review).
      if [[ "$text" == "$self_root"* || "$text" == *"/$self_root"* ]]; then
        mech_filtered=1
      elif [[ "$text" == "skills/${self}/"* || "$text" == ../* ]]; then
        # shellcheck disable=SC2310  # pure predicate; both branches handled
        if resolves_into_self "$file" "$line_no" "$text" "$self_root"; then
          mech_filtered=1
        fi
      fi
    elif [[ "$file" == *".worktrees/"* || "$text" == *".worktrees/"* ||
      "$file" == *".claude/worktrees/"* || "$text" == *".claude/worktrees/"* ||
      "$file" == *".git/worktrees/"* || "$text" == *".git/worktrees/"* ]]; then
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
