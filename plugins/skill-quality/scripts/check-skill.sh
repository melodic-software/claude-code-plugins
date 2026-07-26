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
# NOT covered here: the SHARED listing budget (skillListingBudgetFraction) that
# every loaded skill draws from together, a different cross-skill limit from
# check 2's per-skill entry cap below. See the companion
# check-listing-budget.sh for that aggregate report (always advisory).
#
# Checks:
#   1. Frontmatter parses; name matches dir; description present
#   2. description + when_to_use <= 1536 chars (per-skill listing-entry cap;
#      counts the literal " - " joiner the harness inserts when when_to_use is
#      populated)
#   3. Trigger-keyword preservation vs the base ref (skipped for new skills;
#      a phrase moved verbatim to a sibling skill's listing text — one the
#      sibling did not carry at the base ref — WARNs, since the marketplace
#      listing still routes it; lost phrases and coincidental overlap FAIL)
#   4. SKILL.md < 500 lines (hard cap)
#   5. Backtick-cited skill-internal supporting files resolve
#   6. markdownlint clean (markdownlint-cli2; WARN-skip if npx absent)
#   7. scripts/*.test.sh pass where present
#   8. vendor/ byte-identical vs HEAD, unless paired with an upstream-version
#      bump (a legitimate maintainer-run sync) (vendor-backed skills only)
#   9. Stale-tracking metadata keys preserved vs HEAD (upstream-version/synced/upstream-sha)
#  10. SKILL.md <= 200 lines soft target (WARN; progressive disclosure)
#  11. Gotchas surface present (WARN; inline `## Gotchas` or context|reference/gotchas.md)
#  12. description carries "Use when" trigger phrasing, single-quoted (WARN)
#  13. No committed cache/build artifacts (__pycache__, *.pyc, node_modules) (FAIL)
#  14. Action-router-shaped skill ships evals/evals.json (WARN)
#  15. Companion spoke dirs referenced from SKILL.md (WARN; orphan-spoke direction)
#  16. metadata.category present (INFO only)
#  17. Vendor-backed: metadata.synced not older than 180 days (WARN)
#  18. Precompute opportunity: a fenced shell block gathers read-only context
#      the skill could inline at load time via `!` injection (WARN; heuristic)
#  19. shell: declared when `!` dynamic-context injections carry bash-only syntax
#      (FAIL bash-only syntax + no shell:; WARN portable-looking but undeclared)
#  20. `!`-injected commands carry a `|| <fallback>` (WARN; undocumented injection
#      failure semantics — degrade to a known string, not a surprise)
#  21. Fresh-eyes declaration conformance: same-context judgment language carries
#      fresh-context delegation wording or a fresh-eyes-exempt directive nearby
#      (WARN; heuristic); malformed/reason-less directives FAIL
#      (spec: skills/check/reference/fresh-eyes-declarations.md)
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
  # A `plugin:skill` argument is a common miss: the operator wants to gate a
  # marketplace-INSTALLED skill, but this checker resolves a bare skill name
  # under one skills root — it deliberately does NOT reverse-engineer Claude
  # Code's plugin-cache layout to find it. The cache path
  # (`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills`) is an
  # internal detail: only the cache's existence is documented, the
  # `<mp>/<plugin>/<version>` nesting is not, and the version dir changes on
  # every update (code.claude.com/docs/en/plugins-reference). Point the root at
  # it explicitly instead. Note the cache is a COPY, not a git checkout, so the
  # git-backed checks (3 trigger-preservation, 8 vendor, 9 stale-metadata)
  # correctly no-op there — a "new skill / skipped" result is expected, not a
  # defect (this is why check 3 cannot compare an installed skill against HEAD).
  if [[ "$SKILL_NAME" == *:* ]]; then
    # %q makes the leaf a paste-safe shell token — a malformed name whose leaf
    # carries shell syntax must not become an executable substitution when the
    # operator copies the suggested command.
    q_leaf=$(printf '%q' "${SKILL_NAME##*:}")
    err "Skill not found: '$SKILL_NAME'. This looks like a plugin:skill name — the checker resolves a bare skill name under one skills root, not Claude Code's internal plugin-cache layout. To gate a marketplace-installed skill, point the root at its installed skills dir:
    CHECK_SKILL_SKILLS_ROOT=~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh\" $q_leaf
  The cache is a copy, not a git checkout, so the git-backed checks (3/8/9) no-op there (a 'new skill / skipped' result is expected)."
  else
    err "Skill not found: $SKILL_DIR. Set CHECK_SKILL_SKILLS_ROOT (or skill-quality's skills_root) to the directory that CONTAINS '$SKILL_NAME' as a subdirectory."
  fi
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
  grep -qE '^name:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER" || err "frontmatter missing 'name:'"
  grep -qE '^description:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER" || err "frontmatter missing 'description:'"

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
# truncates the listing and degrades auto-invocation. The harness assembles the
# entry as description + " - " + when_to_use — a literal 3-char joiner — so the
# combined length must include it whenever when_to_use is populated, or this
# check under-counts by 3 and can pass an entry that actually overflows.
JOINER_LEN=0
CUR_DESC="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$FRONTMATTER")")"
CUR_WTU="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$FRONTMATTER")")"
DESC_LEN=${#CUR_DESC}
WTU_LEN=${#CUR_WTU}
((WTU_LEN > 0)) && JOINER_LEN=3
COMBINED_LEN=$((DESC_LEN + JOINER_LEN + WTU_LEN))
if ((COMBINED_LEN > DESC_CHAR_CAP)); then
  err "description+when_to_use is $COMBINED_LEN chars (cap $DESC_CHAR_CAP — overflow truncates the listing)"
elif ((WTU_LEN > 0)); then
  note "description+when_to_use $COMBINED_LEN/$DESC_CHAR_CAP chars (desc $DESC_LEN + joiner $JOINER_LEN + when_to_use $WTU_LEN)"
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
      # A dropped phrase that reappears verbatim in a SIBLING skill's listing
      # text (same skills root, working tree) — where the sibling's BASE_REF
      # frontmatter did NOT already carry it — is a deliberate trigger MOVE,
      # not a lost trigger: the marketplace listing still routes the phrase,
      # which is the regression this check exists to catch. The base-ref
      # condition keeps the exception exactly as narrow as the rationale: a
      # phrase the sibling carried all along is coincidental overlap, not a
      # move, and dropping it here still FAILs. Moves WARN (visible until
      # merge, never blocking).
      # Repo-relative parent of the skills root ("" when skills sit at the
      # repo root), so sibling base-ref lookups address the right tree entry.
      SKILLS_REL_PARENT=""
      [[ "$SKILL_REL" == */* ]] && SKILLS_REL_PARENT="${SKILL_REL%/*}"
      LOST=""
      while IFS= read -r phrase; do
        [[ -n "$phrase" ]] || continue
        MOVE_HOST=""
        for other_md in "$SKILLS_ROOT"/*/SKILL.md; do
          [[ -f "$other_md" ]] || continue
          [[ "$other_md" == "$SKILL_MD" ]] && continue
          OTHER_FM="$(skill_frontmatter::extract <"$other_md")"
          OTHER_TRIG="$(printf '%s\n%s\n' \
            "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$OTHER_FM")")" \
            "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$OTHER_FM")")" |
            skill_frontmatter::extract_triggers)"
          printf '%s\n' "$OTHER_TRIG" | grep -qxF -- "$phrase" || continue
          OTHER_NAME="${other_md%/SKILL.md}"
          OTHER_NAME="${OTHER_NAME##*/}"
          OTHER_REL="${SKILLS_REL_PARENT:+$SKILLS_REL_PARENT/}$OTHER_NAME"
          if git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$OTHER_REL/SKILL.md" 2>/dev/null; then
            OTHER_BASE_FM="$(git -C "$REPO_ROOT" show "$BASE_REF:$OTHER_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
            OTHER_BASE_TRIG="$(printf '%s\n%s\n' \
              "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$OTHER_BASE_FM")")" \
              "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$OTHER_BASE_FM")")" |
              skill_frontmatter::extract_triggers)"
            # Sibling already carried the phrase at BASE_REF: coincidental
            # overlap, not a move — keep looking for a genuine host.
            printf '%s\n' "$OTHER_BASE_TRIG" | grep -qxF -- "$phrase" && continue
          fi
          MOVE_HOST="$OTHER_NAME"
          break
        done
        if [[ -n "$MOVE_HOST" ]]; then
          warn "trigger phrase $phrase moved to sibling skill '$MOVE_HOST' — listing coverage preserved, confirm the move is deliberate"
        else
          LOST="${LOST}${phrase}"$'\n'
        fi
      done <<<"$MISSING"
      if [[ -n "$LOST" ]]; then
        err "dropped trigger keyword(s) vs $BASE_REF (auto-invocation regression): $(printf '%s' "$LOST" | tr '\n' ' ')"
      fi
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
  elif grep -qE '^[^[:space:]]+:[0-9]+' <<<"$ML_OUT"; then
    err "markdownlint failed:
