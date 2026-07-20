#!/usr/bin/env bash
# Static skill-authoring quality gate for a single Claude Code skill.
#
# Runs static checks against one skill directory — NO model invocation. The
# trigger-keyword preservation check (check 3) is the regression-critical net:
# a rewrite that silently drops a `description` trigger phrase degrades
# auto-invocation, and static analysis catches it deterministically.
#
# Exit 0 = all checks pass; 1 = one or more check failures; 2 = usage/env error.
#
# Usage:
#   bash check-skill.sh <skill-name>
#   bash check-skill.sh --help
#
# Skills root resolution (first hit wins):
#   1. CHECK_SKILL_SKILLS_ROOT env var (explicit override)
#   2. ${CLAUDE_PROJECT_DIR}/.claude/skills (plugin runtime)
#   3. <git-root>/.claude/skills (default)
#
# Base ref for the git-backed diff checks (3, 8, 9):
#   CHECK_SKILL_BASE_REF (default HEAD). These checks diff the WORKING TREE
#   against this ref, so the default catches an uncommitted rewrite. For a
#   post-commit audit (where HEAD == tree hides an already-committed change),
#   run on a clean tree with CHECK_SKILL_BASE_REF pointing before the change
#   (e.g. HEAD^ or a merge-base).
#
# Checks:
#   1. Frontmatter parses; name matches dir; description present
#   2. description + when_to_use <= 1536 chars (listing-truncation guard)
#   3. Trigger-keyword preservation vs the base ref (skipped for new skills)
#   4. SKILL.md < 500 lines (hard cap)
#   5. Backtick-cited skill-internal supporting files resolve
#   6. markdownlint clean (markdownlint-cli2; WARN-skip if npx absent)
#   7. scripts/*.test.sh pass where present
#   8. vendor/ byte-identical vs HEAD (vendor-backed skills only)
#   9. Stale-tracking metadata keys preserved vs HEAD (upstream-version/synced/upstream-sha)
#  10. SKILL.md <= 200 lines soft target (WARN; progressive disclosure)
#  11. Gotchas surface present (WARN; inline `## Gotchas` or context|reference/gotchas.md)
#  12. description carries "Use when" trigger phrasing, single-quoted (WARN)
#  13. No committed cache/build artifacts (__pycache__, *.pyc, node_modules) (FAIL)
#  14. Action-router-shaped skill ships evals/evals.json (WARN)
#  15. Companion spoke dirs referenced from SKILL.md (WARN; orphan-spoke direction)
#  16. metadata.category present (INFO only)
#  17. Vendor-backed: metadata.synced not older than 180 days (WARN)
#
# Notes (static, git-diff-based design):
#   - Checks 3/8/9 diff the working tree against CHECK_SKILL_BASE_REF (default
#     HEAD). The default catches an uncommitted rewrite; a post-commit audit
#     sets the base ref before the change and runs on a clean tree (see above).
#   - Frontmatter must open with `---` on line 1; content before the fence is
#     not treated as frontmatter.
#   - A block-scalar `description: |` / `>-` is unfolded before checks 2/3/12,
#     so they see the text rather than the marker. A single-line quoted
#     description is still preferred (the listing budget encourages this).
#   - Trigger-drop protection (check 3) tracks single-quoted 'phrase' triggers.
#     An unquoted `Use when:` list is not tracked; check 12 warns so those
#     triggers get quoted and covered.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  printf 'Error: not in a git repo\n' >&2
  exit 2
fi

# shellcheck source=./skill-frontmatter.sh
source "$SCRIPT_DIR/skill-frontmatter.sh"

# Base ref for the git-backed diff checks (3, 8, 9) — see the header. Default
# HEAD (uncommitted-rewrite case); an explicit ref enables a post-commit audit.
BASE_REF="${CHECK_SKILL_BASE_REF:-HEAD}"
if [[ "$BASE_REF" != "HEAD" ]] \
  && ! git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null 2>&1; then
  printf 'Error: CHECK_SKILL_BASE_REF=%s is not a valid commit\n' "$BASE_REF" >&2
  exit 2
fi

SKILL_NAME="${1:?Usage: check-skill.sh <skill-name>}"

