#!/usr/bin/env bash
# Deterministic skill-regression gate for the skills a PR changes.
#
#   scripts/check-changed-skills.sh <base-ref>
#
# For every skill under plugins/*/skills/** touched vs <base-ref>, run the
# skill-quality static contract gate (plugins/skill-quality/scripts/check-skill.sh
# — trigger-keyword preservation vs the base ref, frontmatter, listing-budget
# and line caps, broken internal refs, evals presence, committed artifacts).
# When a changed skill's SKILL.md is new or modified vs <base-ref>, the checker
# is invoked with --require-evals so a missing evals/evals.json FAILs for any
# shape, unless that skill has a recorded skip in
# scripts/evals-warrant-exemptions.txt (the warrant policy's explicit skip
# classes — #3135). Untouched legacy skills and non-SKILL.md-only touches keep
# the legacy WARN-only posture.
# Any FAIL fails this gate. It replaces the work lane's manual high-blast-radius
# skill-diff read with a deterministic check, and is the first lane to invoke the
# otherwise-uninvoked skill-quality checker.
#
# <base-ref> (e.g. origin/main) is BOTH the changed-file diff base and
# CHECK_SKILL_BASE_REF, so the checker's git-backed checks compare the PR head
# against the same base a reviewer would — a rewrite that silently drops a
# `description` trigger phrase is caught here, not at merge.
#
# markdownlint (check 6) is skipped here (CHECK_SKILL_SKIP_MARKDOWNLINT=1):
# SKILL.md markdown is already gated by the hygiene lane's markdown check, and
# `npx --no-install markdownlint-cli2` would only WARN-skip on a hosted runner
# without the package. Eval-schema validation (validate-evals) is a separate CI
# step — the check-jsonschema composite action over every evals.json.
#
# Exit 0 = every changed skill passes (or none changed); 1 = one or more failed;
# 2 = usage / environment error (fail closed — never a silent skip).
#
# CHECK_SKILL_BIN overrides the checker path (test injection).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2

BASE="${1:?usage: check-changed-skills.sh <base-ref>}"

if ! changed_files::verify_base "$BASE"; then
  printf 'Error: base ref %s is not a valid commit\n' "$BASE" >&2
  exit 2
fi

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi

# Recorded evals-warrant skips. Missing file = no skips (tests, other repos).
# A stale row is a gate failure so the list can only shrink.
EXEMPTIONS="${EVALS_WARRANT_EXEMPTIONS:-scripts/evals-warrant-exemptions.txt}"
evals_skip_dirs=()
if [[ -f "$EXEMPTIONS" ]]; then
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    raw="${raw%%#*}"
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    [[ -n "$raw" ]] || continue
    if [[ "$raw" != plugins/*/skills/* || "$raw" == */*/*/*/* ]]; then
      printf 'FAIL: %s: not a skill path: %s\n' "$EXEMPTIONS" "$raw" >&2
      exit 2
    fi
    if [[ ! -f "$raw/SKILL.md" ]]; then
      printf 'FAIL: %s: stale row, skill gone: %s\n' "$EXEMPTIONS" "$raw" >&2
      exit 1
    fi
    if [[ -f "$raw/evals/evals.json" ]]; then
      printf 'FAIL: %s: stale row, skill now ships evals: %s\n' "$EXEMPTIONS" "$raw" >&2
      exit 1
    fi
    evals_skip_dirs+=("$raw")
  done <"$EXEMPTIONS"
fi

evals_warrant_skip() {
  local dir="$1" listed
  for listed in ${evals_skip_dirs[@]+"${evals_skip_dirs[@]}"}; do
    [[ "$listed" == "$dir" ]] && return 0
  done
  return 1
}

# Changed skill dirs, mapped from any touched path (including vendor/ subtrees)
# to the owning plugins/<plugin>/skills/<skill> dir and de-duplicated.
#
# --include-deleted is deliberate and is NOT the portability scanners' setting.
# Those open each path and need a file on disk; this gate maps a path to its
# owning skill DIRECTORY and then re-runs the skill checker over that directory.
# A commit that only deletes files from a skill (dropping a reference/ page, say)
# still changed that skill and must still be re-checked — filtering deletions out
# would silently stop selecting it, an under-selection in the unsafe direction.
# The skill that was deleted OUTRIGHT is handled below by the SKILL.md guard.
#
# The mapping runs in bash rather than through `sed` because the shared resolver
# hands back NUL-safe paths; piping them into a line-oriented sed would give
# back exactly the C-quoting bug this gate had before #2914.
changed_paths=()
changed_files::into changed_paths "$BASE" --include-deleted -- 'plugins/' || exit 2
changed=()
declare -A seen_dirs=()
for path in ${changed_paths[@]+"${changed_paths[@]}"}; do
  # Segment-exact equivalent of the `^(plugins/[^/]+/skills/[^/]+)/.*` this
  # replaced. A `case` glob will NOT do: `*` matches `/` too, so
  # `plugins/*/skills/*/*` would also accept a nested `plugins/a/b/skills/...`
  # the anchored regex rejected.
  rest="${path#plugins/}"
  [[ "$rest" != "$path" ]] || continue
  plugin="${rest%%/*}"
  [[ -n "$plugin" && "$plugin" != "$rest" ]] || continue
  rest="${rest#"$plugin"/}"
  [[ "${rest%%/*}" == "skills" ]] || continue
  rest="${rest#skills/}"
  skill="${rest%%/*}"
  # `skill == rest` means nothing follows the skill directory, so the path IS
  # the directory rather than a file inside it — the trailing `/.*` the regex
  # required.
  [[ -n "$skill" && "$skill" != "$rest" ]] || continue
  dir="plugins/$plugin/skills/$skill"
  [[ -z "${seen_dirs[$dir]:-}" ]] || continue
  seen_dirs["$dir"]=1
  changed+=("$dir")
done

checked=0
failed=0

for skill_dir in "${changed[@]}"; do
  # A deletion/rename-away leaves no SKILL.md in the tree — not a regression to
  # gate (and the checker would FAIL "not found"). Skip those.
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skills_root="${skill_dir%/*}" # plugins/<plugin>/skills
  skill_name="${skill_dir##*/}" # <skill>
  checked=$((checked + 1))
  printf '=== %s ===\n' "$skill_dir"
  require_evals_args=()
  if git diff --name-only "$BASE" -- "$skill_dir/SKILL.md" | grep -q .; then
    if evals_warrant_skip "$skill_dir"; then
      printf 'evals skip recorded for %s — not passing --require-evals\n' "$skill_dir"
    else
      require_evals_args=(--require-evals)
    fi
  fi
  if ! CHECK_SKILL_SKILLS_ROOT="$PWD/$skills_root" \
    CHECK_SKILL_BASE_REF="$BASE" \
    CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
    bash "$CHECKER" "${require_evals_args[@]}" "$skill_name"; then
    failed=$((failed + 1))
  fi
done

if ((checked == 0)); then
  echo "No changed skills under plugins/*/skills/ — nothing to gate."
  exit 0
fi

printf '\n%d skill(s) checked, %d failed.\n' "$checked" "$failed"
((failed == 0))
