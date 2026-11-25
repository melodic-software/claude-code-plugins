#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
lane=0
if [[ "${1-}" == --merge-base ]]; then
  lane=1
  GE_FLAGS=("--merge-base")
  cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2
else
  cd "$SCRIPT_DIR/.." || exit 2
fi
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2

# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! gate_entry::classify "$@" || [[ "$GE_MODE" != base && "$GE_MODE" != --merge-base ]]; then
  echo "usage: check-changed-skills.sh <base-ref> | --merge-base" >&2
  exit 2
fi
BASE="$GE_REF"
CHECKER="${CHECK_SKILL_BIN:-plugins/skill-quality/scripts/check-skill.sh}"
if ((lane)); then
  # shellcheck disable=SC2310  # the non-zero return IS the handled case
  if ! changed_files::resolve_base BASE; then
    # Only a shallow checkout's HEAD is the base the work started from; in a
    # full history a missing base ref would pass every committed change.
    if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" != true ]]; then
      printf 'Error: no origin/main, origin/master, main or master in a full checkout.\n' >&2
      exit 2
    fi
    printf 'Warning: no origin/main, origin/master, main or master; diffing against HEAD.\n' >&2
    BASE=HEAD
  fi
  CHECKER="$SCRIPT_DIR/../plugins/skill-quality/scripts/check-skill.sh"
  export CHECK_SKILL_SKIP_SCRIPT_TESTS=1
  st_baseline="$PWD/plugins/skill-quality/scripts/settings-token-baseline.txt"
  if [[ -z "${CHECK_SKILL_SETTINGS_TOKEN_BASELINE:-}" && -f "$st_baseline" ]]; then
    export CHECK_SKILL_SETTINGS_TOKEN_BASELINE="$st_baseline"
  fi
fi
# A branch behind $BASE must not inherit $BASE's own newer commits (#7014).
if merge_base="$(git merge-base "$BASE" HEAD 2>/dev/null)" && [[ -n "$merge_base" ]]; then
  BASE="$merge_base"
else
  printf 'Warning: no merge base for %s and HEAD; diffing against the ref as given.\n' "$BASE" >&2
fi

if [[ ! -f "$CHECKER" ]]; then
  printf 'Error: skill checker not found: %s\n' "$CHECKER" >&2
  exit 2
fi

medium_lists=0
if [[ -f lib/view-registry.mjs ]]; then
  [[ -f "$SCRIPT_DIR/check-view-medium-lists.mjs" ]] || {
    printf 'Error: view medium-list check not found: %s\n' "$SCRIPT_DIR/check-view-medium-lists.mjs" >&2
    exit 2
  }
  node "$SCRIPT_DIR/check-view-medium-lists.mjs" --root "$PWD" || medium_lists=$?
  ((medium_lists <= 1)) || exit 2
fi

EXEMPTIONS="${EVALS_WARRANT_EXEMPTIONS:-scripts/evals-warrant-exemptions.txt}"
evals_skip_dirs=()
declare -A evals_skip=()
if [[ -f "$EXEMPTIONS" ]]; then
  read_list::into evals_skip_dirs "$EXEMPTIONS" --comments inline || exit 2
  evals_stale=0
  for raw in ${evals_skip_dirs[@]+"${evals_skip_dirs[@]}"}; do
    if [[ "$raw" != plugins/*/skills/* || "$raw" == */*/*/*/* ]]; then
      printf 'FAIL: %s: not a skill path: %s\n' "$EXEMPTIONS" "$raw" >&2
      exit 2
    fi
    evals_skip["$raw"]=1
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
# A lane run's edits are uncommitted, so a skill it adds is untracked, which
# git diff does not list.
declare -A untracked=()
out_dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$out_dir"' EXIT
if ((lane)); then
  git ls-files --others --exclude-standard -z -- 'plugins/' >"$out_dir/untracked" || exit 2
  while IFS= read -r -d '' path; do
    changed_paths+=("$path")
    untracked["$path"]=1
  done <"$out_dir/untracked"
fi
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
  [[ -n "$skill" && "$skill" != "$rest" ]] || continue
  dir="plugins/$plugin/skills/$skill"
  [[ -z "${seen_dirs[$dir]:-}" ]] || continue
  seen_dirs["$dir"]=1
  changed+=("$dir")
done

checked=0
failed=0
left=0

jobs_max="${CHECK_CHANGED_SKILLS_JOBS:-$(nproc 2>/dev/null || echo 1)}"
[[ "$jobs_max" =~ ^[1-9][0-9]*$ ]] || jobs_max=1
keys=()

for skill_dir in ${changed[@]+"${changed[@]}"}; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skills_root="${skill_dir%/*}"
  skill_name="${skill_dir##*/}"
  checked=$((checked + 1))
  printf -v key '%06d' "$checked"
  keys+=("$key")
  {
    printf '=== %s ===\n' "$skill_dir"
    require_evals_args=()
    skill_md="$skill_dir/SKILL.md"
    if grep -q . < <(git diff --name-only "$BASE" -- "$skill_md") || [[ -n "${untracked["$skill_md"]:-}" ]]; then
      if [[ -n "${evals_skip[$skill_dir]:-}" ]]; then
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
  case "$rc" in
  0) ;;
  3) left=$((left + 1)) ;;
  *) failed=$((failed + 1)) ;;
  esac
done

if ((checked == 0)); then
  echo "No changed skills under plugins/*/skills/ — nothing to gate."
  gate_entry::finish "$medium_lists"
fi

printf '\n%d skill(s) checked, %d failed.\n' "$checked" "$failed"
((left == 0)) || printf '%d skill(s) left script tests to CI, past the deadline.\n' "$left"
((failed == 0 && medium_lists == 0)) || gate_entry::finish 1
((left == 0)) || gate_entry::finish 2
gate_entry::finish 0
