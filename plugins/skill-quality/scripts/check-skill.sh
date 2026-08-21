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
#   bash check-skill.sh [--require-evals] <skill-name>
#   bash check-skill.sh --help
#
# --require-evals (or CHECK_SKILL_REQUIRE_EVALS=1) FAILs when evals/evals.json
# is absent for any skill shape. Without it, check 14 WARNs only on
# action-router-shaped skills — the legacy fleet posture.
#
# Skills root resolution (first hit wins):
#   1. CHECK_SKILL_SKILLS_ROOT env var (explicit override)
#   2. ${CLAUDE_PROJECT_DIR}/.claude/skills (plugin runtime)
#   3. <git-root>/.claude/skills (default, when cwd is inside a git repo)
#
# A git repository is OPTIONAL. Marketplace plugin-cache installs are plain
# directory trees (no .git). When cwd is not inside a git repo, set
# CHECK_SKILL_SKILLS_ROOT (or CLAUDE_PROJECT_DIR) and the non-git checks still
# run; git-backed checks (3, 8, 9, 13) skip with a note.
#
# Base ref for the git-backed diff checks (3, 8, 9):
#   CHECK_SKILL_BASE_REF (default HEAD). These checks diff the WORKING TREE
#   against this ref, so the default catches an uncommitted rewrite. For a
#   post-commit audit (where HEAD == tree hides an already-committed change),
#   run on a clean tree with CHECK_SKILL_BASE_REF pointing before the change
#   (e.g. HEAD^ or a merge-base). Ignored when not in a git repo.
#
# NOT covered here: the SHARED listing budget (skillListingBudgetFraction) that
# every loaded skill draws from together, a different cross-skill limit from
# check 2's per-skill entry cap below. See the companion
# check-listing-budget.sh for that aggregate report (always advisory).
#
# Checks:
#   1. Frontmatter parses; description present; a declared name matches the dir
#      (and, in a plugin skill, WARNs as redundant)
#   2. description + when_to_use <= 1536 chars (per-skill listing-entry cap;
#      counts the literal " - " joiner the harness inserts when when_to_use is
#      populated)
#   3. Trigger-keyword preservation vs the base ref (skipped for new skills;
#      a phrase moved verbatim to a sibling skill's listing text — one the
#      sibling did not carry at the base ref — WARNs, since the marketplace
#      listing still routes it; lost phrases and coincidental overlap FAIL)
#   4. SKILL.md < 500 lines (hard cap)
#   5. Backtick-cited skill-internal supporting files resolve (a path that misses
#      here but resolves under a SIBLING skill also names that sibling and the
#      `${CLAUDE_PLUGIN_ROOT}/skills/<sibling>/…` cross-skill form, without
#      dropping the hand-verify caveat — the hit may be a name collision)
#   6. markdownlint clean (markdownlint-cli2; WARN-skip if npx absent)
#   7. scripts/*.test.sh pass where present
#   8. vendor/ byte-identical vs HEAD, unless paired with an upstream-version
#      bump (a legitimate maintainer-run sync) (vendor-backed skills only)
#   9. Stale-tracking metadata keys preserved vs HEAD (upstream-version/synced/upstream-sha)
#  10. SKILL.md <= 200 lines soft target (WARN; progressive disclosure)
#  11. Gotchas surface present (WARN; inline `## Gotchas` or context|reference/gotchas.md)
#  12. description carries "Use when" trigger phrasing, single-quoted (WARN)
#  13. No committed cache/build artifacts (__pycache__, *.pyc, node_modules) (FAIL)
#  14. evals/evals.json presence (WARN for action-router shape; FAIL with
#      --require-evals / CHECK_SKILL_REQUIRE_EVALS=1 for any shape)
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
#  22. metadata.summary <= 100 Unicode codepoints (FAIL; the key is
#      the generated skill cheat sheet's row source — the cap keeps rows
#      scannable. Absent key = no finding)
#  23. Completion-criteria signal on a 3+ step numbered procedure (WARN)
#  24. disable-model-invocation stated explicitly (FAIL in plugins/; WARN
#      elsewhere)
#  25. Description/verb-contract polarity: read-only vs mutate (WARN;
#      description lead vs Naming verb vs body; #2896)
#
# Notes (static, git-diff-based design):
#   - Checks 3/8/9 diff the working tree against CHECK_SKILL_BASE_REF (default
#     HEAD) when a git repo is available. Outside a repo (plugin-cache install)
#     those checks — and check 13's committed-artifact scan — skip with a note;
#     every other check still runs. The default catches an uncommitted rewrite;
#     a post-commit audit sets the base ref before the change and runs on a
#     clean tree (see above).
#   - Frontmatter must open with `---` on line 1; content before the fence is
#     not treated as frontmatter.
#   - A block-scalar `description: |` / `>-` is unfolded before checks 2/3/12/25,
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

REQUIRE_EVALS="${CHECK_SKILL_REQUIRE_EVALS:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --require-evals)
    REQUIRE_EVALS=1
    shift
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf 'Error: unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  *)
    break
    ;;
  esac
done

# Git is optional. Plugin-cache installs are plain trees; non-git checks still
# run when CHECK_SKILL_SKILLS_ROOT (or CLAUDE_PROJECT_DIR) points at them.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
HAVE_GIT=0
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  HAVE_GIT=1
fi

# shellcheck source=./skill-frontmatter.sh
source "$SCRIPT_DIR/skill-frontmatter.sh"

# Base ref for the git-backed diff checks (3, 8, 9) — see the header. Default
# HEAD (uncommitted-rewrite case); an explicit ref enables a post-commit audit.
# Validated only when a git repo is present; ignored otherwise.
BASE_REF="${CHECK_SKILL_BASE_REF:-HEAD}"
if [[ "$HAVE_GIT" == 1 && "$BASE_REF" != "HEAD" ]] &&
  ! git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null 2>&1; then
  printf 'Error: CHECK_SKILL_BASE_REF=%s is not a valid commit\n' "$BASE_REF" >&2
  exit 2