$(printf '%s\n' "$ML_OUT" | grep -E '^[^[:space:]]+:[0-9]+' | head -10)"
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
    # A vendor/ diff is legitimate exactly when paired with a bumped
    # metadata.upstream-version: the maintainer-run sync flow (the skill's own
    # `update` action) always replaces vendor/ wholesale from a fresh upstream
    # release AND bumps this key in the same change. A vendor/ diff with no
    # accompanying version bump means vendor/ was hand-edited, which the
    # byte-identical guarantee forbids.
    BASE_FM_V8="$(git -C "$REPO_ROOT" show "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
    BASE_UPSTREAM_VERSION="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::metadata_field upstream-version <<<"$BASE_FM_V8")")"
    CUR_UPSTREAM_VERSION="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::metadata_field upstream-version <<<"$FRONTMATTER")")"
    if [[ -n "$CUR_UPSTREAM_VERSION" && "$CUR_UPSTREAM_VERSION" != "$BASE_UPSTREAM_VERSION" ]]; then
      note "vendor/ changed vs $BASE_REF, paired with an upstream-version bump ($BASE_UPSTREAM_VERSION -> $CUR_UPSTREAM_VERSION) — legitimate sync"
    else
      err "vendor/ changed vs $BASE_REF — vendored content carries a byte-identical guarantee; rewrites must not touch vendor/ (no accompanying metadata.upstream-version bump)"
    fi
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

