#!/usr/bin/env bash
# Regression tests for detect.sh (self-contained — no external test lib).
#
# detect.sh resolves its scan root via `git rev-parse --show-toplevel`, so
# every scan case runs against a deterministic throwaway fixture repo.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/detect.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "exit $2" "exit $3"
  fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}
assert_silent() {
  if [[ -z "$2" ]]; then
    pass "$1"
  else
    fail "$1" "empty output" "$2"
  fi
}

# Fixture repos are tracked in a FILE rather than a shell array. Every
# constructor below is called inside a command substitution to capture the path
# it echoes, and an array append made in that subshell never reaches this
# shell, so an array-based ledger silently cleans up nothing. A file append
# survives the subshell, so the trap removes what the run actually created.
FIXTURE_LIST="$(mktemp)"
# Records are NUL-delimited, not newline-delimited: a newline inside TMPDIR
# would otherwise split one path across two records, and the trap would rm -rf
# the truncated prefix, which is a directory outside the fixture set.
cleanup_fixtures() {
  local r
  while IFS= read -r -d '' r; do
    [[ -n "$r" ]] && rm -rf "$r"
  done <"$FIXTURE_LIST"
  rm -f "$FIXTURE_LIST"
}
trap cleanup_fixtures EXIT

# Create an empty throwaway git repo, register it for cleanup, echo its path.
new_fixture_repo() {
  local repo
  repo="$(mktemp -d)"
  git init --quiet "$repo"
  printf '%s\0' "$repo" >>"$FIXTURE_LIST"
  printf '%s' "$repo"
}

# Build a throwaway git repo carrying one file with the given content, and
# echo its path. detect.sh scans the working tree of whatever repo it runs in.
fixture_repo() {
  local file_relpath="$1" line_content="$2"
  local repo
  repo="$(new_fixture_repo)"
  (
    cd "$repo" || exit 1
    mkdir -p "$(dirname "$file_relpath")"
    printf '%s\n' "$line_content" >"$file_relpath"
  )
  printf '%s' "$repo"
}

skill_root=".claude/skills"

# --help exits 0 with non-empty usage
out="$(bash "$SCRIPT" --help 2>&1)"
code=$?
assert_exit "--help exits 0" 0 "$code"
assert_contains "--help prints usage" "$out" "audit-encapsulation detect"

# Unknown arg → exit 2 with diagnostic
out="$(bash "$SCRIPT" --bogus-arg 2>&1)"
code=$?
assert_exit "unknown arg exits 2" 2 "$code"
assert_contains "unknown arg diagnostic" "$out" "unknown arg"

# Empty repo (no in-scope surfaces at all) → environment error
empty_repo="$(new_fixture_repo)"
out="$(cd "$empty_repo" && bash "$SCRIPT" 2>&1)"
code=$?
assert_exit "empty repo → exit 2 (no in-scope surfaces)" 2 "$code"
assert_contains "empty repo diagnostic" "$out" "no in-scope"

# Clean in-scope file → exit 0, silent
clean_repo="$(fixture_repo ".claude/rules/clean.md" "nothing to see here")"
out="$(cd "$clean_repo" && bash "$SCRIPT" 2>/dev/null)"
code=$?
assert_exit "clean repo → exit 0" 0 "$code"
assert_silent "clean repo emits nothing" "$out"

# Private-subdir cite from a rule file → violation, TSV row emitted
viol_repo="$(fixture_repo ".claude/rules/viol.md" \
  "see ${skill_root}/foo/context/notes.md for detail")"
out="$(cd "$viol_repo" && bash "$SCRIPT" 2>/dev/null)"
code=$?
assert_exit "private-subdir cite → exit 1" 1 "$code"
expected_row="$(printf '.claude/rules/viol.md\t1\t%s/foo/context/' "$skill_root")"
assert_contains "violation row is file<TAB>line<TAB>match" "$out" "$expected_row"

# Heading-anchor cite → violation
anchor_repo="$(fixture_repo "docs/guide.md" \
  "see ${skill_root}/foo/SKILL.md#some-heading")"