fi

SKILL_NAME="${1:?Usage: check-skill.sh [--require-evals] <skill-name>}"

# Resolve the skills root without baking a repo layout (convention-resolution
# ladder): explicit override, then plugin project dir, then git-root default.
# Outside a git repo the git-root step is unavailable — require an explicit
# root (or CLAUDE_PROJECT_DIR) rather than aborting solely for missing VCS.
if [[ -n "${CHECK_SKILL_SKILLS_ROOT:-}" ]]; then
  SKILLS_ROOT="$CHECK_SKILL_SKILLS_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  SKILLS_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
elif [[ "$HAVE_GIT" == 1 ]]; then
  SKILLS_ROOT="$REPO_ROOT/.claude/skills"
else
  printf 'Error: not in a git repo and no skills root set — set CHECK_SKILL_SKILLS_ROOT (or CLAUDE_PROJECT_DIR), or run from inside a git repository\n' >&2
  exit 2
fi

# Anchor a relative skills root to the project root. The setup action persists a
# project-relative path; if the skill is invoked from a subdirectory a relative
# root would otherwise resolve against the cwd and miss the skills.
if [[ "$SKILLS_ROOT" != /* && ! "$SKILLS_ROOT" =~ ^[A-Za-z]:[\\/] ]]; then
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    SKILLS_ROOT="$CLAUDE_PROJECT_DIR/$SKILLS_ROOT"
  elif [[ "$HAVE_GIT" == 1 ]]; then
    SKILLS_ROOT="$REPO_ROOT/$SKILLS_ROOT"
  else
    printf 'Error: relative skills root %s needs CLAUDE_PROJECT_DIR or a git repository to anchor against\n' "$SKILLS_ROOT" >&2
    exit 2
  fi
fi

SKILL_DIR="$SKILLS_ROOT/$SKILL_NAME"
SKILL_MD="$SKILL_DIR/SKILL.md"

# SKILL_REL is the skill dir relative to the git root, so the git-backed checks
# (3, 8, 9, 13) address the right tree entry even when the skills root is not
# the conventional .claude/skills. Ask git for the prefix rather than
# string-stripping REPO_ROOT — on Git Bash `git rev-parse` and `pwd` can differ
# in drive-letter case / slash form, which would silently break the strip.
# Empty when not in a git repo, or when the skill dir is outside the repo
# (git-backed checks then no-op).
SKILL_REL=""
if [[ "$HAVE_GIT" == 1 ]]; then
  SKILL_REL="$(git -C "$SKILL_DIR" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"
  SKILL_REL="${SKILL_REL%/}"
fi

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

# Sorted-unique trigger phrases in a frontmatter block's LISTING text — the
# description + when_to_use pair the harness assembles into one listing entry.
# Reads the frontmatter as a string so every caller (working tree, base ref,
# sibling skill) derives triggers the same way.
fm_listing_triggers() {
  local fm="$1"
  printf '%s\n%s\n' \
    "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$fm")")" \
    "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$fm")")" |
    skill_frontmatter::extract_triggers
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

# Is this skill bundled in a PLUGIN, or a loose skill under some skills root?
# A plugin manifest two levels up (<plugin>/skills/<skill>/) is the marker.
# Several checks branch on it — check 1 (a declared `name` also registers a bare
# alias there) and check 5 (a cross-skill citation anchors at
# ${CLAUDE_PLUGIN_ROOT}, which is undefined outside a plugin) — so the layout
# convention is asserted in ONE place rather than restated per call site.
IS_PLUGIN_SKILL=0
PLUGIN_DIR=""
[[ -f "$SKILL_DIR/../../.claude-plugin/plugin.json" ]] && IS_PLUGIN_SKILL=1
if [[ "$IS_PLUGIN_SKILL" == 1 ]]; then
  PLUGIN_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
fi

# --- Check 1: frontmatter parses; description present; declared name matches --

FRONTMATTER="$(skill_frontmatter::extract <"$SKILL_MD")"
if [[ -z "$FRONTMATTER" ]]; then
  err "no YAML frontmatter block found (expected content between two '---' fences)"
else
  grep -qE '^description:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER" || err "frontmatter missing 'description:'"

  # `name` is optional and defaults to the directory name
  # (https://code.claude.com/docs/en/skills#frontmatter-reference), so the
  # checker resolves a skill by its directory either way. A DIVERGENT name is
  # the defect this branch exists for: it silently relocates the invocation the
  # doctrine says the skill has. A matching one is merely redundant — and in a
  # plugin skill, not inert (see the warning below).
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
  elif [[ -n "$CUR_NAME" && "$IS_PLUGIN_SKILL" == 1 ]]; then
    # In a PLUGIN skill a matching `name` is not inert: a declared name also
    # answers to the bare `/<name>` unless another command owns that token
    # (https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name),
    # and the picker appends that alias in parentheses to any row whose typed
    # prefix matches it — `/plugin:deploy (deploy)` (observed in 2.1.225).
    # Omitting the field leaves the namespaced command identical and drops both.
    # Advisory, not a defect: the bare alias is a legitimate thing to want, and
    # declaring a matching name is the only way to register it.
    warn "frontmatter name '$CUR_NAME' repeats the plugin skill's directory — omit it unless the bare /$CUR_NAME alias is wanted"
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
# Working-tree listing triggers, derived once: checks 3 and 12 both read them.
CUR_TRIG="$(printf '%s\n%s\n' "$CUR_DESC" "$CUR_WTU" | skill_frontmatter::extract_triggers)"
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

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — trigger-keyword preservation (check 3) skipped"
elif git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
  BASE_FM_3="$(git -C "$REPO_ROOT" show "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
  BASE_TRIG="$(fm_listing_triggers "$BASE_FM_3")"
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
      # A sibling's working-tree listing text is the same for every missing
      # phrase, so read and parse each SKILL.md once here rather than once per
      # phrase (the per-phrase scan below then only walks the cached arrays).
      # Glob order is preserved, so the first-genuine-host tie-break is unchanged.
      SIB_NAMES=()
      SIB_TRIGS=()
      for other_md in "$SKILLS_ROOT"/*/SKILL.md; do
        [[ -f "$other_md" ]] || continue
        [[ "$other_md" == "$SKILL_MD" ]] && continue
        sib_path="${other_md%/SKILL.md}"
        SIB_NAMES+=("${sib_path##*/}")
        SIB_TRIGS+=("$(fm_listing_triggers "$(skill_frontmatter::extract <"$other_md")")")
      done
      LOST=""
      while IFS= read -r phrase; do
        [[ -n "$phrase" ]] || continue
        MOVE_HOST=""
        for ((sib_i = 0; sib_i < ${#SIB_NAMES[@]}; sib_i++)); do
          printf '%s\n' "${SIB_TRIGS[$sib_i]}" | grep -qxF -- "$phrase" || continue
          OTHER_NAME="${SIB_NAMES[$sib_i]}"
          OTHER_REL="${SKILLS_REL_PARENT:+$SKILLS_REL_PARENT/}$OTHER_NAME"
          if git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$OTHER_REL/SKILL.md" 2>/dev/null; then
            OTHER_BASE_TRIG="$(fm_listing_triggers \
              "$(git -C "$REPO_ROOT" show "$BASE_REF:$OTHER_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)")"
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
#
# DECIDED, do not re-litigate (#2179 deferred this as "a separate call"; settled
# here). Narrowing extraction to markdown-link targets only — dropping the
# backtick branch — was rejected on measurement, not taste. Two premises usually
# offered for narrowing are both false:
#
#   1. "It matches bare paths in prose." It does not. Both generators below are
#      delimited — backtick-wrapped, or a `](…)` link target — and both are
#      scoped to the INTERNAL_DIRS allowlist. Naked prose never matches.
#   2. "The backtick branch is redundant with the link branch." Measured over
#      the 196-skill corpus: 122 unique backtick-form refs across 39 skills have
#      no link form anywhere in the same SKILL.md, so narrowing would drop them
#      from coverage entirely. All 122 resolve to a real file today, i.e. the
#      backtick branch contributes 122 refs' worth of real coverage at zero
#      false positives on the current corpus.
#
# The false-positive risk that motivated the proposal is real but latent, not
# observed: a generic path in an illustrative example could collide. That is
# handled by message wording — every failure below carries `hand-verify the line
# before fixing, may be an illustrative example` — rather than by deleting
# coverage of 39 skills. Reopen only if a false positive is actually observed.
INTERNAL_DIRS='context|templates|scripts|reference|references|actions|evals|lanes|catalog|vendor'
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  resolve_base="$SKILL_DIR"
  check_ref="$ref"
  # shellcheck disable=SC2016  # single quotes deliberate: ${CLAUDE_PLUGIN_ROOT} is a literal placeholder prefix
  if [[ "$ref" == '${CLAUDE_PLUGIN_ROOT}/'* ]]; then
    # shellcheck disable=SC2016
    check_ref="${ref#'${CLAUDE_PLUGIN_ROOT}/'}"
    if [[ "$IS_PLUGIN_SKILL" != 1 || -z "$PLUGIN_DIR" ]]; then
      note "check-5 skip (plugin-root placeholder outside a plugin): $ref"
      continue
    fi
    resolve_base="$PLUGIN_DIR"
  fi
  if [[ "$HAVE_GIT" == 1 ]] && git -C "$REPO_ROOT" check-ignore -q "$resolve_base/$check_ref" 2>/dev/null; then
    note "check-5 skip (gitignored runtime path): $check_ref"
    continue
  fi
  if [[ ! -e "$resolve_base/$check_ref" ]]; then
    ref_line="$(grep -nF "$ref" "$SKILL_MD" 2>/dev/null | head -1 | cut -d: -f1)"
    # A path that misses here but DOES resolve under a SIBLING skill of the same
    # skills root is most often a cross-skill citation written in the
    # skill-internal form — not a missing file. Every bare path in this check
    # resolves against the CITING skill's dir, so the bare form is wrong either
    # way and still FAILs; what changes is the message. The default wording
    # sends the author looking for the file under their own skill, where it will
    # never be — naming the host sibling and the anchored form that works is the
    # difference between a dead end and a one-line fix.
    #
    # The sibling hit is EVIDENCE, not proof: this check deliberately extracts
    # inline-code refs as well as link targets, so a generic path (`scripts/run.sh`) can
    # collide with an unrelated same-named sibling file. The wording therefore
    # stays conditional and keeps the hand-verify instruction the default
    # message carries — a coincidental name match and an illustrative example
    # are both still live readings. Glob order is sorted, so a path present
    # under more than one sibling names the first deterministically.
    REF_HOST=""
    for other_md in "$SKILLS_ROOT"/*/SKILL.md; do
      [[ -f "$other_md" ]] || continue
      [[ "$other_md" == "$SKILL_MD" ]] && continue
      if [[ -e "${other_md%/SKILL.md}/$check_ref" ]]; then
        REF_HOST="${other_md%/SKILL.md}"
        REF_HOST="${REF_HOST##*/}"
        break
      fi
    done
    if [[ -z "$REF_HOST" ]]; then
      if [[ "$resolve_base" == "$PLUGIN_DIR" ]]; then
        err "broken plugin-root ref: $ref (no such file under the plugin root; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example)"
      else
        err "broken skill-internal ref: $ref (no such file under the skill dir; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example)"
      fi
    else
      # Plugin-shaped root: bundled plugin assets are anchored at the plugin
      # root, so that is the form to name. Outside a plugin
      # ${CLAUDE_PLUGIN_ROOT} is undefined, so name the layout-free
      # sibling-relative form rather than advertise a variable that resolves to
      # nothing.
      if [[ "$IS_PLUGIN_SKILL" == 1 ]]; then
        ref_fix="\${CLAUDE_PLUGIN_ROOT}/skills/$REF_HOST/$check_ref"
      else
        ref_fix="../$REF_HOST/$check_ref"
      fi
      err "broken skill-internal ref: $ref (no such file under the skill dir; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example). A file with that path DOES exist under sibling skill '$REF_HOST': if that is the file meant, this is a cross-skill citation, and a bare path always resolves against the CITING skill's dir — write it as $ref_fix. If the names merely collide, the ref is unrelated to that sibling."
    fi
  fi
done < <(
  {
    grep -oE "\`(\$\{CLAUDE_PLUGIN_ROOT\}/)?($INTERNAL_DIRS)/[A-Za-z0-9._/-]+\`" "$SKILL_MD" 2>/dev/null | tr -d '`'
    grep -oE "\]\((\$\{CLAUDE_PLUGIN_ROOT\}/)?($INTERNAL_DIRS)/[A-Za-z0-9._/#-]+\)" "$SKILL_MD" 2>/dev/null |
      sed -E 's/^\]\(//; s/\)$//; s/#.*$//'
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
    # Output is captured rather than discarded so a FAILURE can be replayed. A test
    # that only ever reports "it failed" is undiagnosable wherever it cannot be
    # reproduced by hand — a gate whose one CI-visible signal is its own name sends
    # the reader guessing at environment differences instead of reading the case that
    # broke. Success stays silent: the reason to suppress was log noise, and that
    # reason does not apply to the run that just went red.
    test_out=""
    if test_out="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_PREFIX \
      bash "$test_sh" 2>&1)"; then
      note "script test passed: ${test_sh#"$SKILL_DIR"/}"
    else
      err "script test failed: ${test_sh#"$SKILL_DIR"/}"
      printf '%s\n' "$test_out" >&2
    fi
  done < <(find "$SKILL_DIR/scripts" -name '*.test.sh' -type f 2>/dev/null | sort)
fi

# --- Check 8: vendor/ byte-identical vs HEAD (vendor-backed only) ----------

# Only meaningful when the skill has a HEAD baseline: a brand-new vendored skill
# staged before a pre-commit run has no prior vendor/ to preserve, so its staged
# files must not read as "changed vs HEAD". Outside a git repo there is no
# baseline to compare — skip rather than abort the whole gate.
if [[ "$HAVE_GIT" != 1 ]]; then
  [[ -d "$SKILL_DIR/vendor" ]] && note "not in a git repo — vendor byte-identity (check 8) skipped"
elif [[ -d "$SKILL_DIR/vendor" ]] && git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
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

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — stale-tracking metadata (check 9) skipped"
elif git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null; then
  BASE_FM="$(git -C "$REPO_ROOT" show "$BASE_REF:$SKILL_REL/SKILL.md" 2>/dev/null | skill_frontmatter::extract)"
  for key in upstream-version synced upstream-sha; do
    if grep -qE "^[[:space:]]*$key:" <<<"$BASE_FM"; then
      grep -qE "^[[:space:]]*$key:" <<<"$FRONTMATTER" ||
        err "metadata key '$key' present at $BASE_REF but dropped (stale-tracking metadata for a vendored skill)"
    fi
  done
fi

# --- Check 10: SKILL.md soft line target (progressive disclosure) ----------

if ((LINE_COUNT > LINE_SOFT_CAP && LINE_COUNT < LINE_HARD_CAP)); then
  warn "SKILL.md is $LINE_COUNT lines (soft target $LINE_SOFT_CAP — consider pushing detail to progressive-disclosure spokes)"
fi

# --- Check 11: Gotchas surface present --------------------------------------

if ! grep -qEi '^##+[[:space:]]+(gotchas|quirks)' "$SKILL_MD" &&
  [[ ! -f "$SKILL_DIR/context/gotchas.md" ]] &&
  [[ ! -f "$SKILL_DIR/reference/gotchas.md" ]] &&
  [[ ! -f "$SKILL_DIR/references/gotchas.md" ]]; then
  warn "no Gotchas surface (inline '## Gotchas' or context/gotchas.md) — confirm the skill has no observed failure history"
fi

# --- Check 12: description carries trigger phrasing --------------------------

# The standing 4-skill warning floor is INTENTIONAL, and no dmi carve-out is
# wanted here (#2181 left them; re-reviewed and confirmed). `discipline:wait-what`,
# `firecrawl:update`, `playbooks:update`, and `github:setup` are all
# `disable-model-invocation: true`, and upstream states outright that for that
# setting the "Description not in context, full skill loads when you invoke"
# (skills.md frontmatter-behavior table, verified 2026-08-10) — so trigger
# phrasing on them can never route anything. Each was re-checked for a STRANDED
# phrase (one a user would type that no model-invocable skill can receive) and
# none is stranded: the two `update` skills are maintainer-only with
# consumer-facing siblings that carry the phrases, `github:setup` is a declared
# slash-command-only contract with `advise`/`audit` model-invocable beside it,
# and `wait-what` triggers on self-observation the model cannot detect. Adding a
# dmi exemption branch would suppress a warning that is doing no harm while
# hiding the kindle-dedrm failure mode (a phrase reachable only from a dmi-true
# skill), so the warning stays and the exemptions stay documented instead.
if [[ -n "$CUR_DESC" ]]; then
  CUR_TRIG_WTU="$(printf '%s\n' "$CUR_WTU" | skill_frontmatter::extract_triggers)"
  if ! grep -qi 'use when' <<<"$CUR_DESC$CUR_WTU" && [[ -z "$CUR_TRIG_WTU" ]]; then
    warn "description has no 'Use when:' trigger phrasing — a description is a trigger spec, not a summary"
  elif [[ -z "$CUR_TRIG" ]]; then
    warn "'Use when:' triggers are not single-quoted — drop-regression protection (check 3) tracks only 'quoted' phrases; single-quote each trigger phrase to cover it"
  fi
fi

# --- Check 13: no committed cache/build artifacts ----------------------------

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — committed-artifact scan (check 13) skipped"
else
  CACHE_HITS="$(git -C "$REPO_ROOT" ls-files "$SKILL_REL" 2>/dev/null | grep -E '__pycache__|\.pyc$|/node_modules/' || true)"
  if [[ -n "$CACHE_HITS" ]]; then
    err "committed cache/build artifact(s) under the skill dir: $(printf '%s' "$CACHE_HITS" | head -3 | tr '\n' ' ')"
  fi
fi

# --- Check 14: evals/evals.json presence -------------------------------------
# Legacy fleet: action-router shape without evals WARNs (evals warranted, not
# mandatory). Changed-skill CI passes --require-evals so any touched SKILL.md
# must ship evals/evals.json regardless of shape.

if [[ ! -f "$SKILL_DIR/evals/evals.json" ]]; then
  if [[ "$REQUIRE_EVALS" == "1" ]]; then
    err "skill ships no evals/evals.json — required when the skill is new or its SKILL.md changed"
  elif grep -qE '^##+[[:space:]]+Actions?([^[:alnum:]_]|$)' "$SKILL_MD"; then
    warn "action-router-shaped skill with no evals/evals.json — check whether the skill warrants triggering evals"
  fi
fi

# --- Check 15: companion spoke dirs referenced from the hub -------------------

for spoke_dir in context reference references templates lanes actions; do
  [[ -d "$SKILL_DIR/$spoke_dir" ]] || continue
  grep -q "$spoke_dir/" "$SKILL_MD" ||
    warn "orphan spoke: $spoke_dir/ exists but SKILL.md never references it (progressive-disclosure routing gap)"
done

# --- Check 16: metadata.category (informational) ------------------------------

if [[ -n "$FRONTMATTER" ]] && ! grep -A8 '^metadata:' <<<"$FRONTMATTER" | grep -q 'category:'; then
  note "no metadata.category in frontmatter (optional — category not machine-readable)"
fi

# --- Check 17: vendor sync age ------------------------------------------------

if [[ -d "$SKILL_DIR/vendor" ]]; then
  SYNCED_VAL="$(awk '/^metadata:/{m=1;next} m && /^[a-zA-Z]/{m=0} m && /^[[:space:]]+synced:/{print $2;exit}' <<<"$FRONTMATTER" | tr -d "\"'")"
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
  line="${line#"${line%%[![:space:]]*}"}" # ltrim
  line="${line#\$ }"                      # strip a leading `$ ` prompt

  # Shell metacharacters that can introduce a second command or a write. `<(`
  # and `>(` process substitution are caught by the `<`/`>` tests.
  case "$line" in
  *'>'* | *'<'* | *';'* | *'&'*) return 1 ;;
  *) ;;
  esac
  # shellcheck disable=SC2016  # single quotes are deliberate: '$(' is a literal glob, not a shell expansion
  case "$line" in *'$('*) return 1 ;; *) ;; esac # $(...) command substitution
  case "$line" in *'`'*) return 1 ;; *) ;; esac  # backtick command substitution
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
inj_in_fence=0 # inside any fenced code block
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
# Fenced code blocks are ignored by both detectors so docs can show literal
# examples (self-reference guard); lines with backtick runs or backslash-escaped
# `<` are structurally ambiguous and skipped per the parsing contract. A
# trailing \r is tolerated per line (third-party checkouts without eol=lf normalization).
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
    BEGIN { fe_blank = 1; cm_in_comment = 0 }
    # NO ERE INTERVALS IN THIS PROGRAM. The three-space indent cap is written as
    # three optional spaces (" ? ? ?") and the ordered-marker digit cap as one
    # digit plus eight optional ones, never as {0,3} / {1,9}. Two mawk failures
    # motivate the rule, and both are silent: mawk 1.3.4 PANICS ("REcompile() -
    # panic: values still on machine stack") when an interval is immediately
    # followed by a group, killing the program before it emits a record, so every
    # malformed directive PASSes; mawk 1.3.3 does not implement intervals at all
    # and matches them as literal characters, so the same scan quietly never
    # fires. Both leave check 21 reporting a clean run over a file it never read.
    # Same portability intent as the [[:space:]] note above, one layer deeper.
    # Blockquote nesting depth of a raw line: the number of leading `>` markers,
    # each optionally followed by one space, under the three-space indent cap.
    function fe_depth_of(s,   d) {
      d = 0
      while (match(s, /^ ? ? ?> ?/)) { d++; s = substr(s, RSTART + RLENGTH) }
      return d
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
        fe_fence = 0; fe_open_pre = 0; fe_icode = 0; fe_blank = 1; cm_in_comment = 0
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
          sub(/^ ? ? ?> ?/, "", $0)
          sub(/^ ? ? ?([-*+]|[0-9][0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[.)])[ \t]+/, "", $0)
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
    /^ ? ? ?(```+|~~~+)/ {
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
        fe_fence = 1; fe_open_char = fe_char; fe_open_len = fe_len; fe_open_pre = fe_stripped; fe_open_depth = fe_bq_depth
        fe_open_bq = (fe_bq_depth > 0); fe_open_ind = fe_strip_len
        next
      }
    }
    fe_fence { next }
    {
      line = $0
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
      # Inline code spans and backslash escapes are not reconstructed — a line
      # that carries either is ambiguous for directive hard verdicts and is
      # skipped by the Form 1 and judgment detectors. See the parsing contract.
      fe_bt_ambig = (index(line, "`") > 0)
      fe_esc_ambig = (index(line, "\\<") > 0) # portability-ok: index() for literal backslash+less-than, not a GNU grep word boundary
      fe_line_ambig = (fe_icode || fe_bt_ambig || fe_esc_ambig)
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
        damb[dir_n] = fe_line_ambig
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
      # classified, since a directive IS a comment. Comment state carries across
      # lines until the closing `-->`, so delegation wording split across a
      # multi-line comment does not satisfy Form 1.
      if (cm_in_comment) {
        cm_e = index(line, "-->")
        if (cm_e) {
          line = substr(line, cm_e + 3)
          cm_in_comment = 0
        } else {
          line = ""
        }
      }
      cm_keep = ""
      while ((cm_p = index(line, "<!--")) > 0) {
        cm_keep = cm_keep substr(line, 1, cm_p - 1) " "
        line = substr(line, cm_p + 4)
        cm_e = index(line, "-->")
        if (!cm_e) {
          if (!fe_bt_ambig && !fe_esc_ambig) cm_in_comment = 1
          line = ""
          break
        }
        line = substr(line, cm_e + 3)
      }
      line = cm_keep line
      if (fe_bt_ambig || fe_esc_ambig) next
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

# --- Check 22: metadata.summary length cap -----------------------------------
# The key is the generated skill cheat sheet's row source; the cap keeps rows
# scannable. Length is Unicode CODEPOINTS, not bytes, counted
# locale-independently: UTF-8 -> UTF-32BE via iconv makes every codepoint
# exactly 4 bytes, so byte-count/4 is the codepoint count on any host — a
# locale-pinned ${#var} silently degrades to byte counting where the pinned
# locale does not exist, tightening the cap for multi-byte summaries. Hosts
# without iconv fall back to the UTF-8-locale form. The value is read via
# metadata_field (trailing-comment strip) + strip_quotes, matching how the
# sheet generator reads it.

SUMMARY_CP_CAP=100
CUR_SUMMARY="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::metadata_field summary <<<"$FRONTMATTER")")"
if [[ -n "$CUR_SUMMARY" ]]; then
  if command -v iconv >/dev/null 2>&1; then
    SUMMARY_CP_LEN=$(($(printf '%s' "$CUR_SUMMARY" | iconv -f UTF-8 -t UTF-32BE | wc -c) / 4))
  else
    SUMMARY_CP_LEN="$(
      LC_ALL=C.UTF-8
      printf '%s' "${#CUR_SUMMARY}"
    )"
  fi
  if ((SUMMARY_CP_LEN > SUMMARY_CP_CAP)); then
    err "metadata.summary is $SUMMARY_CP_LEN codepoints (cap $SUMMARY_CP_CAP — the cheat sheet row it generates must stay scannable)"
  else
    note "summary $SUMMARY_CP_LEN/$SUMMARY_CP_CAP codepoints"
  fi
