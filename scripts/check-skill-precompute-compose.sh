#!/usr/bin/env bash
# Gate: a skill whose ## Pre-computed context block contains a git command AND
# more than one inline `!`command`` injection line is refused in worktree-
# isolated agents (#1619). Adding a second precompute line silently breaks
# such skills — CI stays green, normal sessions render fine, only isolated
# agents fail.
#
#   scripts/check-skill-precompute-compose.sh --all
#   scripts/check-skill-precompute-compose.sh <base-ref>
#   scripts/check-skill-precompute-compose.sh --paths FILE...
#
# Default mode is warn-only (exit 0, prints violations) until the #1619
# remediation wave graduates the gate to --strict. Pass --strict to fail closed.
#
# Exit 0 = clean or warn-only violations; 1 = violations in --strict mode;
# 2 = usage / environment error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2

STRICT=0
POSITIONAL=()

usage() {
  printf 'usage: check-skill-precompute-compose.sh --all | <base-ref> | --paths FILE...\n' >&2
  printf '       [--strict]  fail closed on violations (default: warn-only)\n' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --strict)
    STRICT=1
    shift
    ;;
  -h | --help) usage ;;
  -- | --all | --paths)
    POSITIONAL+=("$1")
    shift
    break
    ;;
  *)
    POSITIONAL+=("$1")
    shift
    ;;
  esac
done
POSITIONAL+=("$@")

if [[ ${#POSITIONAL[@]} -eq 0 ]]; then
  usage
fi

first="${POSITIONAL[0]}"
rest=("${POSITIONAL[@]:1}")

# precompute_block <file> — print the ## Pre-computed context section body.
precompute_block() {
  awk '
    /^## Pre-computed context[[:space:]]*$/ { in_block = 1; next }
    in_block && /^## / { in_block = 0 }
    in_block { print }
  ' "$1"
}

# line_has_git <line> — git appears as a command (word-boundary), not prose.
line_has_git() {
  grep -qE '(^|[[:space:]|`])git([[:space:]]|$|[|;&])' <<<"$1"
}

# scan_skill <skill_md> — print violation message on stdout when found.
scan_skill() {
  local skill_md="$1"
  local block line_count=0 git_count=0
  block="$(precompute_block "$skill_md")"
  if [[ -z "${block//[[:space:]]/}" ]]; then
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    # shellcheck disable=SC2016  # ERE matches literal backticks around precompute injections
    if grep -qE '!`[^`]+`' <<<"$line"; then
      line_count=$((line_count + 1))
      if line_has_git "$line"; then
        git_count=1
      fi
    fi
  done <<<"$block"
  if ((line_count > 1 && git_count == 1)); then
    printf 'VIOLATION: %s — %d precompute lines with a git command (#1619 composition rule)\n' \
      "$skill_md" "$line_count"
    return 1
  fi
  return 0
}

# The base ref is validated HERE, in the parent shell, and the diff itself is
# taken through scripts/lib/changed-files.sh. Both halves answer the same
# failure: a `mapfile` fed from a process substitution sees only the READ's
# status, so neither an `exit 2` inside nor a failed `git diff` reaches the
# parent, which saw nothing but an empty `targets` and scanned zero files at
# exit 0. Validating the ref catches the typo'd branch (#3377); the shared
# resolver catches everything else a diff can fail on (a shallow clone missing
# an object, a corrupt pack, an unreadable index), because a failed diff is its
# own non-zero return rather than an empty scope.
targets=()
case "$first" in
--all)
  mapfile -t targets < <(find plugins -path 'plugins/*/skills/*/SKILL.md' -type f 2>/dev/null | sort)
  ;;
--paths)
  targets=("${rest[@]}")
  ;;
*)
  if ! changed_files::verify_base "$first"; then
    printf 'Error: base ref %s is not a valid commit\n' "$first" >&2
    exit 2
  fi
  # Diff on plugins/ then filter the skill path in-script: a `plugins/*/skills/`
  # git pathspec does not match under git's default (non-pathname) globbing.
  changed=()
  changed_files::into changed "$first" -- 'plugins/' || exit 2
  for f in ${changed[@]+"${changed[@]}"}; do
    case "$f" in
    plugins/*/skills/*/SKILL.md)
      # A `case` glob's `*` spans `/`, so re-check the depth: only a SKILL.md
      # exactly at plugins/<plugin>/skills/<skill>/ is a target.
      rest_path="${f#plugins/}"
      rest_path="${rest_path#*/skills/}"
      [[ "$rest_path" == "${rest_path%%/*}/SKILL.md" ]] || continue
      targets+=("$f")
      ;;
    *) ;;
    esac
  done
  ;;
esac

violations=0
scanned=0

for skill_md in "${targets[@]}"; do
  [[ -f "$skill_md" ]] || continue
  scanned=$((scanned + 1))
  if ! scan_skill "$skill_md"; then
    violations=$((violations + 1))
  fi
done

if ((scanned == 0)); then
  echo "No skill SKILL.md files in scope — nothing to gate."
  exit 0
fi

printf '\n%d skill(s) scanned, %d violation(s).\n' "$scanned" "$violations"

if ((violations > 0)); then
  if ((STRICT == 1)); then
    echo "Strict mode: failing." >&2
    exit 1
  fi
  echo "Warn-only mode: violations reported but step passes (use --strict to fail)." >&2
fi
exit 0