out="$(cd "$anchor_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "SKILL.md#anchor cite → exit 1" 1 "$?"
assert_contains "anchor cite emitted" "$out" "${skill_root}/foo/SKILL.md#"

# Bare SKILL.md path cite → legal (discouraged but public)
bare_repo="$(fixture_repo "docs/guide.md" \
  "see ${skill_root}/foo/SKILL.md")"
out="$(cd "$bare_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "bare SKILL.md cite → exit 0" 0 "$?"
assert_silent "bare SKILL.md cite emits nothing" "$out"

# *.schema.json at any depth → violation
schema_repo="$(fixture_repo ".claude/rules/schema.md" \
  "validate against ${skill_root}/foo/output.schema.json")"
out="$(cd "$schema_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "schema.json cite → exit 1" 1 "$?"
assert_contains "schema.json cite emitted" "$out" "output.schema.json"

# Plain data file at skill root → legal (data-file carve-out)
data_repo="$(fixture_repo ".claude/rules/data.md" \
  "reads ${skill_root}/foo/catalog.json at runtime")"
out="$(cd "$data_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "root data-file cite → exit 0" 0 "$?"
assert_silent "root data-file cite emits nothing" "$out"

# Root instruction file is in scope
readme_repo="$(fixture_repo "README.md" \
  "internals at ${skill_root}/foo/reference/table.md")"
out="$(cd "$readme_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "README.md violation → exit 1" 1 "$?"
assert_contains "README.md hit emitted" "$out" "README.md"

# .github/ workflows are in scope
gh_repo="$(fixture_repo ".github/workflows/ci.yml" \
  "run: cat ${skill_root}/foo/lib/helper.sh")"
out="$(cd "$gh_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit ".github violation → exit 1" 1 "$?"
assert_contains ".github hit emitted" "$out" "${skill_root}/foo/lib/"

# Mixed line: scripts/ entry cite + other-skill private cite. The genuine cite
# must survive (exit 1, emitted) while the scripts/ cite stays carved out —
# per-cite granularity, not whole-line masking.
mixed_repo="$(fixture_repo ".claude/rules/mixed.md" \
  "see ${skill_root}/alpha/scripts/foo.sh and ${skill_root}/beta/research/bar.md")"
out="$(cd "$mixed_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "mixed line: scripts/ + private → exit 1 (masking fix)" 1 "$?"
assert_contains "mixed line: emits the private cite" "$out" "${skill_root}/beta/research/"
assert_not_contains "mixed line: scripts/ cite stays carved out" "$out" "/scripts/"

# Pure scripts/ line stays carved out (entry-surface carve-out)
pure_repo="$(fixture_repo ".claude/rules/pure-scripts.md" \
  "see ${skill_root}/alpha/scripts/foo.sh")"
out="$(cd "$pure_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "pure scripts/ line → exit 0 (carve-out)" 0 "$?"
assert_silent "pure scripts/ line emits nothing" "$out"

# Self-citation: skills dir is out of scope by default...
self_repo="$(fixture_repo "${skill_root}/foo/SKILL.md" \
  "progressive disclosure: ${skill_root}/foo/context/detail.md")"
# ...a clean in-scope file keeps the default run off the exit-2 path.
mkdir -p "$self_repo/.claude/rules"
printf 'clean\n' >"$self_repo/.claude/rules/clean.md"
out="$(cd "$self_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "self-citation out of scope by default → exit 0" 0 "$?"

# ...surfaces raw with --include-skills...
out="$(cd "$self_repo" && bash "$SCRIPT" --include-skills 2>/dev/null)"
assert_exit "self-citation raw with --include-skills → exit 1" 1 "$?"
assert_contains "self-citation raw hit emitted" "$out" "${skill_root}/foo/context/"

# ...and is filtered legal with --include-skills --apply-filters
err="$(cd "$self_repo" && bash "$SCRIPT" --include-skills --apply-filters 2>&1 >/dev/null)"
code=$?
assert_exit "self-citation filtered legal → exit 0" 0 "$code"
assert_contains "summary counts self-citation as mech-filtered" "$err" \
  "raw=1 mech-filtered=1 candidates=0"