fi

# --- Check 23: completion-criteria signal (WARN; advisory heuristic) ----------
# Flags a numbered procedure (three or more ordered-list steps outside fenced
# code blocks) whose text carries no completion-criteria signal — no observable
# done-condition a reader can test. A step without one invites premature
# completion: the model marks it done at the first plausible output. Advisory
# only: a static scan can detect the ABSENCE of any completion signal, never
# grade the quality of a criterion, and an illustrative list is
# indistinguishable from an operative one — so the signal tokens are
# deliberately broad and only genuinely signal-free procedures fire.
# Write-side doctrine: docs-hygiene:write-for-agents ("Give every step a
# completion criterion").

CC_SIGNAL='done|complete|verified|verify|confirm|assert|exit|pass|green|criteria|criterion|until|settle|expect|observable|observed|succeed|fail'
# Blank lines separate LOOSE list items without closing the block — but a
# numbered item that RESTARTS numbering (its number <= the previous item's)
# after a blank line is a new, independent list, and merging the two would
# both fire a spurious warn on adjacent short lists and let one list's signal
# clear the other. Side effect, accepted: an all-ones-numbered LOOSE list
# (CommonMark lazy numbering, blank lines between items) closes at every item
# and so under-reports — consistent with the advisory posture above.
CC_BLOCKS="$(awk -v sigre="$CC_SIGNAL" '
  function close_block() {
    if (steps >= 3 && !sig) bad = bad (bad ? "," : "") start "-" last
    steps = 0; sig = 0; had_blank = 0
  }
  /^[[:space:]]*(```|~~~)/ {
    m = ($0 ~ /^[[:space:]]*```/) ? "b" : "t"
    if (!fence) { fence = 1; fence_ch = m } else if (m == fence_ch) fence = 0
    next
  }
  fence { next }
  {
    lower = tolower($0)
    if ($0 ~ /^[[:space:]]*[0-9]+[.)][[:space:]]/) {
      n = $0
      sub(/^[[:space:]]*/, "", n)
      sub(/[.)].*$/, "", n)
      n = n + 0
      if (steps > 0 && had_blank && n <= last_n) close_block()
      if (steps == 0) start = NR
      steps++; last = NR; last_n = n; had_blank = 0
      if (lower ~ sigre) sig = 1
    } else if ($0 ~ /^[[:space:]]*$/) {
      had_blank = 1
    } else if (steps > 0 && $0 ~ /^[[:space:]]+[^[:space:]]/) {
      last = NR; had_blank = 0
      if (lower ~ sigre) sig = 1
    } else {
      close_block()
    }
  }
  END { close_block(); print bad }
