#!/usr/bin/env bash
# Skill portability verifier.
#
# Per .claude/rules/skill/encapsulation.md "Skill portability gate" — opt-in via BEHAVIOR.md.
# Static-analysis only (no runtime emulation). Exits 0 = skill is portable
# for plugin lift-and-shift; 1 = portability violation.
#
# Usage:
#   bash tools/skill-contract/skill-portability-lib.sh <skill-name>
#
# Test-only override: SKILL_PORTABILITY_SKILLS_ROOT changes the skills-root
# directory (default: <repo>/.claude/skills). The portability test suite sets
# it to a TEST_TMPDIR so synthetic fixtures never materialize in the live
# skills tree — CC's skill scanner would otherwise pick them up mid-run, and a
# killed run would leak __test_* dirs. Real-skill invocations leave it unset.
#
# Checks (all required):
#   1. BEHAVIOR.md exists                        (only when behavior/ dir present — opt-in)
#   2. Symmetry: every declared point is cited by SKILL.md or an action body
#   3. Default present: every point dir has a default.<ext> file or default/ folder
#   4. No machine-local paths in SKILL.md / BEHAVIOR.md / behavior/**
#   5. No escape paths (../../) in behavior/** (regex matches `../../`; a single
#      `../` from behavior/<point>/ stays inside the skill — sibling-point refs
#      are legal, real escapes need `../../../` which contains the `../../` token)
#   6. Frontmatter validity: override files declare @behavior matching parent dir
#   7. v2 deny-list: no repo-specific identifiers in SKILL.md / BEHAVIOR.md / behavior/*/default.<ext>
#      (HARD-FAIL = exit 1, WARN = log only). Source: tools/skill-contract/repo-specific-identifiers.txt.
#      Per-line opt-out: append `<!-- portability-scan-ignore-line -->` to a line to skip its
#      tokens (use for meta-prose describing what the team layer holds).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT" ]]; then
  printf 'Error: not in a git repo\n' >&2
  exit 2
fi

# Source the hardcoded-path-patterns lib for machine-local-path detection
if [[ -f "$REPO_ROOT/tools/shared/path-detection/hardcoded-path-patterns.sh" ]]; then
  # shellcheck source=../../shared/path-detection/hardcoded-path-patterns.sh
  source "$REPO_ROOT/tools/shared/path-detection/hardcoded-path-patterns.sh"
fi

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

skill_name="${1:?Usage: test-skill-portability.sh <skill-name>}"
skill_dir="${SKILL_PORTABILITY_SKILLS_ROOT:-$REPO_ROOT/.claude/skills}/$skill_name"

if [[ ! -d "$skill_dir" ]]; then
  err "Skill not found: $skill_dir"
  exit 1
fi