plugin_skill_root="plugins/my-plugin/skills"

# Positive control: marketplace monorepo layout must not scan vacuously (#1889).
plugin_repo="$(fixture_repo "docs/guide.md" \
  "see ${plugin_skill_root}/foo/context/notes.md for detail")"
out="$(cd "$plugin_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "plugin private-subdir cite → exit 1" 1 "$?"
expected_plugin_row="$(printf 'docs/guide.md\t1\t%s/foo/context/' "$plugin_skill_root")"
assert_contains "plugin violation row emitted" "$out" "$expected_plugin_row"

plugin_scripts_repo="$(fixture_repo "docs/guide.md" \
  "run ${plugin_skill_root}/alpha/scripts/foo.sh")"
out="$(cd "$plugin_scripts_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "plugin scripts/ entry cite → exit 0 (carve-out)" 0 "$?"
assert_silent "plugin scripts/ cite emits nothing" "$out"

# Subdir / skill name shapes beyond the kebab class must match.
for shape_desc_path in \
  "uppercase-subdir:${skill_root}/foo/Context/notes.md" \
  "single-char-subdir:${skill_root}/foo/c/x.md" \
  "digit-leading-subdir:${skill_root}/foo/2dir/x.md" \
  "underscore-leading-subdir:${skill_root}/foo/_priv/x.md" \
  "uppercase-skill:${skill_root}/Foo/context/x.md" \
  "digit-leading-skill:${skill_root}/2skill/context/x.md" \
  "underscore-leading-skill:${skill_root}/_x/context/x.md"; do
  shape="${shape_desc_path%%:*}"
  cite_path="${shape_desc_path#*:}"
  match_prefix="$(dirname "$cite_path")/"
  shape_repo="$(fixture_repo ".claude/rules/shape.md" "see ${cite_path}")"
  out="$(cd "$shape_repo" && bash "$SCRIPT" 2>/dev/null)"
  assert_exit "F3 ${shape} cite → exit 1" 1 "$?"
  assert_contains "F3 ${shape} emitted" "$out" "$match_prefix"
done

# Prose listing multiple skill roots must not span whitespace/punctuation into one hit.
prose_repo="$(fixture_repo ".claude/rules/prose.md" \
  "The roots are .claude/skills/, .claude/agents/, and .claude/rules/.")"
out="$(cd "$prose_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "multi-root prose list → exit 0 (no false span)" 0 "$?"
assert_silent "multi-root prose list emits nothing" "$out"

# --help documents candidate semantics and relative-path coverage (#2716 closed).
help_out="$(bash "$SCRIPT" --help 2>&1)"
assert_contains "--help says candidates exist" "$help_out" "candidates exist"
assert_contains "--help names relative forms" "$help_out" "relative forms"
assert_contains "--help warns against hard-gate" "$help_out" "hard-gate CI"

# Honest summary keys under --apply-filters on a candidate hit
cand_repo="$(fixture_repo ".claude/rules/cand.md" \
  "see ${skill_root}/foo/context/notes.md")"
err="$(cd "$cand_repo" && bash "$SCRIPT" --apply-filters 2>&1 >/dev/null)"
code=$?
assert_exit "candidate hit → exit 1" 1 "$code"
assert_contains "summary uses candidates key" "$err" "candidates=1"
assert_contains "summary uses mech-filtered key" "$err" "mech-filtered=0"
assert_not_contains "summary does not say illegal=" "$err" "illegal="

# --- Relative-path cites (#2716) ---