' "$SKILL_MD")"
if [[ -n "$CC_BLOCKS" ]]; then
  warn "numbered procedure(s) at lines $CC_BLOCKS carry no completion-criteria signal — steps risk premature completion; give each step an observable done-condition (write-side doctrine: docs-hygiene:write-for-agents)"
else
  note "completion-criteria signal present (or no 3+-step numbered procedure)"
fi

# --- Check 24: explicit invocation mode --------------------------------------
# Every skill states its invocation mode explicitly. The official default for an
# absent key is already `false` (docs table row, code.claude.com/docs/en/skills),
# so this is an auditability rule rather than a behavior change: an explicit key
# makes the choice reviewable, and a `true` reviewable against the exception
# classes in the rubric that owns this decision —
# docs/conventions/invocation-mode/README.md.
#
# Severity is scoped by tree, deliberately. A marketplace plugin skill
# (plugins/*/skills/*) FAILs: the rubric is this fleet's convention and the fleet
# is normalized to it. A skill outside that tree — a consumer's project or user
# skill — WARNs instead, because the harness default already makes an absent key
# behave as `false`, and failing someone else's tree over a house convention
# would be wrong.
#
# The exception class a `true` claims is NOT machine-checkable: a static scan
# cannot tell class (i) manual-timing from an unjustified hide. Only class (ii)
# is deterministic — the PLUGIN-PHILOSOPHY setup contract names `setup` skills —
# so every other `true` emits a note for hand-verification against the rubric
# rather than a warning nothing can clear.