if grep -qE '^##+[[:space:]]+Actions?($|[^A-Za-z0-9_])' "$SKILL_MD" && [[ ! -f "$SKILL_DIR/evals/evals.json" ]]; then
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
    # portability-ok: GNU-first, BSD fallback co-located (#1510) — was a real,
    # previously-unguarded gap: this check silently no-op'd on BSD/macOS.
    if SYNCED_EPOCH="$(date -u -d "$SYNCED_VAL" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$SYNCED_VAL" +%s 2>/dev/null)"; then
      AGE_DAYS=$((($(date -u +%s) - SYNCED_EPOCH) / 86400))
      if ((AGE_DAYS > SYNCED_MAX_AGE_DAYS)); then
        warn "vendor last synced $AGE_DAYS days ago (> $SYNCED_MAX_AGE_DAYS) — run the skill's update action"
      fi
    fi
  fi
fi

# --- Check 18: precompute opportunity (WARN; advisory heuristic) --------------
# Flags a SKILL.md that gathers deterministic, read-only context by telling
# Claude to run shell commands at invocation, when that output could instead be
# inlined at load time via `!`command`` / ```! dynamic-context injection (one
# preprocessing pass, no per-invocation tool round-trip). Advisory only: a
# static scan cannot tell an instruction-to-run block from an illustrative
# example, and it reads fenced shell blocks only (not prose "run `git status`").
# The whole-file gate below (silent when the skill already injects with `!`)
# is deliberate — it suppresses per-block opportunities in a skill that already
# precomputes something, an accepted recall limit for an advisory check.

# Read-only context-gathering command line? The design FAILS CLOSED: the
# first-token check below only sees the head of the line, so any shell construct
# that can hide a second command or a write disqualifies the line up front —
# redirection (`>`/`<`), command/process substitution (`$(...)`, backticks),
# backgrounding/chaining (`&`, `&&`, `;`), and a bare pipe (`| tee`) — as does a
# side-effecting option that survives an allowlisted reader (`find -exec`,
# `find -delete`, `git diff --output`). `|| echo` is the one sanctioned
# continuation (our fallback form), so `||` is stripped before the pipe test.
# git/gh are matched by a read-only subcommand/verb allowlist, never wholesale,
# so an unlisted mutation (`git stash`, `gh pr merge`) is never read-only. Every
# miss lands on the safe side — a missed opportunity, never advice to auto-run a
# mutation at load time.
precompute_readonly_line() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"   # ltrim
  line="${line#\$ }"                          # strip a leading `$ ` prompt

  # Shell metacharacters that can introduce a second command or a write. `<(`
  # and `>(` process substitution are caught by the `<`/`>` tests.
  case "$line" in
    *'>'* | *'<'* | *';'* | *'&'*) return 1 ;;
    *) ;;
  esac
  # shellcheck disable=SC2016  # single quotes are deliberate: '$(' is a literal glob, not a shell expansion
  case "$line" in *'$('*) return 1 ;; *) ;; esac   # $(...) command substitution
  case "$line" in *'`'*) return 1 ;; *) ;; esac     # backtick command substitution
  # `|| echo <fallback>` is the one sanctioned continuation. Remove those, then
  # any residual pipe disqualifies the line — a bare `| sink`, or a `||`
  # continuation into a non-echo command such as `|| bash x`.
  # shellcheck disable=SC2016  # single quotes deliberate: \|\| and $ are literal regex, not a shell expansion
  local sanitized
  sanitized="$(sed -E 's/\|\|[[:space:]]*echo([[:space:]]|$)/ /g' <<<"$line")"
  case "$sanitized" in *'|'*) return 1 ;; *) ;; esac

  # Side-effecting options that survive the head-command allowlist: command- or
  # file-writing find primaries, a git reader's file-output flag, and git's
  # external-program diff options (`--ext-diff` runs a configured diff.external
  # helper; `--textconv` runs a configured textconv filter). Repo config can
  # still attach programs to a plain `git diff` (default diff.external / textconv
  # on configured paths) — that is inherent to git and beyond a static line scan.
  # shellcheck disable=SC2016  # single quotes are deliberate: $ is an ERE end anchor, not a shell expansion
  grep -qE '(^|[[:space:]])(-exec|-execdir|-ok|-okdir|-delete|-fprintf|-fprint0|-fprint|-fls|--output|--ext-diff|--textconv|rm|mv|cp|tee|sed|mkdir|touch)([[:space:]=]|$)' <<<"$line" && return 1

  local cmd="${line%%[[:space:]]*}"
  case "$cmd" in
    ls | pwd | cat | find | date | uname | whoami | hostname | wc | head | tail | echo | printf | id | stat | du | df | basename | dirname | realpath | readlink | groups | tree | sw_vers) return 0 ;;
    git)
      local sub="${line#git}"
      sub="${sub#"${sub%%[![:space:]]*}"}"
      sub="${sub%%[[:space:]]*}"
      case "$sub" in
        status | log | diff | show | rev-parse | rev-list | describe | ls-files | ls-tree | symbolic-ref | shortlog | blame | cat-file | for-each-ref | name-rev | whatchanged) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    gh)
      # gh nests the read verb after the object (gh pr diff, gh run view). Allow
      # only a known read verb, and never when a write verb is also present.
      case " $line " in
        *" create "* | *" edit "* | *" delete "* | *" merge "* | *" close "* | *" comment "*) return 1 ;;
        *" view "* | *" diff "* | *" list "* | *" status "* | *" checks "*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Does the skill already use `!` dynamic-context injection anywhere? Inline form
# is recognized only at line start or after whitespace (per the skills docs); a
# ```! opening fence is the multi-line form. Either presence silences check 18.
PRECOMPUTE_INJECTS=0
if grep -qE '(^|[[:space:]])!`' "$SKILL_MD" || grep -qE '^[[:space:]]*```+!' "$SKILL_MD"; then
  PRECOMPUTE_INJECTS=1