# Portability is opt-in via BEHAVIOR.md. Plugin-ref-only skills (behavior/third-party/
# without BEHAVIOR.md) are not adopters — silent exit.
if [[ ! -f "$skill_dir/BEHAVIOR.md" ]]; then
  if [[ -d "$skill_dir/behavior" ]]; then
    while IFS= read -r point_dir; do
      [[ -z "$point_dir" ]] && continue
      point_name="$(basename "$point_dir")"
      [[ "$point_name" == "third-party" ]] && continue
      warn "Skill '$skill_name' has behavior/$point_name/ but no BEHAVIOR.md — add manifest or remove point dir"
    done < <(find "$skill_dir/behavior" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi
  exit 0
fi

# 1. BEHAVIOR.md exists (verified above)
note "BEHAVIOR.md present for $skill_name"

# 2. Enumerate declared points
declared_points=()
while IFS= read -r line; do
  # Match `## Point: <skill>.<point-id>`
  if [[ "$line" =~ ^##[[:space:]]Point:[[:space:]]+([a-zA-Z0-9_.-]+) ]]; then
    declared_points+=("${BASH_REMATCH[1]}")
  fi
done <"$skill_dir/BEHAVIOR.md"

if [[ ${#declared_points[@]} -eq 0 ]]; then
  warn "BEHAVIOR.md declares no points (## Point: <id> headings). Manifest is empty."
fi

# 3. Symmetry: every declared point must be cited somewhere in SKILL.md or actions/*.md
search_corpus=()
[[ -f "$skill_dir/SKILL.md" ]] && search_corpus+=("$skill_dir/SKILL.md")
[[ -d "$skill_dir/actions" ]] && while IFS= read -r f; do search_corpus+=("$f"); done < <(find "$skill_dir/actions" -name '*.md' -type f 2>/dev/null)
[[ -d "$skill_dir/reference" ]] && while IFS= read -r f; do search_corpus+=("$f"); done < <(find "$skill_dir/reference" -name '*.md' -type f 2>/dev/null)

for point in "${declared_points[@]}"; do
  found=0
  for f in "${search_corpus[@]}"; do
    if grep -qF "$point" "$f" 2>/dev/null; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    err "Point '$point' declared in BEHAVIOR.md but not cited by SKILL.md or any action/reference file"
  fi
done

# 4. Default present: every point dir under behavior/ has default.<ext> or default/
if [[ -d "$skill_dir/behavior" ]]; then
  while IFS= read -r point_dir; do
    [[ -z "$point_dir" ]] && continue
    has_default=0
    for ext in md yaml yml json sh; do
      [[ -f "$point_dir/default.$ext" ]] && {
        has_default=1
        break
      }
    done
    [[ -d "$point_dir/default" ]] && has_default=1
    if [[ "$has_default" -eq 0 ]]; then
      err "Point dir '$point_dir' missing default.<ext> or default/ subfolder"
    fi
  done < <(find "$skill_dir/behavior" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# 5. No machine-local paths in SKILL.md, BEHAVIOR.md, behavior/**
if declare -F hpp::scan_text >/dev/null 2>&1; then
  while IFS= read -r scan_file; do
    [[ -z "$scan_file" ]] && continue
    content="$(cat "$scan_file" 2>/dev/null)"
    findings="$(hpp::scan_text "$content" "$scan_file" 2>/dev/null)"
    if [[ -n "$findings" ]]; then
      err "Machine-local path in $scan_file: $findings"
    fi
  done < <(find "$skill_dir/SKILL.md" "$skill_dir/BEHAVIOR.md" "$skill_dir/behavior" -type f 2>/dev/null)
fi

# 6. No escape paths (../../) in behavior/** override files
if [[ -d "$skill_dir/behavior" ]]; then
  while IFS= read -r f; do
    if grep -qE '\.\./\.\.' "$f" 2>/dev/null; then
      err "Escape path (../../) in $f — overrides must stay within skill dir"
    fi
  done < <(find "$skill_dir/behavior" -type f 2>/dev/null)
fi

# 7. Override-file frontmatter validity: @behavior matches parent dir name
if [[ -d "$skill_dir/behavior" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    parent_dir_name="$(basename "$(dirname "$f")")"
    expected_point="$skill_name.$parent_dir_name"
    # Look for @behavior: <value> in file (YAML frontmatter, JSON field, or magic comment)
    found_behavior="$(grep -m 1 -E "['\"]?@behavior['\"]?[[:space:]]*:" "$f" 2>/dev/null | sed -E "s/.*['\"]?@behavior['\"]?[[:space:]]*:[[:space:]]*['\"]?([a-zA-Z0-9._-]+)['\"]?.*/\1/" | tr -d '\r' | head -1)"
    if [[ -z "$found_behavior" ]]; then
      warn "Override file $f missing @behavior declaration"
    elif [[ "$found_behavior" != "$expected_point" ]]; then
      err "Override file $f declares @behavior: $found_behavior but parent dir implies $expected_point"
    fi
  done < <(find "$skill_dir/behavior" -type f \( -name 'default.*' -o -name 'team.*' -o -name 'user.*' \) 2>/dev/null)
fi

# 8. v2 deny-list scan: repo-specific identifiers in SKILL.md / BEHAVIOR.md / behavior/*/default.<ext>
DENYLIST_FILE="$REPO_ROOT/tools/skill-contract/repo-specific-identifiers.txt"
if [[ -f "$DENYLIST_FILE" ]]; then
  hard_tokens=()
  warn_tokens=()
  while IFS= read -r raw_line; do
    raw_line="${raw_line%$'\r'}"
    case "$raw_line" in
      '#'* | '') continue ;;
      'H:'*) hard_tokens+=("${raw_line#H:}") ;;
      'W:'*) warn_tokens+=("${raw_line#W:}") ;;
    esac
  done <"$DENYLIST_FILE"

  # Build list of scanned files: SKILL.md + BEHAVIOR.md + behavior/<point>/default.<ext> (NOT team/user)
  scan_files=()
  [[ -f "$skill_dir/SKILL.md" ]] && scan_files+=("$skill_dir/SKILL.md")
  [[ -f "$skill_dir/BEHAVIOR.md" ]] && scan_files+=("$skill_dir/BEHAVIOR.md")
  if [[ -d "$skill_dir/behavior" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      base="$(basename "$f")"
      # Only default.<ext> (not team.<ext> / user.<ext> / per-file default-dir contents)
      case "$base" in
        default.*) scan_files+=("$f") ;;
      esac
    done < <(find "$skill_dir/behavior" -type f 2>/dev/null)
  fi

  for scan_file in "${scan_files[@]}"; do
    rel_file="${scan_file#"$REPO_ROOT"/}"
    line_num=0
    while IFS= read -r file_line || [[ -n "$file_line" ]]; do
      line_num=$((line_num + 1))
      # Per-line opt-out marker
      if [[ "$file_line" == *'<!-- portability-scan-ignore-line -->'* ]]; then
        continue
      fi
      for token in "${hard_tokens[@]}"; do
        if [[ "$file_line" == *"$token"* ]]; then
          err "Repo-specific identifier '$token' (HARD-FAIL) in $rel_file:$line_num"
        fi
      done
      for token in "${warn_tokens[@]}"; do
        if [[ "$file_line" == *"$token"* ]]; then
          warn "Stack-choice token '$token' (WARN) in $rel_file:$line_num"
        fi
      done
    done <"$scan_file"
  done
fi

# Summary
printf '\n'
if [[ "$FAILED" -gt 0 ]]; then
  printf 'PORTABILITY: FAIL — %d error(s), %d warning(s)\n' "$FAILED" "$WARNINGS" >&2
  exit 1
fi
printf 'PORTABILITY: PASS — 0 errors, %d warning(s)\n' "$WARNINGS"
exit 0