INVOCATION_RUBRIC='docs/conventions/invocation-mode/README.md'
# Validated as a BARE YAML boolean, deliberately WITHOUT quote stripping: `"false"`
# is a YAML string, not the boolean this key takes, and normalizing the quotes
# away would ship malformed invocation metadata while reporting PASS. Only
# leading/trailing whitespace is trimmed — deleting whitespace wholesale would
# splice a scalar broken by an internal space back into a passing boolean. A
# trailing `# comment` is already removed by skill_frontmatter::field, so an
# author may annotate the exception class inline.
DMI_RAW="$(skill_frontmatter::field disable-model-invocation <<<"$FRONTMATTER")"
DMI_TRIMMED="${DMI_RAW#"${DMI_RAW%%[![:space:]]*}"}"
DMI_TRIMMED="${DMI_TRIMMED%"${DMI_TRIMMED##*[![:space:]]}"}"
DMI_VAL="$(printf '%s' "$DMI_TRIMMED" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$DMI_VAL" ]]; then
  if [[ "$SKILL_REL" == plugins/*/skills/* ]]; then
    err "frontmatter has no explicit disable-model-invocation key — every skill in this marketplace states its invocation mode (the absent-key default is false; write it out so the choice is auditable). Rubric: $INVOCATION_RUBRIC"
  else
    warn "frontmatter has no explicit disable-model-invocation key — the absent-key default is false, so behavior is unchanged; writing it out makes the choice auditable (marketplace-fleet convention: $INVOCATION_RUBRIC)"
  fi
elif [[ "$DMI_VAL" != "true" && "$DMI_VAL" != "false" ]]; then
  if [[ "$DMI_TRIMMED" == \"*\" || "$DMI_TRIMMED" == \'*\' ]]; then
    err "disable-model-invocation is the quoted string $DMI_TRIMMED — YAML reads that as a string, not a boolean; write it unquoted as true or false"
  else
    err "disable-model-invocation is '$DMI_TRIMMED' — expected the boolean true or false"
  fi
elif [[ "$DMI_VAL" == "true" ]]; then
  if [[ "$SKILL_NAME" == "setup" ]]; then
    note "invocation mode: user-invoked only — exception class (ii), setup contract"
  else
    note "invocation mode: user-invoked only — hand-verify it against an exception class ((i) side-effect/manual-timing, (ii) setup, (iii) maintainer-only) in $INVOCATION_RUBRIC; a static scan cannot attribute the class"
  fi
else
  note "invocation mode: model-invoked (fleet default)"
fi

# --- Check 25: description/verb-contract polarity (WARN; advisory) ----------
# PLUGIN-PHILOSOPHY Naming fixes verb meanings: audit/scan are read-only
# findings reports (mutation only behind an explicit override such as --fix);
# clean/tidy/fix mutate the target. This check flags a description that tells
# a different story than that verb contract, or than the body — the two
# directions in #2896. Narrow by design:
#   - polarity is read from the description LEAD (before "Use when:"), so a
#     trigger phrase like 'fix the formatting' never advertises mutation;
#   - override language (--fix, explicit override, never on bare) anywhere in
#     the listing text is the compliant claude-config:audit [--fix] shape and
#     clears a report-only verb;
#   - "read-only by default" is a default-then-override shape, not a
#     never-mutates claim;
#   - "remediation" as a noun and a negated "or rewrites" list are not
#     mutate-advertising.
# Advisory only: a static scan cannot judge whether an audit skill should
# gain a --fix path (out of scope) or whether a name should change (no
# rename campaign). A WARN is a factual-consistency candidate to
# hand-verify, not a mandate to rewrite the fleet.
# Fenced code blocks are ignored in the body so a literal example cannot
# satisfy or trip the body limbs.

# Drop a negated mutate-verb clause so "never rewrites the files" cannot
# advertise mutation. Scoped to those verbs — a blanket "not ..." strip
# would eat unrelated lead text.
vc_strip_negated_mutate() {
  printf '%s' "$1" | sed -E \
    's/(never|not|does not|do not)[[:space:]]+(rewrites?|fixes|remediates?|mutates|applies)[^.;]*//g'
}

vc_lead_mutate() {
  # Positive action verbs only. "remediation" (noun) is not advertising.
  printf '%s' "$(vc_strip_negated_mutate "$1")" | grep -qE \
    '(^|[[:space:]])remediates[[:space:]]|and[[:space:]]+remediate([^[:alnum:]]|$)|(^|[[:space:]])rewrites[[:space:]]+(the|your|files)|(^|[[:space:]])fixes[[:space:]]+(the|your|files)|applies[[:space:]]+(fixes|edits|changes|patches)|mutates[[:space:]]+(the|on|files)|and[[:space:]]+fix([^[:alnum:]]|$)'
}

vc_lead_readonly() {
  local t="$1"
  case "$t" in
  *"read-only by default"* | *"read only by default"*) return 1 ;;
  *) ;;
  esac
  # A scoped "does not modify X" next to a mutate advertisement is a
  # restriction, not a never-mutates claim (Fixes the files but does not
  # modify vendored dependencies).
  vc_lead_mutate "$t" && return 1
  printf '%s' "$t" | grep -qE \
    'read[- ]only|report[- ]only|findings[[:space:]]+(report|only)|no edits applied|never[[:space:]]+(writes|mutates|modifies|edits)|does not[[:space:]]+(modify|edit|write|mutate)|zero mutations|performs[[:space:]]+zero[[:space:]]+mutations'
}

