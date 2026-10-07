#!/usr/bin/env bash
# Before/after measurement for a plugin-by-plugin skill rewrite.
#
# Repo tooling, not shipped to consumers. Deterministic and model-free: it never
# invokes `claude`. Snapshots land in .work/skill-rewrite/<plugin>/<phase>.tsv
# (git-ignored) under the repo root.
#
# Usage:
#   bash scripts/skill-rewrite-measure.sh --plugin P --phase before|after [--dry-run]
#   bash scripts/skill-rewrite-measure.sh --plugin P --compare
#   bash scripts/skill-rewrite-measure.sh --help
#
# Options:
#   --plugin P        plugin directory name under plugins/
#   --phase PHASE     take a snapshot: before (pre-rewrite) or after
#   --compare         print the before/after delta table from the two snapshots
#   --dry-run         list the skills and the commands, write nothing, exit 0
#   --help            this text
#
# Recorded per skill: description characters (frontmatter `description`, folded,
# literal and quoted forms unwrapped by skill-frontmatter.sh), body lines (lines
# of SKILL.md after the frontmatter), the git SHA measured at, and the lexical
# tripwire score. Recorded per plugin: check-skill.sh exit code and WARN count
# over plugins/<plugin>/skills.
#
# Lexical tripwire score: when a probe file under plugins/<plugin>/probes/ (for
# example <skill>.json; its skill_dir names the skill it targets) covers the
# skill, the fraction of that skill's probe queries (train and validation) that
# `measure-invocation.sh score` (listing-overlap floor) predicts correctly. It is
# a floor, not a trigger rate. `n/a` when there is no probe file, or score
# cannot resolve the skill.
#
# --compare exit status: 1 when the root check exit code turns non-zero (it was
# 0), or when any skill's lexical score drops by more than 0.05 (absolute,
# after minus before); 0 otherwise. 2 for usage errors or a missing snapshot.
#
# Environment:
#   SKILL_REWRITE_MEASURE_ROOT        repo root to measure (default: this
#                                     script's git toplevel); tests point it at
#                                     a fixture tree
#   SKILL_REWRITE_MEASURE_CHECK_BIN   check-skill.sh to run (default: the
#                                     skill-quality plugin's copy)
#   SKILL_REWRITE_MEASURE_SCORE_BIN   measure-invocation.sh to run (default: the
#                                     skill-quality plugin's copy)
#   CHECK_SKILL_SKIP_MARKDOWNLINT=1   passed through to check-skill.sh
#
# Runbook: model-graded steps (they cost money and need approval; this script
# never runs them). Run after the deterministic snapshots above:
#   1. Trigger rate, model-graded:
#        bash plugins/skill-quality/scripts/measure-invocation.sh \
#          emit-plugin-eval plugins/<plugin>/probes <out-dir>
#      then `claude plugin eval` on <out-dir> (see /evals:plugin-eval for
#      preflight, cost estimate and reading the delta). Run it on the base
#      and on the rewrite, then `measure-invocation.sh compare`.
#   2. The plugin's own eval cases (plugins/<plugin>/evals), run the same way
#      on the base and on the rewrite.
#   3. Semantic diff of the rewritten bodies, labeled by a fresh agent:
#        /docs-hygiene:compress compare ORIG_DIR NEW_DIR [REASONS]
# Paste this script's markdown table and the results of the steps above into
# the pull request body.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB="$TOOL_REPO/plugins/skill-quality/scripts/skill-frontmatter.sh"
CHECK_BIN="${SKILL_REWRITE_MEASURE_CHECK_BIN:-$TOOL_REPO/plugins/skill-quality/scripts/check-skill.sh}"
SCORE_BIN="${SKILL_REWRITE_MEASURE_SCORE_BIN:-$TOOL_REPO/plugins/skill-quality/scripts/measure-invocation.sh}"
ROOT="${SKILL_REWRITE_MEASURE_ROOT:-$TOOL_REPO}"
# A lexical score may fall this far (absolute) between snapshots before --compare fails.
TRIPWIRE_DROP="0.05"

usage() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 2
}