fi

PRECOMPUTE_CANDIDATE=0
if ((PRECOMPUTE_INJECTS == 0)); then
  # Single-level fence scan. A fenced code block is opened by a run of >=3
  # backticks and closes on a bare fence of at least that many; content inside
  # never opens a nested block (CommonMark), so inner ``` examples inside a
  # wider ```` wrapper are treated as literal content, not scanned as commands.
  # shellcheck disable=SC2016  # single quotes are deliberate: backticks and $ are literal regex, not shell expansion
  fence_open_re='^(```+)([^`]*)$'
  in_block=0
  fence_len=0
  is_shell=0
  block_ok=1
  block_has_cmd=0
  while IFS= read -r bl || [[ -n "$bl" ]]; do
    trimmed="${bl#"${bl%%[![:space:]]*}"}"
    if [[ "$trimmed" =~ $fence_open_re ]]; then
      ticks="${BASH_REMATCH[1]}"
      info="${BASH_REMATCH[2]}"
      n=${#ticks}
      info="${info#"${info%%[![:space:]]*}"}"
      info_first="${info%%[[:space:]]*}"
      if ((in_block == 0)); then
        in_block=1
        fence_len=$n
        block_ok=1
        block_has_cmd=0
        case "$info_first" in
          bash | sh | shell | zsh | console | shell-session | shellsession | sh-session) is_shell=1 ;;
          *) is_shell=0 ;;
        esac
      elif ((n >= fence_len)) && [[ -z "$info" ]]; then
        if ((is_shell == 1 && block_ok == 1 && block_has_cmd == 1)); then
          PRECOMPUTE_CANDIDATE=1
        fi
        in_block=0
        is_shell=0
      fi
      continue
    fi
    if ((in_block == 1 && is_shell == 1)); then
      if [[ -n "$trimmed" && "$trimmed" != \#* ]]; then
        block_has_cmd=1
        precompute_readonly_line "$bl" || block_ok=0
      fi
    fi
  done <"$SKILL_MD"
fi

if ((PRECOMPUTE_CANDIDATE == 1)); then
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks and ! in the advisory text are literal, not shell expansion
  warn 'precompute opportunity: a fenced shell block runs read-only context-gathering commands the skill could inline at load time via `!`command`` / ```! dynamic-context injection (preprocessed once at load, no per-invocation tool call). If the block runs on every invocation to gather context, convert it; if it is an illustrative example, ignore. Heuristic over fenced shell blocks — see https://code.claude.com/docs/en/skills#inject-dynamic-context'
fi

# --- Checks 19-20: dynamic-context injection portability + fallback ----------
# Both checks scan the INJECTED command text only — never prose or a plain
# ```bash example that merely shows the syntax. Collect it once: every inline
# !`cmd` occurrence, plus the body lines of each ```! fenced block. Lines inside
# a NON-injection fenced block are literal examples, so inline !` there is
# skipped too (a general-fence state gates the inline scan). The inline form is
# recognized only at line start or after whitespace (per the injection docs), so
# a mid-token `!`` such as an inline `#!` code span in prose is not an injection.
INJECTIONS=()
inj_in_fence=0     # inside any fenced code block
inj_fence_len=0
inj_is_injection=0 # the current fence opened as a ```! injection block
# shellcheck disable=SC2016  # single quotes deliberate: backticks and $ are literal regex, not shell expansion
inj_fence_re='^(```+)([^`]*)$'
while IFS= read -r il || [[ -n "$il" ]]; do
  itrim="${il#"${il%%[![:space:]]*}"}"
  if [[ "$itrim" =~ $inj_fence_re ]]; then
    iticks="${BASH_REMATCH[1]}"
    iinfo="${BASH_REMATCH[2]}"
    ilen=${#iticks}
    iinfo="${iinfo#"${iinfo%%[![:space:]]*}"}" # ltrim the info string
    if ((inj_in_fence == 0)); then
      inj_in_fence=1
      inj_fence_len=$ilen
      [[ "$iinfo" == '!'* ]] && inj_is_injection=1 || inj_is_injection=0
    elif ((ilen >= inj_fence_len)) && [[ -z "$iinfo" ]]; then
      inj_in_fence=0
      inj_is_injection=0
    fi
    continue
  fi
  if ((inj_in_fence == 1)); then
    if ((inj_is_injection == 1)) && [[ -n "$itrim" && "$itrim" != \#* ]]; then
      INJECTIONS+=("$il")
    fi
    continue # inside a non-injection fence → literal example, skip inline scan
  fi
  # Outside any fence: collect every inline injection on the line. grep -oE
  # emits each anchored `<boundary>!`cmd`` match on its own line; strip the
  # boundary + opening !` and the closing backtick to leave the command. Fixed
  # literals do the stripping (never the command text), so a command carrying
  # glob metacharacters is captured verbatim.
  # shellcheck disable=SC2016  # single quotes deliberate: the backticks are literal delimiters, not shell expansion
  while IFS= read -r inj_match; do
    inj_match="${inj_match#*'!`'}" # drop boundary + opening !`
    inj_match="${inj_match%'`'}"   # drop closing backtick
    INJECTIONS+=("$inj_match")
  done < <(grep -oE '(^|[[:space:]])!`[^`]+`' <<<"$il")
done <"$SKILL_MD"

if ((${#INJECTIONS[@]} > 0)); then
  # --- Check 19: shell declaration for bash-only injection syntax ------------
  # A `!` injection defaults to bash; on a host without Git Bash it falls
  # through to the PowerShell tool, so a bash-only pipeline silently breaks.
  # Declaring `shell:` is the author taking explicit responsibility for the
  # shell (we trust it — no per-shell syntax validation, so `shell: pwsh` with
  # bash-only commands is out of scope). With no declaration, bash-only syntax
  # is a FAIL; portable-looking commands are an unprovable WARN.
  #
  # Bash-only token set is deliberately narrow (tight avoids a false FAIL that
  # blocks; anything missed degrades to the WARN path, never a false negative):
  # `/dev/null` (PowerShell is `$null`), `command -v` (a bash builtin;
  # PowerShell is `Get-Command`), and a pipe into a Unix text tool with no
  # same-named PowerShell cmdlet. `sort`/`tee` are excluded — PowerShell aliases
  # them, so a pipe there is not a clean break.
  # shellcheck disable=SC2016  # single quotes deliberate: \| and $ are literal ERE, not shell expansion
  bash_only_re='/dev/null|(^|[[:space:]])command[[:space:]]+-v([[:space:]]|$)|\|[[:space:]]*(head|tail|grep|sed|awk|cut|tr|wc|xargs|rev|nl|fold|paste|comm|join|column|uniq)([[:space:]]|$)'
  if grep -qE '^shell:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER"; then
    note "shell: declared — dynamic-context injection portability is the author's explicit choice"
  else
    bash_only_hit=""
    for inj in "${INJECTIONS[@]}"; do
      hit="$(grep -oE "$bash_only_re" <<<"$inj" | head -1 || true)"
      if [[ -n "$hit" ]]; then
        bash_only_hit="$hit"
        break
      fi
    done
    if [[ -n "$bash_only_hit" ]]; then
      # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
      err "\`!\` dynamic-context injection uses bash-only syntax ('$bash_only_hit') with no \`shell:\` frontmatter — on a host without Git Bash the injection falls through to the PowerShell tool and breaks. Declare \`shell: bash\` (or write portable commands). See https://code.claude.com/docs/en/skills#inject-dynamic-context"
    else
      # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
      warn "\`!\` dynamic-context injection present with no \`shell:\` frontmatter — the commands look portable but static analysis can't prove it. Declare \`shell:\` explicitly, or confirm the commands run under the host's default shell"
    fi
  fi

  # --- Check 20: injected commands carry a defensive fallback ----------------
  # Injection failure/timeout/stderr semantics are undocumented, so an unguarded
  # command can inline an error string (or nothing) into the prompt. The pinned
  # convention is a `|| <fallback>` on every injected command; match the `||`
  # continuation, not the literal `echo` (`|| printf`/`|| true` are valid too).
  missing_fallback=0
  for inj in "${INJECTIONS[@]}"; do
    [[ "$inj" == *'||'* ]] || missing_fallback=$((missing_fallback + 1))
  done
  if ((missing_fallback > 0)); then
    # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
    warn "$missing_fallback \`!\`-injected command(s) carry no \`|| <fallback>\` — injection failure/timeout/stderr semantics are undocumented, so an unguarded command can inline an error string into the prompt. Add a \`|| echo \"<fallback>\"\` (or shell-appropriate) continuation"
  fi
fi

# --- Check 21: fresh-eyes declaration conformance ---------------------------
# Deterministic proxy for the fresh-eyes rule: a step whose output judges work
# produced in the same context declares either fresh-context delegation or an
# exemption directive IN THE SKILL'S OWN FILES. The judgment-language detector
# is a curated heuristic (WARN-only); directive syntax errors FAIL. Contract
# spec for authors: skills/check/reference/fresh-eyes-declarations.md.
# Scan surface excludes vendor/ (byte-frozen per check 8 — findings would be
# permanently unclearable) and evals/ (fixtures contain arbitrary prose).
# Fenced blocks and inline code spans are ignored by both detectors so docs
# can show literal examples (self-reference guard); a trailing \r is tolerated
# per line (third-party checkouts without eol=lf normalization).
FRESH_EYES_PROXIMITY_LINES=8
# Lowercase POSIX ERE (matched against the lowercased, span-stripped line).
# Seeded from the phrasing of the audited skills and their exempted steps;
# curation policy (triggers + disposition ladder) lives in the reference page.
# [[:space:]] instead of \t: awk -v escape processing differs across awks, a
# POSIX class does not. (^|[^a-z]) boundary guards keep substrings quiet —
# "upgrade your own", "underscore its own" must not read as grade/score.
FRESH_EYES_JUDGE_RE='(^|[^a-z])self[- ](review|audit|assess|score|grade|verif)|(^|[^a-z])(review|verify|assess|grade|score|judge|critique)[a-z]*[[:space:]]+(your|its|their)[[:space:]]+own|(^|[^a-z])spot[- ]check|(^|[^a-z])outcome[[:space:]]+gate|(^|[^a-z])score[[:space:]]+each'

FRESH_EYES_FILES=("$SKILL_MD")
for spoke_dir in context templates reference references actions lanes catalog; do
  [[ -d "$SKILL_DIR/$spoke_dir" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] && FRESH_EYES_FILES+=("$f")
  done < <(find "$SKILL_DIR/$spoke_dir" -type f -name '*.md' \
    -not -path '*/vendor/*' -not -path '*/evals/*' 2>/dev/null | sort)
done

for fe_file in "${FRESH_EYES_FILES[@]}"; do
  fe_rel="${fe_file#"$SKILL_DIR"/}"
  [[ "$fe_file" == "$SKILL_MD" ]] && fe_rel="SKILL.md"
  while IFS= read -r fe_line; do
    fe_kind="${fe_line%% *}"
    fe_ln="${fe_line#* }"
    case "$fe_kind" in
      DIRECTIVE_MALFORMED)
        err "malformed fresh-eyes-exempt directive ($fe_rel:$fe_ln) — expected '<!-- fresh-eyes-exempt: <class> -- <reason> -->' with class deterministic-gate|external-input|deferred (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
        ;;
      DIRECTIVE_NOREASON)
        err "fresh-eyes-exempt directive missing its '-- <reason>' ($fe_rel:$fe_ln) — justification is recorded at the suppression site (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
        ;;
      HIT_BOTH)
        note "fresh-eyes: judgment language at $fe_rel:$fe_ln carries BOTH delegation wording and an exemption directive — contradictory declaration, hand-verify"
        ;;
      HIT_WORDING)
        note "fresh-eyes: judgment language at $fe_rel:$fe_ln — fresh-context delegation declared nearby"
        ;;
      HIT_DIRECTIVE)
        note "fresh-eyes: judgment language at $fe_rel:$fe_ln — exemption directive declared nearby"
        ;;
      HIT_NONE)
        warn "same-context judgment language with no fresh-context delegation or exemption directive within $FRESH_EYES_PROXIMITY_LINES lines ($fe_rel:$fe_ln) — declaration may live in a referenced spoke — hand-verify (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
        ;;
      DIRECTIVE_STALE)
        warn "stale fresh-eyes-exempt directive ($fe_rel:$fe_ln) — no judgment-language hit within $FRESH_EYES_PROXIMITY_LINES lines; the heuristic list, not the directive, may be the gap — verify before removing"
        ;;
      *)
        # Scanner and dispatcher ship together; an unknown record is a bug here,
        # never the audited skill's fault — fail loud, not silent.
        err "check 21 internal error: unknown scan record '$fe_kind' ($fe_rel)"
        ;;
    esac
  done < <(awk -v P="$FRESH_EYES_PROXIMITY_LINES" -v JR="$FRESH_EYES_JUDGE_RE" '
    # Start of file counts as a paragraph break, so an indented block opening on
    # line one is recognized as one.
    BEGIN { fe_blank = 1 }
    # Blockquote nesting depth of a raw line: the number of leading `>` markers,
    # each optionally followed by one space, under the three-space indent cap.
    function fe_depth_of(s,   d) {
      d = 0
      while (match(s, /^ {0,3}> ?/)) { d++; s = substr(s, RSTART + RLENGTH) }
      return d
    }
    # Position in s of the first backtick run of EXACTLY n characters, or 0.
    # Escapes are deliberately ignored: a code span is literal, so a backslash
    # inside one is content and cannot suppress the closer.
    function fe_span_close(s, n,   base) {
      base = 0
      while (match(s, /`+/)) {
        if (RLENGTH == n) return base + RSTART
        base += RSTART + RLENGTH - 1
        s = substr(s, RSTART + RLENGTH)
      }
      return 0
    }
    { sub(/\r$/, "") }
    # YAML frontmatter is not markdown, so nothing in it is a fence, a span, or a
    # directive. Parsing it as markdown let a block-scalar description containing
    # an example fence open `fe_fence` that the closing `---` never ended, which
    # suppressed the whole body and passed the file silently. Skip the region and
    # reset every structural carry at its terminator.
    NR == 1 && /^---[ \t]*$/ { fe_fm = 1; next }
    fe_fm {
      if (/^---[ \t]*$/) {
        fe_fm = 0
        fe_fence = 0; fe_open_pre = 0; sp_open = 0; fe_icode = 0; fe_blank = 1
      }
      next
    }
    # Block-container prefixes come off before anything else looks at the line, so
    # container content parses exactly like top-level content. Markers interleave
    # (`> - ```), so strip until neither form matches.
    #
    # Inside a fence the strip applies only when the OPENER itself carried a
    # prefix — otherwise a nested `> ``` ` in the quoted example a fence itself
    # contains becomes a closer and leaks the block.
    #
    # NOTE: this awk program is a single-quoted shell string. An apostrophe in a
    # comment here terminates it and breaks the script — keep prose apostrophe-free.
    {
      fe_raw = $0
      # A container-nested fence dies with its container. CommonMark ends a fence
      # inside a blockquote or list item when that container ends, but this fence
      # state is a single global flag: without the reset an unclosed
      # `> ```markdown` swallows every following top-level line, and a malformed
      # directive in later prose silently PASSes.
      if (fe_fence && fe_open_pre) {
        if (fe_open_bq) {
          # A blockquote marker must repeat on every line — a fenced block inside
          # a quote takes no lazy continuation, and a blank line ends the quote.
          # DEPTH matters, not mere presence: a fence opened at "> > " lives in the
          # inner quote, so a later depth-1 line has left that quote and ends the
          # fence even though it still carries a marker.
          if (fe_depth_of(fe_raw) < fe_open_depth) { fe_fence = 0; fe_open_pre = 0 }
        } else {
          # A list item continues by indentation to its content column: a blank
          # line stays inside the item, a dedent ends it.
          fe_ind = 0
          while (substr(fe_raw, fe_ind + 1, 1) == " ") fe_ind++
          if (fe_raw !~ /^[ \t]*$/ && fe_ind < fe_open_ind) { fe_fence = 0; fe_open_pre = 0 }
        }
      }
      if (!fe_fence || fe_open_pre) {
        do {
          fe_pre = $0
          sub(/^ {0,3}> ?/, "", $0)
          sub(/^ {0,3}([-*+]|[0-9]{1,9}[.)])[ \t]+/, "", $0)
        } while ($0 != fe_pre)
      }
      fe_stripped = ($0 != fe_raw)
      fe_bq_depth = fe_depth_of(fe_raw)
      fe_strip_len = length(fe_raw) - length($0)
    }
    # Fence matching. What this scanner models, what it does not attempt, and what
    # it does when it cannot tell are stated once in the Parsing contract section
    # of skills/check/reference/fresh-eyes-declarations.md — that doc is the claim
    # this code implements; do not restate it here.
    /^ {0,3}(```+|~~~+)/ {
      fe_run = $0
      sub(/^ */, "", fe_run)
      fe_char = substr(fe_run, 1, 1)
      fe_len = 0
      while (substr(fe_run, fe_len + 1, 1) == fe_char) fe_len++
      fe_info = substr(fe_run, fe_len + 1)
      # A fence line is markdown structure, never the blank line or indented run
      # an indented code block needs, so it resets that tracking either way.
      fe_icode = 0; fe_blank = 0
      if (fe_fence) {
        if (fe_char == fe_open_char && fe_len >= fe_open_len \
            && fe_info ~ /^[ \t]*$/) fe_fence = 0
        next
      }
      # A backtick fence opener cannot carry backticks in its info string —
      # such a line is ordinary prose, so it falls through to the scanners
      # instead of opening a fence.
      if (!(fe_char == "`" && index(fe_info, "`"))) {
        # A fence interrupts the paragraph, so any code span still waiting for
        # its closer expires here rather than blinding the first paragraph
        # after the fence closes.
        fe_fence = 1; fe_open_char = fe_char; fe_open_len = fe_len; sp_open = 0
        fe_open_pre = fe_stripped; fe_open_depth = fe_bq_depth
        fe_open_bq = (fe_bq_depth > 0); fe_open_ind = fe_strip_len
        next
      }
    }
    fe_fence { next }
    {
      line = $0
      # A code span lives inside one paragraph, so a blank line expires a span
      # still waiting for its closer — otherwise one stray backtick would blind
      # the detectors for the rest of the file.
      if (line ~ /^[ \t]*$/) sp_open = 0
      # Escapes and code spans resolve in ONE left-to-right pass because
      # CommonMark couples them: escapes apply only outside a span, and a span is
      # literal inside. Two independent passes cannot express that — either pass
      # order breaks one of the two rules.
      sp_keep = ""
      # A span opened on an earlier line: spans may cross a newline, so scan for
      # the closer first. With no run of exactly the opener length, the whole
      # line is span content and never reaches the detectors.
      if (sp_open) {
        sp_at = fe_span_close(line, sp_open)
        if (!sp_at) next
        line = substr(line, sp_at + sp_open)
        sp_keep = " "
        sp_open = 0
      }
      while (1) {
        if (!match(line, /[\\`]/)) { sp_keep = sp_keep line; break }
        sp_p = RSTART
        sp_keep = sp_keep substr(line, 1, sp_p - 1)
        if (substr(line, sp_p, 1) == "\\") {
          # Only the three characters this scanner keys on need escape handling,
          # which makes the set complete for it. Any other backslash is ordinary
          # text and must survive, or prose like a Windows path would lose the
          # character after it.
          sp_next = substr(line, sp_p + 1, 1)
          if (sp_next == "`" || sp_next == "<" || sp_next == "\\") {
            sp_keep = sp_keep "  "
            line = substr(line, sp_p + 2)
          } else {
            sp_keep = sp_keep "\\"
            line = substr(line, sp_p + 1)
          }
          continue
        }
        # An opening backtick run pairs with the next run of EXACTLY the same
        # length; a shorter or longer run inside is span content, so a naive
        # /`[^`]*`/ would split a ``…`` span and expose its content.
        sp_len = 0
        while (substr(line, sp_p + sp_len, 1) == "`") sp_len++
        line = substr(line, sp_p + sp_len)
        sp_at = fe_span_close(line, sp_len)
        # No closer on this line: the span may continue on the next one, so carry
        # the opener length forward and drop the remainder as span content. The
        # carry is optimistic — a run that never closes before the paragraph ends
        # masks content CommonMark would call literal — but the tradeoff is
        # deliberate: masking risks missing a declaration, whereas scanning risks
        # a blocking failure on legitimate code-span text.
        if (!sp_at) { sp_open = sp_len; break }
        sp_keep = sp_keep " "
        line = substr(line, sp_at + sp_len)
      }
      line = sp_keep
      # Structural ambiguity: a four-space-indented line here is either an
      # indented code block or a list-item continuation, and telling those
      # apart needs a block parser this scanner does not have. Rather than
      # guess, it declines its HARD verdicts on such a line — see the parsing
      # contract in skills/check/reference/fresh-eyes-declarations.md for the
      # asymmetry that makes declining the safe direction.
      if (line ~ /^[ \t]*$/) fe_blank = 1
      else {
        fe_ind2 = 0
        if (line ~ /^\t/) fe_ind2 = 4
        else while (substr(line, fe_ind2 + 1, 1) == " ") fe_ind2++
        fe_icode = (fe_ind2 >= 4 && (fe_icode || fe_blank))
        fe_blank = 0
      }
      # Classify each directive on the line independently, bounded at its own
      # `-->`. Testing the whole line let a valid directive elsewhere on it lend
      # its class and reason to a malformed neighbour, so an unknown-class
      # suppression could hide beside a well-formed one and never FAIL.
      dir_rest = line
      # The directive name needs a terminator after it, or a prefix-only match
      # reads an ordinary comment about `fresh-eyes-exemption` as a directive and
      # FAILs the skill on prose.
      while (match(dir_rest, /<!--[ \t]*fresh-eyes-exempt([ \t]|:|-->)/)) {
        dir_one = substr(dir_rest, RSTART)
        dir_rest = substr(dir_rest, RSTART + RLENGTH)
        dir_end = index(dir_one, "-->")
        if (dir_end) dir_one = substr(dir_one, 1, dir_end + 2)
        dir_n++
        d[dir_n] = NR
        damb[dir_n] = fe_icode
        if (dir_one ~ /<!--[ \t]*fresh-eyes-exempt:[ \t]*(deterministic-gate|external-input|deferred)[ \t]+--[ \t]+[^ \t].*-->/) {
          dt[dir_n] = "valid"
        } else if (dir_one ~ /<!--[ \t]*fresh-eyes-exempt:[ \t]*(deterministic-gate|external-input|deferred)[ \t]*(--[ \t]*)?-->/) {
          dt[dir_n] = "noreason"
        } else {
          dt[dir_n] = "malformed"
        }
      }
      # Form 1 is VISIBLE PROSE by contract, so an HTML comment cannot carry it:
      # a hidden `<!-- dispatch this to a fresh-context agent -->` would be exactly
      # the parallel marker Form 1 exists to rule out, and it was satisfying the
      # delegation detector. Comments come off only AFTER the directives above are
      # classified, since a directive IS a comment. An unterminated `<!--` drops
      # the rest of its own line and no further — carrying comment state across
      # lines would let one stray opener blind the detectors for the whole file.
      cm_keep = ""
      while ((cm_p = index(line, "<!--")) > 0) {
        cm_keep = cm_keep substr(line, 1, cm_p - 1) " "
        line = substr(line, cm_p + 4)
        cm_e = index(line, "-->")
        if (!cm_e) { line = ""; break }
        line = substr(line, cm_e + 3)
      }
      line = cm_keep line
      low = tolower(line)
      # Delegation wording needs a worker actually named on the line — bare
      # "in a fresh context" prose assigns no one and does not declare. Both
      # halves match as whole words with their inflections, so embedded stems
      # cannot satisfy the requirement: "agentless" is not a worker, and
      # "Refresh context" is not the fresh-context wording.
      if (low ~ /(^|[^a-z0-9_])fresh[- ]context([^a-z0-9_]|$)/ \
          && low ~ /(^|[^a-z0-9_])((sub-?)?agents?|workers?|advisors?|reviewers?|verifiers?|dispatch(es|ed|ing)?|delegat(e|es|ed|ing|ion|ions))([^a-z0-9_]|$)/) {
        word_n++; w[word_n] = NR
      }
      if (low ~ JR) { judge_n++; j[judge_n] = NR }
    }
    END {
      # A directive whose structural context was ambiguous yields no hard
      # verdict: both of these FAIL the skill, and failing an author on a
      # parser artifact is worse than missing one malformed directive.
      for (i = 1; i <= dir_n; i++) {
        if (damb[i]) continue
        if (dt[i] == "noreason") printf "DIRECTIVE_NOREASON %d\n", d[i]
        else if (dt[i] == "malformed") printf "DIRECTIVE_MALFORMED %d\n", d[i]
      }
      for (i = 1; i <= judge_n; i++) {
        hasw = 0; hasd = 0
        for (k = 1; k <= word_n; k++) if (w[k] >= j[i] - P && w[k] <= j[i] + P) hasw = 1
        # An ambiguous directive cannot satisfy a judgment step either: if the
        # scanner is not confident it is live markdown, a literal example inside
        # an indented code block would otherwise silence the WARN it deserves.
        for (k = 1; k <= dir_n; k++) if (dt[k] == "valid" && !damb[k] && d[k] >= j[i] - P && d[k] <= j[i] + P) hasd = 1
        if (hasw && hasd) printf "HIT_BOTH %d\n", j[i]
        else if (hasw) printf "HIT_WORDING %d\n", j[i]
        else if (hasd) printf "HIT_DIRECTIVE %d\n", j[i]
        else printf "HIT_NONE %d\n", j[i]
      }
      for (i = 1; i <= dir_n; i++) {
        # Ambiguous placement also withholds the stale WARN: the scanner is not
        # confident the directive is live markdown, so it makes no claim either way.
        if (dt[i] != "valid" || damb[i]) continue
        used = 0
        for (k = 1; k <= judge_n; k++) if (j[k] >= d[i] - P && j[k] <= d[i] + P) used = 1
        if (!used) printf "DIRECTIVE_STALE %d\n", d[i]
      }
    }
  ' "$fe_file")
done

# --- Summary ---------------------------------------------------------------

printf '\n'
if ((FAILED > 0)); then
  printf 'CHECK-SKILL %s: FAIL — %d error(s), %d warning(s)\n' "$SKILL_NAME" "$FAILED" "$WARNINGS" >&2
  exit 1
fi
printf 'CHECK-SKILL %s: PASS — 0 errors, %d warning(s)\n' "$SKILL_NAME" "$WARNINGS"
exit 0