vc_has_override() {
  printf '%s' "$1" | grep -qE \
    -- '--fix|explicit[[:space:]]+(user[[:space:]]+)?override|only[[:space:]]+behind|never[[:space:]]+on[[:space:]]+bare|not[[:space:]]+on[[:space:]]+bare|read[- ]only[[:space:]]+on[[:space:]]+bare'
}

# Body limbs are fence-aware (frontmatter + both CommonMark fence forms).
# Close is character-only, same as check 23 — not CommonMark run-length
# matching. A nested shorter fence of the same character can unmask the
# rest of an illustrative block; accepted recall limit for an advisory check.
# NO ERE INTERVALS — same mawk-portability rule as checks 21 and 23.
VC_BODY="$(awk '
  NR == 1 && /^---[ \t]*$/ { fm = 1; next }
  fm { if (/^---[ \t]*$/) fm = 0; next }
  /^[[:space:]]*(```|~~~)/ {
    m = ($0 ~ /```/) ? "b" : "t"
    if (!fence) { fence = 1; ch = m } else if (m == ch) fence = 0
    next
  }
  fence { next }
  { print }
' "$SKILL_MD")"

vc_body_bare_mutate() {
  printf '%s\n' "$1" | awk '
    { low = tolower($0) }
    low ~ /never|does not|do not|not on bare/ { next }
    low ~ /mutates on bare invocation|edits on bare invocation|writes on bare invocation/ { found = 1 }
    low ~ /on bare invocation[, ]+(edit|write|apply|rewrite|mutate)([^a-z]|$)/ { found = 1 }
    END { exit !found }
  '
}