# Resolve the skills root without baking a repo layout (convention-resolution
# ladder): explicit override, then plugin project dir, then git-root default.
if [[ -n "${CHECK_SKILL_SKILLS_ROOT:-}" ]]; then
  SKILLS_ROOT="$CHECK_SKILL_SKILLS_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  SKILLS_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
else
  SKILLS_ROOT="$REPO_ROOT/.claude/skills"
fi

# Anchor a relative skills root to the project root. The setup action persists a
# project-relative path; if the skill is invoked from a subdirectory a relative
# root would otherwise resolve against the cwd and miss the skills.
if [[ "$SKILLS_ROOT" != /* && ! "$SKILLS_ROOT" =~ ^[A-Za-z]:[\\/] ]]; then
  SKILLS_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}/$SKILLS_ROOT"
fi

SKILL_DIR="$SKILLS_ROOT/$SKILL_NAME"
SKILL_MD="$SKILL_DIR/SKILL.md"

# SKILL_REL is the skill dir relative to the git root, so the git-backed checks
# (3, 8, 9, 13) address the right tree entry even when the skills root is not
# the conventional .claude/skills. Ask git for the prefix rather than
# string-stripping REPO_ROOT — on Git Bash `git rev-parse` and `pwd` can differ
# in drive-letter case / slash form, which would silently break the strip.
# Empty when the skill dir is outside the repo (git-backed checks then no-op).
SKILL_REL="$(git -C "$SKILL_DIR" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"
SKILL_REL="${SKILL_REL%/}"

# Tunables (listing description cap; SKILL.md line caps; vendor sync age).
DESC_CHAR_CAP=1536
LINE_HARD_CAP=500
LINE_SOFT_CAP=200
SYNCED_MAX_AGE_DAYS=180

FAILED=0
WARNINGS=0

err() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILED=$((FAILED + 1))
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  WARNINGS=$((WARNINGS + 1))
}

note() {
  printf 'INFO: %s\n' "$*"
}

if [[ ! -d "$SKILL_DIR" ]]; then
  err "Skill not found: $SKILL_DIR"
  exit 1
fi
if [[ ! -f "$SKILL_MD" ]]; then
  err "SKILL.md not found: $SKILL_MD"
  exit 1
fi

# --- Check 1: frontmatter parses; name matches dir; description present ----

FRONTMATTER="$(skill_frontmatter::extract <"$SKILL_MD")"
if [[ -z "$FRONTMATTER" ]]; then
  err "no YAML frontmatter block found (expected content between two '---' fences)"
else
  grep -qE '^name:[[:space:]]*\S' <<<"$FRONTMATTER" || err "frontmatter missing 'name:'"
  grep -qE '^description:[[:space:]]*\S' <<<"$FRONTMATTER" || err "frontmatter missing 'description:'"

  # The directory name is what Claude Code namespaces the skill by, so a
  # divergent frontmatter name silently relocates the invocation the doctrine
  # says the skill has — and the picker labels rows by the resolved leaf name,
  # so the drift never surfaces in the listing either.
  RAW_NAME="$(skill_frontmatter::field name <<<"$FRONTMATTER")"
  # A trailing `# comment` is legal on a YAML scalar and is not part of the
  # value. Skill names are kebab-case per the Agent Skills spec, so a '#' can
  # never belong to the name itself — strip from the first whitespace-then-hash,
  # before unquoting, so a quoted name with a trailing comment also resolves.
  RAW_NAME="${RAW_NAME%%[[:space:]]#*}"
  RAW_NAME="${RAW_NAME%"${RAW_NAME##*[![:space:]]}"}"
  CUR_NAME="$(skill_frontmatter::strip_quotes "$RAW_NAME")"
  # Constrain the accepted syntax rather than reimplementing a YAML decoder in
  # bash: the Agent Skills spec restricts a name to lowercase alphanumerics and
  # hyphens, so anything else (an escape sequence like "\x2d", whitespace, an
  # unresolved quote) is a name defect in its own right. Reporting it as one
  # keeps the directory comparison below working on literal text, and stops a
  # decodable-but-undecoded scalar from surfacing as a confusing mismatch.
  if [[ -n "$CUR_NAME" && ! "$CUR_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    err "frontmatter name '$CUR_NAME' is not kebab-case ([a-z0-9] and hyphens, per the Agent Skills spec)"
  elif [[ -n "$CUR_NAME" && "$CUR_NAME" != "$SKILL_NAME" ]]; then
    err "frontmatter name '$CUR_NAME' does not match skill directory '$SKILL_NAME'"
  fi
fi

# --- Check 2: description + when_to_use <= DESC_CHAR_CAP chars --------------
# Cap is per-skill listing entry (description + when_to_use combined) — overflow
# truncates the listing and degrades auto-invocation.

CUR_DESC="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$FRONTMATTER")")"
CUR_WTU="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$FRONTMATTER")")"
DESC_LEN=${#CUR_DESC}
WTU_LEN=${#CUR_WTU}
COMBINED_LEN=$((DESC_LEN + WTU_LEN))
if ((COMBINED_LEN > DESC_CHAR_CAP)); then
  err "description+when_to_use is $COMBINED_LEN chars (cap $DESC_CHAR_CAP — overflow truncates the listing)"
elif ((WTU_LEN > 0)); then
  note "description+when_to_use $COMBINED_LEN/$DESC_CHAR_CAP chars (desc $DESC_LEN + when_to_use $WTU_LEN)"
else
  note "description length $DESC_LEN/$DESC_CHAR_CAP chars"
fi

# --- Check 3: trigger-keyword preservation vs HEAD -------------------------

if git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
  BASE_FM_3="$(git -C "$REPO_ROOT" show "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
  BASE_DESC="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$BASE_FM_3")")"
  BASE_WTU="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$BASE_FM_3")")"
  BASE_TRIG="$(printf '%s\n%s\n' "$BASE_DESC" "$BASE_WTU" | skill_frontmatter::extract_triggers)"
  CUR_TRIG="$(printf '%s\n%s\n' "$CUR_DESC" "$CUR_WTU" | skill_frontmatter::extract_triggers)"
  if [[ -n "$BASE_TRIG" ]]; then
    MISSING="$(comm -23 <(printf '%s\n' "$BASE_TRIG") <(printf '%s\n' "$CUR_TRIG"))"
    if [[ -n "$MISSING" ]]; then
      err "dropped trigger keyword(s) vs $BASE_REF (auto-invocation regression): $(printf '%s' "$MISSING" | tr '\n' ' ')"
    else
      note "all $(printf '%s\n' "$BASE_TRIG" | grep -c .) base-ref trigger phrase(s) preserved"
    fi
  fi
else
  note "no $BASE_REF version (new skill) — keyword-preservation check skipped"
fi

# --- Check 4: SKILL.md < LINE_HARD_CAP lines -------------------------------

LINE_COUNT="$(grep -c '' "$SKILL_MD")"
if ((LINE_COUNT >= LINE_HARD_CAP)); then
  err "SKILL.md is $LINE_COUNT lines (hard cap $LINE_HARD_CAP)"
else
  note "SKILL.md $LINE_COUNT/$LINE_HARD_CAP lines"
fi

# --- Check 5: skill-internal supporting files resolve ----------------------

# Match BOTH backtick refs (`context/foo.md`) AND markdown-link refs
# ([label](context/foo.md#anchor)) into known skill-internal dirs. Scoping to
# these dir names avoids matching prose-example paths; link-form `#anchor`
# suffixes are stripped before the existence check. Process substitution (not a
# pipe) keeps the loop in this shell so `err` increments FAILED.
#
# A placeholder-segment path (`context/<topic>.md`) is ignored: the grep
# char-class below excludes `<` and `>`, so it never enters this loop. A
# gitignored runtime-output path is auto-skipped (not a tracked supporting file,
# so skipping cannot mask a real tracked ref).
INTERNAL_DIRS='context|templates|scripts|reference|references|actions|evals|lanes|catalog|vendor'
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  if git -C "$REPO_ROOT" check-ignore -q "$SKILL_DIR/$ref" 2>/dev/null; then
    note "check-5 skip (gitignored runtime path): $ref"
    continue
  fi
  if [[ ! -e "$SKILL_DIR/$ref" ]]; then
    ref_line="$(grep -nF "$ref" "$SKILL_MD" 2>/dev/null | head -1 | cut -d: -f1)"
    err "broken skill-internal ref: $ref (no such file under the skill dir; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example)"
  fi
done < <(
  {
    grep -oE "\`($INTERNAL_DIRS)/[A-Za-z0-9._/-]+\`" "$SKILL_MD" 2>/dev/null | tr -d '`'
    grep -oE "\]\(($INTERNAL_DIRS)/[A-Za-z0-9._/#-]+\)" "$SKILL_MD" 2>/dev/null \
      | sed -E 's/^\]\(//; s/\)$//; s/#.*$//'
  } | sort -u
)

# --- Check 6: markdownlint clean -------------------------------------------

# CHECK_SKILL_SKIP_MARKDOWNLINT=1 is a test seam: fixture SKILL.md files may
# live outside a repo with markdownlint config, so the tool applies defaults
# (MD041/MD013) that real skills intentionally violate.
if [[ "${CHECK_SKILL_SKIP_MARKDOWNLINT:-}" == "1" ]]; then
  note "markdownlint check skipped (CHECK_SKILL_SKIP_MARKDOWNLINT=1)"
elif command -v npx >/dev/null 2>&1; then
  # --no-install: never trigger a remote fetch. A genuine lint failure emits
  # file:line findings; a non-zero exit WITHOUT such findings means the package
  # is unavailable (not installed / offline), which downgrades to a WARN-skip
  # rather than a hard FAIL on an otherwise valid skill.
  if ML_OUT="$(npx --no-install markdownlint-cli2 "$SKILL_MD" 2>&1)"; then
    note "markdownlint clean"
  elif grep -qE '^\S+:[0-9]+' <<<"$ML_OUT"; then
    err "markdownlint failed:
$(printf '%s\n' "$ML_OUT" | grep -E '^\S+:[0-9]+' | head -10)"
  else
    warn "markdownlint-cli2 unavailable (not installed / not resolvable) — markdownlint check skipped"
  fi
else
  warn "npx not found — markdownlint check skipped"
fi

# --- Check 7: scripts/*.test.sh pass where present -------------------------

if [[ -d "$SKILL_DIR/scripts" ]]; then
  while IFS= read -r test_sh; do
    [[ -z "$test_sh" ]] && continue
    # env -u: this gate may run inside git-hook chains where git exports
    # GIT_DIR/GIT_INDEX_FILE — a fixture `git init` in a test would then mutate
    # the real repo. Strip before exec.
    if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_PREFIX \
      bash "$test_sh" >/dev/null 2>&1; then
      note "script test passed: ${test_sh#"$SKILL_DIR"/}"
    else
      err "script test failed: ${test_sh#"$SKILL_DIR"/}"
    fi
  done < <(find "$SKILL_DIR/scripts" -name '*.test.sh' -type f 2>/dev/null | sort)
fi

# --- Check 8: vendor/ byte-identical vs HEAD (vendor-backed only) ----------

# Only meaningful when the skill has a HEAD baseline: a brand-new vendored skill
# staged before a pre-commit run has no prior vendor/ to preserve, so its staged
# files must not read as "changed vs HEAD".
if [[ -d "$SKILL_DIR/vendor" ]] && git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
  if git -C "$REPO_ROOT" diff --quiet "$BASE_REF" -- "$SKILL_REL/vendor/" 2>/dev/null; then
    note "vendor/ unchanged vs $BASE_REF"
  else
    err "vendor/ changed vs $BASE_REF — vendored content carries a byte-identical guarantee; rewrites must not touch vendor/"
  fi
fi

# --- Check 9: stale-tracking metadata keys preserved vs HEAD ---------------

if git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
  BASE_FM="$(git -C "$REPO_ROOT" show "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
  for key in upstream-version synced upstream-sha; do
    if grep -qE "^[[:space:]]*$key:" <<<"$BASE_FM"; then
      grep -qE "^[[:space:]]*$key:" <<<"$FRONTMATTER" \
        || err "metadata key '$key' present at $BASE_REF but dropped (stale-tracking metadata for a vendored skill)"
    fi
  done
fi

# --- Check 10: SKILL.md soft line target (progressive disclosure) ----------

if ((LINE_COUNT > LINE_SOFT_CAP && LINE_COUNT < LINE_HARD_CAP)); then
  warn "SKILL.md is $LINE_COUNT lines (soft target $LINE_SOFT_CAP — consider pushing detail to progressive-disclosure spokes)"
fi

# --- Check 11: Gotchas surface present --------------------------------------

if ! grep -qEi '^##+[[:space:]]+(gotchas|quirks)' "$SKILL_MD" \
  && [[ ! -f "$SKILL_DIR/context/gotchas.md" ]] \
  && [[ ! -f "$SKILL_DIR/reference/gotchas.md" ]] \
  && [[ ! -f "$SKILL_DIR/references/gotchas.md" ]]; then
  warn "no Gotchas surface (inline '## Gotchas' or context/gotchas.md) — confirm the skill has no observed failure history"
fi

# --- Check 12: description carries trigger phrasing --------------------------

if [[ -n "$CUR_DESC" ]]; then
  if ! grep -qi 'use when' <<<"$CUR_DESC$CUR_WTU"; then
    warn "description has no 'Use when:' trigger phrasing — a description is a trigger spec, not a summary"
  elif [[ -z "$(printf '%s\n%s\n' "$CUR_DESC" "$CUR_WTU" | skill_frontmatter::extract_triggers)" ]]; then
    warn "'Use when:' triggers are not single-quoted — drop-regression protection (check 3) tracks only 'quoted' phrases; single-quote each trigger phrase to cover it"
  fi
fi

# --- Check 13: no committed cache/build artifacts ----------------------------

CACHE_HITS="$(git -C "$REPO_ROOT" ls-files "$SKILL_REL" 2>/dev/null | grep -E '__pycache__|\.pyc$|/node_modules/' || true)"
if [[ -n "$CACHE_HITS" ]]; then
  err "committed cache/build artifact(s) under the skill dir: $(printf '%s' "$CACHE_HITS" | head -3 | tr '\n' ' ')"
fi

# --- Check 14: action-router shape without evals ------------------------------

if grep -qE '^##+[[:space:]]+Actions?\b' "$SKILL_MD" && [[ ! -f "$SKILL_DIR/evals/evals.json" ]]; then
  warn "action-router-shaped skill with no evals/evals.json — check whether the skill warrants triggering evals"
fi

# --- Check 15: companion spoke dirs referenced from the hub -------------------

for spoke_dir in context reference references templates lanes actions; do
  [[ -d "$SKILL_DIR/$spoke_dir" ]] || continue
  grep -q "$spoke_dir/" "$SKILL_MD" \
    || warn "orphan spoke: $spoke_dir/ exists but SKILL.md never references it (progressive-disclosure routing gap)"
done

# --- Check 16: metadata.category (informational) ------------------------------

if [[ -n "$FRONTMATTER" ]] && ! grep -A8 '^metadata:' <<<"$FRONTMATTER" | grep -q 'category:'; then
  note "no metadata.category in frontmatter (optional — category not machine-readable)"
fi

# --- Check 17: vendor sync age ------------------------------------------------

if [[ -d "$SKILL_DIR/vendor" ]]; then
  SYNCED_VAL="$(awk '/^metadata:/{m=1;next} m && /^[a-zA-Z]/{m=0} m && /^[[:space:]]+synced:/{print $2;exit}' <<<"$FRONTMATTER" | tr -d '"' | tr -d "'")"
  if [[ "$SYNCED_VAL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    if SYNCED_EPOCH="$(date -u -d "$SYNCED_VAL" +%s 2>/dev/null)"; then
      AGE_DAYS=$((($(date -u +%s) - SYNCED_EPOCH) / 86400))
      if ((AGE_DAYS > SYNCED_MAX_AGE_DAYS)); then
        warn "vendor last synced $AGE_DAYS days ago (> $SYNCED_MAX_AGE_DAYS) — run the skill's update action"
      fi
    fi
  fi
fi

# --- Summary ---------------------------------------------------------------

printf '\n'
if ((FAILED > 0)); then
  printf 'CHECK-SKILL %s: FAIL — %d error(s), %d warning(s)\n' "$SKILL_NAME" "$FAILED" "$WARNINGS" >&2
  exit 1
fi
printf 'CHECK-SKILL %s: PASS — 0 errors, %d warning(s)\n' "$SKILL_NAME" "$WARNINGS"
exit 0