# Bare plugin-relative `skills/<x>/<subdir>/` (disk-hygiene README shape).
bare_skills_repo="$(fixture_repo "plugins/disk-hygiene/README.md" \
  "see [safety](skills/clean/reference/safety-model.md#standalone-git-checkout-evidence)")"
out="$(cd "$bare_skills_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "bare skills/ private-subdir cite → exit 1" 1 "$?"
assert_contains "bare skills/ violation emitted" "$out" "skills/clean/reference/"

# Heading-anchor form of bare skills/ must flag (not only the subdir slash form).
bare_anchor_repo="$(fixture_repo "plugins/demo/README.md" \
  "see skills/clean/SKILL.md#standalone-git-checkout-evidence")"
out="$(cd "$bare_anchor_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "bare skills/ SKILL.md#anchor cite → exit 1" 1 "$?"
assert_contains "bare skills/ anchor emitted" "$out" "skills/clean/SKILL.md#"

# `../`-prefixed path that still contains a `skills/` segment (harness-config
# cross-plugin shape removed in #2703).
dotdot_skills_repo="$(fixture_repo "plugins/harness-config/skills/audit/SKILL.md" \
  "see ../../../../harness-memory/skills/audit/reference/criteria.md")"
# Keep an in-scope non-skills surface so the default run is not exit-2.
mkdir -p "$dotdot_skills_repo/.claude/rules"
printf 'clean\n' >"$dotdot_skills_repo/.claude/rules/clean.md"
out="$(cd "$dotdot_skills_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "../.../skills/ private cite → exit 1" 1 "$?"
assert_contains "../.../skills/ cite emitted via skills/ segment" "$out" "skills/audit/reference/"

# Same-name cross-plugin ../.../skills/<name>/ must stay a candidate under
# --apply-filters (not vacated as self-citation by leaf name alone).
err="$(cd "$dotdot_skills_repo" && bash "$SCRIPT" --apply-filters 2>&1 >/dev/null)"
code=$?
assert_exit "cross-plugin same-leaf skills/ cite stays candidate" 1 "$code"
assert_contains "cross-plugin same-leaf summary keeps candidate" "$err" "candidates=1"

# Sibling-skill relative cite with no `skills/` segment in the text —
# resolution pass must catch it.
sibling_repo="$(new_fixture_repo)"
(
  cd "$sibling_repo" || exit 1
  mkdir -p plugins/demo/skills/alpha plugins/demo/skills/beta/reference
  printf 'see ../beta/reference/notes.md\n' >plugins/demo/skills/alpha/SKILL.md
  printf 'notes\n' >plugins/demo/skills/beta/reference/notes.md
  mkdir -p .claude/rules
  printf 'clean\n' >.claude/rules/clean.md
)
out="$(cd "$sibling_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "sibling ../skill/reference cite → exit 1" 1 "$?"
assert_contains "sibling relative cite emitted" "$out" "../beta/reference/"

# Same-skill `../reference/deep/` from an actions/ file is self-citation under
# --apply-filters (resolution lands in the citing skill). Assert raw>0 so a
# silent miss cannot vacate the filter check.
self_rel_repo="$(new_fixture_repo)"
(
  cd "$self_rel_repo" || exit 1
  mkdir -p plugins/demo/skills/alpha/actions
  mkdir -p plugins/demo/skills/alpha/reference/deep
  printf 'see ../reference/deep/notes.md\n' >plugins/demo/skills/alpha/actions/step.md
  printf 'notes\n' >plugins/demo/skills/alpha/reference/deep/notes.md
  mkdir -p .claude/rules
  printf 'clean\n' >.claude/rules/clean.md
)
raw_out="$(cd "$self_rel_repo" && bash "$SCRIPT" 2>/dev/null)"
raw_code=$?
assert_exit "same-skill ../reference/deep/ raw → exit 1" 1 "$raw_code"
assert_contains "same-skill relative cite raw-emitted" "$raw_out" "../reference/deep/"
err="$(cd "$self_rel_repo" && bash "$SCRIPT" --apply-filters 2>&1 >/dev/null)"
code=$?
assert_exit "same-skill ../reference/ filtered → exit 0" 0 "$code"
assert_contains "summary counts same-skill relative as mech-filtered" "$err" \
  "raw=1 mech-filtered=1 candidates=0"

# Bare skills/ scripts/ entry cite stays carved out.
bare_scripts_repo="$(fixture_repo "plugins/demo/README.md" \
  "run skills/alpha/scripts/foo.sh")"
out="$(cd "$bare_scripts_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "bare skills/ scripts/ cite → exit 0 (carve-out)" 0 "$?"
assert_silent "bare skills/ scripts/ cite emits nothing" "$out"

# Plugin README bare skills/ cite is NOT self-citation (README is external).
readme_bare_repo="$(fixture_repo "plugins/demo/README.md" \
  "see skills/alpha/reference/notes.md")"
# Add the skill so a mistaken self-filter could fire if it keyed only on text.
mkdir -p "$readme_bare_repo/plugins/demo/skills/alpha/reference"
printf 'x\n' >"$readme_bare_repo/plugins/demo/skills/alpha/reference/notes.md"
out="$(cd "$readme_bare_repo" && bash "$SCRIPT" --apply-filters 2>/dev/null)"
code=$?
assert_exit "plugin README bare skills/ cite stays candidate" 1 "$code"
assert_contains "README bare skills/ hit emitted under filters" "$out" "skills/alpha/reference/"

# --- Cross-plugin cites, file types, marketplace id, allowlist ---

# Skill-root cite (no trailing subdirectory) into another plugin.
root_repo="$(fixture_repo "plugins/alpha/README.md" \
  "see plugins/beta/skills/foo for the details.")"
out="$(cd "$root_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "cross-plugin skill-root cite → exit 1" 1 "$?"
assert_contains "skill-root cite emitted without the trailing dot" "$out" \
  "$(printf 'plugins/alpha/README.md\t1\tplugins/beta/skills/foo')"

# Bare SKILL.md path cite into another plugin.
bare_cross_repo="$(fixture_repo "plugins/alpha/README.md" \
  "read plugins/beta/skills/foo/SKILL.md first")"
out="$(cd "$bare_cross_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "cross-plugin bare SKILL.md cite → exit 1" 1 "$?"
assert_contains "bare SKILL.md cite emitted" "$out" "plugins/beta/skills/foo/SKILL.md"

# A .py file is scanned (every text file type).
py_repo="$(fixture_repo "plugins/alpha/tool.py" \
  "# see plugins/beta/skills/foo/reference/table.md")"
out="$(cd "$py_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit ".py file cite → exit 1" 1 "$?"
assert_contains ".py cite emitted" "$out" "tool.py"

# Cross-plugin scripts/ cite from inside plugins/ is flagged.
xscripts_repo="$(fixture_repo "plugins/alpha/README.md" \
  "run plugins/beta/skills/foo/scripts/run.sh")"
out="$(cd "$xscripts_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "cross-plugin scripts/ cite → exit 1" 1 "$?"
assert_contains "cross-plugin scripts/ cite emitted" "$out" "plugins/beta/skills/foo/scripts/"

# ...but a CI workflow outside plugins/ keeps the carve-out...
ci_scripts_repo="$(fixture_repo ".github/workflows/ci.yml" \
  "run: bash plugins/beta/skills/foo/scripts/run.sh")"
out="$(cd "$ci_scripts_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "workflow scripts/ cite → exit 0 (carve-out)" 0 "$?"
assert_silent "workflow scripts/ cite emits nothing" "$out"

# ...and so does the plugin's own scripts/ cite.
same_scripts_repo="$(fixture_repo "plugins/beta/README.md" \
  "run plugins/beta/skills/foo/scripts/run.sh")"
out="$(cd "$same_scripts_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "same-plugin scripts/ cite → exit 0" 0 "$?"
assert_silent "same-plugin scripts/ cite emits nothing" "$out"

# Same-plugin skill-root and bare SKILL.md cites stay quiet.
same_root_repo="$(fixture_repo "plugins/beta/README.md" \
  "see plugins/beta/skills/foo and plugins/beta/skills/foo/SKILL.md")"
out="$(cd "$same_root_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "same-plugin root and SKILL.md cites → exit 0" 0 "$?"
assert_silent "same-plugin root and SKILL.md cites emit nothing" "$out"

# github.com blob URL into another plugin's skill folder.
url_repo="$(fixture_repo "plugins/alpha/README.md" \
  "https://github.com/acme/market/blob/main/plugins/beta/skills/foo/SKILL.md")"
out="$(cd "$url_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "github blob URL cite → exit 1" 1 "$?"
assert_contains "github blob URL cite emitted" "$out" "plugins/beta/skills/foo/SKILL.md"

# raw.githubusercontent.com URL to a scripts/ file.
raw_url_repo="$(fixture_repo "plugins/alpha/README.md" \
  "https://raw.githubusercontent.com/acme/market/main/plugins/beta/skills/foo/scripts/run.sh")"
out="$(cd "$raw_url_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "raw URL scripts/ cite → exit 1" 1 "$?"
assert_contains "raw URL scripts/ cite emitted" "$out" "plugins/beta/skills/foo/scripts/"

# ../-prefixed cross-plugin bare SKILL.md and scripts/ cites resolve to the other plugin.
dotdot_cross_repo="$(fixture_repo "plugins/alpha/skills/a/SKILL.md" \
  "see ../../../beta/skills/foo/SKILL.md and ../../../beta/skills/foo/scripts/run.sh")"
out="$(cd "$dotdot_cross_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "../ cross-plugin SKILL.md and scripts/ cites → exit 1" 1 "$?"
assert_contains "../ cross-plugin SKILL.md cite emitted" "$out" "../../../beta/skills/foo/SKILL.md"
assert_contains "../ cross-plugin scripts/ cite emitted" "$out" "skills/foo/scripts/"

# ../ resolving back into the plugin's own sibling skill stays quiet.
dotdot_same_repo="$(fixture_repo "plugins/alpha/skills/a/SKILL.md" \
  "see ../../../alpha/skills/foo/SKILL.md and ../../../alpha/skills/foo/scripts/run.sh")"
out="$(cd "$dotdot_same_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "../ same-plugin SKILL.md and scripts/ cites → exit 0" 0 "$?"
assert_silent "../ same-plugin cites emit nothing" "$out"

# Own marketplace id outside an install recipe.
id_repo="$(fixture_repo "docs/guide.md" "enable foo@acme-market in settings")"
mkdir -p "$id_repo/.claude-plugin"
printf '{\n  "name": "acme-market",\n  "plugins": []\n}\n' >"$id_repo/.claude-plugin/marketplace.json"
out="$(cd "$id_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "own marketplace id → exit 1" 1 "$?"
assert_contains "own marketplace id emitted" "$out" "$(printf 'docs/guide.md\t1\tfoo@acme-market')"

# An install recipe line may carry the id.
recipe_repo="$(fixture_repo "docs/guide.md" "run /plugin install foo@acme-market")"
mkdir -p "$recipe_repo/.claude-plugin"
printf '{\n  "name": "acme-market",\n  "plugins": []\n}\n' >"$recipe_repo/.claude-plugin/marketplace.json"
out="$(cd "$recipe_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "install recipe with own id → exit 0" 0 "$?"
assert_silent "install recipe emits nothing" "$out"

# A third-party id, a longer id sharing the prefix, and an unbound repo stay quiet.
other_id_repo="$(fixture_repo "docs/guide.md" \
  "enable foo@other-market and bar@acme-market-extra")"
mkdir -p "$other_id_repo/.claude-plugin"
printf '{\n  "name": "acme-market"\n}\n' >"$other_id_repo/.claude-plugin/marketplace.json"
out="$(cd "$other_id_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "third-party and longer ids → exit 0" 0 "$?"
assert_silent "third-party and longer ids emit nothing" "$out"
nobind_repo="$(fixture_repo "docs/guide.md" "enable foo@acme-market in settings")"
out="$(cd "$nobind_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "no marketplace manifest → exit 0" 0 "$?"
assert_silent "no marketplace manifest emits nothing" "$out"

# Allowlist: a listed path with a reason is skipped; its sibling is not.
allow_repo="$(fixture_repo "plugins/alpha/evals/case.md" \
  "see plugins/beta/skills/foo/SKILL.md")"
printf 'see plugins/beta/skills/foo/SKILL.md\n' >"$allow_repo/plugins/alpha/README.md"
mkdir -p "$allow_repo/docs/conventions"
printf '# path<TAB>reason\nplugins/alpha/evals/\texists to exercise the detector\n' \
  >"$allow_repo/docs/conventions/audit-encapsulation-allowlist.tsv"
out="$(cd "$allow_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "allowlisted dir skipped, sibling still flagged → exit 1" 1 "$?"
assert_contains "unlisted sibling emitted" "$out" "plugins/alpha/README.md"
assert_not_contains "allowlisted path not emitted" "$out" "evals/case.md"

# Allowlist given by flag; a listed single file leaves nothing.
flag_allow_repo="$(fixture_repo "plugins/alpha/README.md" \
  "see plugins/beta/skills/foo/SKILL.md")"
printf 'plugins/alpha/README.md\ta fixture\n' >"$flag_allow_repo/list.tsv"
out="$(cd "$flag_allow_repo" && bash "$SCRIPT" --allowlist list.tsv 2>/dev/null)"
assert_exit "--allowlist file skips its path → exit 0" 0 "$?"
assert_silent "--allowlist file leaves no output" "$out"

# A row with no reason is an error.
noreason_repo="$(fixture_repo "plugins/alpha/README.md" "nothing here")"
printf 'plugins/alpha/README.md\n' >"$noreason_repo/list.tsv"
out="$(cd "$noreason_repo" && bash "$SCRIPT" --allowlist list.tsv 2>&1)"
assert_exit "allowlist row without reason → exit 2" 2 "$?"
assert_contains "allowlist reason diagnostic" "$out" "needs a path and a reason"

# Missing explicit allowlist file is an error.
out="$(cd "$noreason_repo" && bash "$SCRIPT" --allowlist missing.tsv 2>&1)"
assert_exit "missing --allowlist file → exit 2" 2 "$?"

# A ../ path spelling the plugins/ segment resolves like any other cross-plugin cite.
dotdot_plugins_repo="$(fixture_repo "plugins/alpha/skills/a/SKILL.md" \
  "see ../../../../plugins/beta/skills/foo/SKILL.md")"
out="$(cd "$dotdot_plugins_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "../plugins/ cross-plugin SKILL.md cite → exit 1" 1 "$?"
assert_contains "../plugins/ cite emitted once" "$out" "../../../../plugins/beta/skills/foo/SKILL.md"

# An id closing a sentence is still the own marketplace id.
dot_id_repo="$(fixture_repo "docs/guide.md" "Enable foo@acme-market.")"
mkdir -p "$dot_id_repo/.claude-plugin"
printf '{\n  "name": "acme-market"\n}\n' >"$dot_id_repo/.claude-plugin/marketplace.json"
out="$(cd "$dot_id_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "own id before a period → exit 1" 1 "$?"
assert_contains "own id emitted without the period" "$out" "$(printf 'docs/guide.md\t1\tfoo@acme-market')"

# A consumer repo (.claude/skills only, no plugins/) stays quiet on the new shapes.
consumer_repo="$(fixture_repo ".claude/rules/notes.md" \
  "see ${skill_root}/foo/SKILL.md and ${skill_root}/foo/scripts/run.sh and plugins/beta/skills/foo")"
out="$(cd "$consumer_repo" && bash "$SCRIPT" 2>/dev/null)"
assert_exit "consumer repo root/SKILL.md/scripts cites → exit 0" 0 "$?"
assert_silent "consumer repo emits nothing for the new shapes" "$out"

# --help names the new shapes.
assert_contains "--help names the allowlist" "$help_out" "--allowlist"
assert_contains "--help names the marketplace id check" "$help_out" "marketplace"

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
printf '\nAll %d checks passed.\n' "$CASE_NUM"