vc_body_never_mutate() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -qE \
    'never[[:space:]]+mutates|does not[[:space:]]+modify|no edits applied|never[[:space:]]+writes|read[- ]only[[:space:]]+on[[:space:]]+bare|does not[[:space:]]+fix[[:space:]]+on[[:space:]]+bare|nothing edits'
}

VC_LEAF="${SKILL_NAME%%-*}"
VC_LEAD="$(printf '%s' "$CUR_DESC" | sed -E 's/[Uu]se[[:space:]]+[Ww]hen:.*//')"
VC_LEAD_LC="$(printf '%s' "$VC_LEAD" | tr '[:upper:]' '[:lower:]')"
VC_ALL_LC="$(printf '%s %s' "$CUR_DESC" "$CUR_WTU" | tr '[:upper:]' '[:lower:]')"

VC_HIT=""
if [[ "$VC_LEAF" == "audit" || "$VC_LEAF" == "scan" ]] &&
  vc_lead_mutate "$VC_LEAD_LC" && ! vc_has_override "$VC_ALL_LC"; then
  VC_HIT="leaf verb '$VC_LEAF' is a read-only findings report (PLUGIN-PHILOSOPHY Naming) but the description lead advertises mutation without an explicit override"
elif [[ "$VC_LEAF" == "clean" || "$VC_LEAF" == "tidy" || "$VC_LEAF" == "fix" ]] &&
  vc_lead_readonly "$VC_LEAD_LC"; then
  VC_HIT="leaf verb '$VC_LEAF' mutates the target (PLUGIN-PHILOSOPHY Naming) but the description lead claims the skill is read-only/report-only"