plugin="" phase="" compare=0 dry=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin)
      [[ $# -ge 2 ]] || die "--plugin needs a value"
      plugin="$2"
      shift 2
      ;;
    --phase)
      [[ $# -ge 2 ]] || die "--phase needs a value"
      phase="$2"
      shift 2
      ;;
    --compare)
      compare=1
      shift
      ;;
    --dry-run)
      dry=1
      shift
      ;;
    --help | -h)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[[ -n "$plugin" ]] || die "--plugin is required"
[[ "$plugin" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid plugin name: $plugin"
if ((compare)); then
  [[ -z "$phase" ]] || die "--compare and --phase are mutually exclusive"
else
  [[ "$phase" == "before" || "$phase" == "after" ]] || die "--phase must be before or after"
fi

skills_root="$ROOT/plugins/$plugin/skills"
probes_dir="$ROOT/plugins/$plugin/probes"
snap_dir="$ROOT/.work/skill-rewrite/$plugin"

list_skills() {
  local d name
  for d in "$skills_root"/*/; do
    [[ -f "${d}SKILL.md" ]] || continue
    name="$(basename "$d")"
    # A name outside this set would break the TSV columns and reach --compare's arithmetic.
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
      printf 'warning: skipping skill dir with an unsafe name: %q\n' "$name" >&2
      continue
    }
    printf '%s\n' "$name"
  done
  return 0
}

if ((compare)); then
  b="$snap_dir/before.tsv"
  a="$snap_dir/after.tsv"
  [[ -f "$b" && -f "$a" ]] || die "need both before.tsv and after.tsv under .work/skill-rewrite/$plugin (run --phase before and --phase after)"
  rc=0
  b_rc="$(awk -F'\t' '$1=="root"{print $4}' "$b")"
  a_rc="$(awk -F'\t' '$1=="root"{print $4}' "$a")"
  b_w="$(awk -F'\t' '$1=="root"{print $5}' "$b")"
  a_w="$(awk -F'\t' '$1=="root"{print $5}' "$a")"
  printf '### Skill rewrite measurement: %s\n\n' "$plugin"
  printf '| check | before | after |\n|---|---|---|\n'
  printf '| check-skill exit code | %s | %s |\n| check-skill WARN count | %s | %s |\n\n' "$b_rc" "$a_rc" "$b_w" "$a_w"
  if [[ "$b_rc" == "0" && "$a_rc" != "0" ]]; then
    rc=1
    printf 'TRIPWIRE: check-skill exit code turned non-zero (%s -> %s)\n\n' "$b_rc" "$a_rc"
  fi
  printf '| skill | desc chars (before > after) | body lines (before > after) | lexical (before > after) |\n|---|---|---|---|\n'
  tb=0 ta=0 lb=0 la=0
  while IFS=$'\t' read -r _ name adesc abody alex _; do
    [[ "$adesc" =~ ^[0-9]+$ && "$abody" =~ ^[0-9]+$ ]] || die "malformed after.tsv row for skill: $name"
    brow="$(awk -F'\t' -v n="$name" '$1=="skill" && $2==n' "$b")"
    if [[ -z "$brow" ]]; then
      printf '| %s | new > %s | new > %s | new > %s |\n' "$name" "$adesc" "$abody" "$alex"
      continue
    fi
    IFS=$'\t' read -r _ _ bdesc bbody blex _ <<<"$brow"
    [[ "$bdesc" =~ ^[0-9]+$ && "$bbody" =~ ^[0-9]+$ ]] || die "malformed before.tsv row for skill: $name"
    printf '| %s | %s > %s (%+d) | %s > %s (%+d) | %s > %s |\n' "$name" \
      "$bdesc" "$adesc" $((adesc - bdesc)) "$bbody" "$abody" $((abody - bbody)) "$blex" "$alex"
    tb=$((tb + bdesc))
    ta=$((ta + adesc))
    lb=$((lb + bbody))
    la=$((la + abody))
    if [[ "$blex" != "n/a" && "$alex" != "n/a" ]] &&
      awk -v b="$blex" -v a="$alex" -v t="$TRIPWIRE_DROP" 'BEGIN { exit !((b - a) > t + 1e-9) }'; then
      rc=1
      printf 'TRIPWIRE: %s lexical score fell %s -> %s (more than %s)\n' "$name" "$blex" "$alex" "$TRIPWIRE_DROP"
    fi
  done < <(awk -F'\t' '$1=="skill"' "$a")
  while IFS=$'\t' read -r _ name _; do
    awk -F'\t' -v n="$name" '$1=="skill" && $2==n { f=1 } END { exit !f }' "$a" ||
      printf '| %s | removed | removed | removed |\n' "$name"
  done < <(awk -F'\t' '$1=="skill"' "$b")
  printf '| **total (skills in both)** | %s > %s (%+d) | %s > %s (%+d) | |\n' \
    "$tb" "$ta" $((ta - tb)) "$lb" "$la" $((la - lb))
  exit "$rc"
fi

[[ -d "$skills_root" ]] || die "no skills root: plugins/$plugin/skills"

check_cmd=(bash "$CHECK_BIN" "$skills_root")
score_cmd=(bash "$SCORE_BIN" score "$probes_dir")

if ((dry)); then
  printf 'plugin: %s\nskills root: plugins/%s/skills\nsnapshot: .work/skill-rewrite/%s/%s.tsv (not written)\n' "$plugin" "$plugin" "$plugin" "$phase"
  printf 'skills:\n'
  list_skills | sed 's/^/  - /'
  printf 'commands:\n'
  printf '  check-skill.sh plugins/%s/skills\n' "$plugin"
  if [[ -d "$probes_dir" ]]; then
    printf '  measure-invocation.sh score plugins/%s/probes\n' "$plugin"
  else
    printf '  (no plugins/%s/probes: lexical score is n/a)\n' "$plugin"
  fi
  printf '  per skill: frontmatter description length; SKILL.md lines after the frontmatter\n'
  exit 0
fi

[[ -f "$LIB" ]] || die "missing $LIB"
# shellcheck source=../plugins/skill-quality/scripts/skill-frontmatter.sh
source "$LIB"
sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"

check_out="$(mktemp)"
trap 'rm -f "$check_out"' EXIT
check_rc=0
"${check_cmd[@]}" >"$check_out" 2>&1 || check_rc=$?
warns="$(grep -c '^WARN:' "$check_out" || true)"

score_json="[]"
if [[ -d "$probes_dir" ]] && command -v jq >/dev/null 2>&1; then
  if out="$(MEASURE_INVOCATION_REPO_ROOT="$ROOT" "${score_cmd[@]}" 2>/dev/null)"; then
    score_json="$(jq -c '[.skills[] | {listing_file, n: (.cases | length), ok: ([.cases[] | select(.correct == true)] | length)}]' <<<"$out")"
  else
    echo "warning: lexical scoring failed for plugins/$plugin/probes; every lexical score is n/a" >&2
  fi
fi

mkdir -p "$snap_dir"
tsv="$snap_dir/$phase.tsv"
{
  printf 'root\t%s\t%s\t%s\t%s\n' "$plugin" "$sha" "$check_rc" "$warns"
  while IFS= read -r s; do
    md="$skills_root/$s/SKILL.md"
    fm="$(skill_frontmatter::extract <"$md")"
    desc="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$fm")")"
    body="$(awk 'NR==1 && !/^---[[:space:]]*$/ { print 0; exit } /^---[[:space:]]*$/ && f<2 { f++; next } f>=2 { n++ } END { if (f>=2) print n+0 }' "$md")"
    lex="$(jq -r --arg f "plugins/$plugin/skills/$s/SKILL.md" '[.[] | select(.listing_file == $f and .n > 0)] | if length == 0 then "n/a" else (.[0].ok / .[0].n * 1000 | round / 1000 | tostring) end' <<<"$score_json")"
    printf 'skill\t%s\t%s\t%s\t%s\t%s\n' "$s" "${#desc}" "$body" "$lex" "$sha"
  done < <(list_skills)
} >"$tsv"

printf '### Skill rewrite measurement: %s (%s, at %s)\n\n' "$plugin" "$phase" "$sha"
printf '| skill | desc chars | body lines | lexical |\n|---|---|---|---|\n'
awk -F'\t' '$1=="skill" { printf "| %s | %s | %s | %s |\n", $2, $3, $4, $5 }' "$tsv"
printf '\ncheck-skill exit code: %s, WARN count: %s\nsnapshot: .work/skill-rewrite/%s/%s.tsv\n' "$check_rc" "$warns" "$plugin" "$phase"
