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
# Any FAIL fails this gate.
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
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2

# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! gate_entry::classify "$@" || [[ "$GE_MODE" != base ]]; then
  echo "usage: check-changed-skills.sh <base-ref>" >&2
  exit 2
fi
BASE="$GE_REF"

CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi

# Recorded pre-existing `description` field-cap breaches, handed to the checker's
# check 2b so those skills WARN where an unrecorded breach FAILs (#3845).
#
# Absent = passed empty, which means NO downgrades: the checker then FAILs every
# breach. That is the safe direction for a file that has gone missing (the gate
# gets stricter and says so, loudly, on the next changed skill), and it is what
# lets the fixture repos in the test suite run the real checker without carrying
# this repo's baseline. SKILL_DESC_CAP_BASELINE overrides the path for tests.
DESC_CAP_BASELINE="${SKILL_DESC_CAP_BASELINE-}"
if [[ -z "${SKILL_DESC_CAP_BASELINE+set}" && -f "$PWD/scripts/skill-description-cap-baseline.txt" ]]; then
  DESC_CAP_BASELINE="$PWD/scripts/skill-description-cap-baseline.txt"
fi

# Recorded evals-warrant skips. Missing file = no skips (tests, other repos).
# A stale row is a gate failure so the list can only shrink.
EXEMPTIONS="${EVALS_WARRANT_EXEMPTIONS:-scripts/evals-warrant-exemptions.txt}"
evals_skip_dirs=()
if [[ -f "$EXEMPTIONS" ]]; then
  # `inline`: entries are skill paths, never regexes, so a `#` anywhere on the
  # line opens the reason comment (scripts/lib/read-list.sh owns the two comment
  # families and why they must stay distinct).
  read_list::into evals_skip_dirs "$EXEMPTIONS" --comments inline || exit 2
  evals_stale=0
  for raw in ${evals_skip_dirs[@]+"${evals_skip_dirs[@]}"}; do
    if [[ "$raw" != plugins/*/skills/* || "$raw" == */*/*/*/* ]]; then
      printf 'FAIL: %s: not a skill path: %s\n' "$EXEMPTIONS" "$raw" >&2
      exit 2
    fi
    # A row still doing its job names a live skill that ships no evals; anything
    # else is an exemption outliving what it excuses. scripts/lib/read-list.sh
    # owns the consumed-set and the diagnostic.
    if [[ ! -f "$raw/SKILL.md" ]]; then
      read_list::stale_line "$EXEMPTIONS" "$raw" 'names a skill that is gone'
      evals_stale=1
    elif [[ -f "$raw/evals/evals.json" ]]; then
      read_list::stale_line "$EXEMPTIONS" "$raw" 'names a skill that now ships evals'
      evals_stale=1
    fi
  done
  ((evals_stale == 0)) || exit 1
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
# hands back NUL-safe paths; piping them into a line-oriented sed would C-quote
# them.
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

# ONE CHECKER PER CORE. Each skill is checked on its own, so the checks run
# CHECK_CHANGED_SKILLS_JOBS at a time (default: the core count) and each one's
# output is captured and printed whole, in the order the skills were found, so
# the log reads exactly as a serial run's. A marketplace-wide change checked
# the skills one at a time for up to six minutes.
jobs_max="${CHECK_CHANGED_SKILLS_JOBS:-$(nproc 2>/dev/null || echo 1)}"
[[ "$jobs_max" =~ ^[1-9][0-9]*$ ]] || jobs_max=1
out_dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$out_dir"' EXIT
keys=()

for skill_dir in ${changed[@]+"${changed[@]}"}; do
  # A deletion/rename-away leaves no SKILL.md in the tree — not a regression to
  # gate (and the checker would FAIL "not found"). Skip those.
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skills_root="${skill_dir%/*}" # plugins/<plugin>/skills
  skill_name="${skill_dir##*/}" # <skill>
  checked=$((checked + 1))
  key="$(printf '%06d' "$checked")"
  keys+=("$key")
  {
    printf '=== %s ===\n' "$skill_dir"
    require_evals_args=()
    if grep -q . < <(git diff --name-only "$BASE" -- "$skill_dir/SKILL.md"); then
      if evals_warrant_skip "$skill_dir"; then
        printf 'evals skip recorded for %s — not passing --require-evals\n' "$skill_dir"
      else
        require_evals_args=(--require-evals)
      fi
    fi
  } >"$out_dir/$key.head"
  (
    rc=0
    CHECK_SKILL_SKILLS_ROOT="$PWD/$skills_root" \
      CHECK_SKILL_BASE_REF="$BASE" \
      CHECK_SKILL_SKIP_MARKDOWNLINT=1 \
      CHECK_SKILL_DESC_FIELD_BASELINE="$DESC_CAP_BASELINE" \
      bash "$CHECKER" ${require_evals_args[@]+"${require_evals_args[@]}"} "$skill_name" \
      >"$out_dir/$key.out" 2>&1 || rc=$?
    printf '%s\n' "$rc" >"$out_dir/$key.rc"
  ) &
  while (($(jobs -rp | wc -l) >= jobs_max)); do wait -n || true; done
done
wait

for key in ${keys[@]+"${keys[@]}"}; do
  cat "$out_dir/$key.head" "$out_dir/$key.out"
  rc="$(cat "$out_dir/$key.rc" 2>/dev/null || echo 1)"
  [[ "$rc" == 0 ]] || failed=$((failed + 1))
done

if ((checked == 0)); then
  echo "No changed skills under plugins/*/skills/ — nothing to gate."
  gate_entry::finish 0
fi

printf '\n%d skill(s) checked, %d failed.\n' "$checked" "$failed"
((failed == 0))
gate_entry::finish $?