elif vc_lead_readonly "$VC_LEAD_LC" && vc_body_bare_mutate "$VC_BODY"; then
  VC_HIT="description lead claims read-only but the body mutates on bare invocation (or hides an unadvertised mutation path)"
elif vc_lead_mutate "$VC_LEAD_LC" && ! vc_has_override "$VC_ALL_LC" &&
  vc_body_never_mutate "$VC_BODY"; then
  VC_HIT="description lead advertises fixing but the body claims the skill never mutates"
fi

if [[ -n "$VC_HIT" ]]; then
  warn "description/verb-contract mismatch: $VC_HIT — a mismatch is a factual defect in the listing surface being routed on, not a style issue. Hand-verify; --fix in the description is the compliant override shape. Out of scope: whether this skill should gain a --fix path, and any rename"
else
  note "description/verb-contract polarity consistent (or no Naming verb / no polarity language)"
fi

# --- Summary ---------------------------------------------------------------

printf '\n'
if ((FAILED > 0)); then
  printf 'CHECK-SKILL %s: FAIL — %d error(s), %d warning(s)\n' "$SKILL_NAME" "$FAILED" "$WARNINGS" >&2
  exit 1
fi
printf 'CHECK-SKILL %s: PASS — 0 errors, %d warning(s)\n' "$SKILL_NAME" "$WARNINGS"
exit 0
