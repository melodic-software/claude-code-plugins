# shellcheck shell=bash
set -uo pipefail

usage() {
  echo "usage: time-gates.sh --timings FILE [--base REF]" >&2
  exit 2
}

timings_file=""
base="origin/main"
while (($# > 0)); do
  case "$1" in
  --timings)
    [[ $# -ge 2 ]] || usage
    timings_file="$2"
    shift
    ;;
  --timings=*) timings_file="${1#--timings=}" ;;
  --base)
    [[ $# -ge 2 ]] || usage
    base="$2"
    shift
    ;;
  --base=*) base="${1#--base=}" ;;
  *) usage ;;
  esac
  shift
done
[[ -n "$timings_file" && -n "$base" ]] || usage
timings_dir="$(dirname "$timings_file")"
if [[ ! -d "$timings_dir" ]]; then
  echo "error: --timings directory not found: $timings_dir" >&2
  exit 2
fi
timings_file="$(cd "$timings_dir" && pwd)/$(basename "$timings_file")" || exit 2

root="${TIME_GATES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$root" || exit 2

gates=(
  scripts/check-purged-em-dashes.sh
  scripts/check-changed-skills.sh
  scripts/check-changelog-parity.sh
  plugins/skill-quality/scripts/check-skill.sh
  plugins/planning/scripts/check-open-questions.sh
)
for g in "${gates[@]}"; do
  if [[ ! -f "$g" ]]; then
    echo "error: gate not found under $root: $g" >&2
    exit 2
  fi
done

scratch="$(mktemp -d)" || exit 2
trap 'rm -rf "$scratch"' EXIT
ledger="$scratch/interview-checklist.md"
printf '%s\n' '# /interview Checklist' '' '## Steps' '' '- [x] Step 1' '' \
  '## Open-question register' '' \
  '- Q1 | answered | round 1 | Who writes? | admin' \
  '- Q2 | answered | round 1 | What format? | markdown' \
  '' '## Decision tree' '' '- [ ] something' >"$ledger"

now=0
now_us() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    now="${EPOCHREALTIME//[.,]/}"
    now=$((10#$now))
  else
    now=$((SECONDS * 1000000))
  fi
}

: >"$timings_file" || exit 2
time_gate() {
  local gate="$1" rc=0 start us
  shift
  now_us
  start="$now"
  "$@" >&2 || rc=$?
  now_us
  us=$((now - start))
  printf '%s\t%d.%03d\t%s\n' "$gate" $((us / 1000000)) $((us % 1000000 / 1000)) "$rc" >>"$timings_file" || exit 2
}

time_gate "${gates[0]}" bash "${gates[0]}" --check
time_gate "${gates[1]}" bash "${gates[1]}" "$base"
time_gate "${gates[2]}" bash "${gates[2]}" --check-bump "$base"
time_gate "${gates[3]}" env CHECK_SKILL_SKILLS_ROOT="$root/plugins/skill-quality/skills" \
  CHECK_SKILL_BASE_REF="$base" CHECK_SKILL_SKIP_MARKDOWNLINT=1 bash "${gates[3]}" check
time_gate "${gates[4]}" bash "${gates[4]}" --ledger "$ledger"
exit 0
