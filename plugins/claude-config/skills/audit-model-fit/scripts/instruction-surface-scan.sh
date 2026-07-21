#!/usr/bin/env bash
# Enumerate local Claude Code instruction surfaces and surface the grep-able
# model-fit smells for the audit-model-fit skill.
#
# Scans project + user CLAUDE.md, skill SKILL.md bodies (+ context files),
# agent definitions, .claude/rules/**/*.md, output styles, and hook scripts.
# Flags the two deterministically-detectable smells as CANDIDATES only —
# bare prohibitions (never/do not/must not) and oversized example-block files.
# The judgment (is a rationale present? is a step list over-prescriptive? does
# removing this cause mistakes?) stays in the skill body, never here.
#
# Modes:  (default) compact inventory + smell summary
#         --candidates  list each flagged file:line
#         --count       print total candidate-line count only
# Exit: always 0 (advisory).
set -u

usage() {
  cat <<'EOF'
instruction-surface-scan.sh — enumerate Claude Code instruction surfaces and
flag the grep-able model-fit smells (bare prohibitions, oversized example blocks).

Usage:
  instruction-surface-scan.sh [--candidates | --count | --help]

Modes:
  (default)     compact surface inventory + smell summary
  --candidates  list each flagged file:line (bounded to 200 lines)
  --count       print the total bare-prohibition candidate-line count only

Exit: always 0 (advisory — candidates require model judgment, not a verdict).
EOF
}

MODE="summary"
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--candidates) MODE="candidates" ;;
--count) MODE="count" ;;
"") ;;
*)
  usage >&2
  exit 0
  ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$repo_root" ]] && cd "$repo_root" || true

# Word-boundary bare-prohibition pattern (case-insensitive). A prohibition is
# only a smell when NO rationale accompanies it — that call is the model's; the
# script just locates the prohibitions.
PROHIBITION='(^|[^[:alnum:]])(never|do not|don'\''t|must not|shall not)([^[:alnum:]]|$)'
EXAMPLE_BLOCK_THRESHOLD=5

# Collect the prose surface files (NUL-safe) into an array to grep for smells.
surfaces=()

# CLAUDE_CONFIG_DIR relocates the whole ~/.claude tree; honor it so the scan
# reads the user-global CLAUDE.md actually loaded into the session.
user_config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
claude_md_count=0
for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md "$user_config_dir/CLAUDE.md"; do
  if [[ -f "$f" ]]; then
    surfaces+=("$f")
    claude_md_count=$((claude_md_count + 1))
  fi
done

skill_count=0
context_count=0
if [[ -d .claude/skills ]]; then
  while IFS= read -r -d '' f; do
    surfaces+=("$f")
    skill_count=$((skill_count + 1))
  done < <(find .claude/skills -name 'SKILL.md' -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    surfaces+=("$f")
    context_count=$((context_count + 1))
  done < <(find .claude/skills \( -path '*/context/*' -o -path '*/reference/*' \) -name '*.md' -print0 2>/dev/null)
fi

agent_count=0
while IFS= read -r -d '' f; do
  surfaces+=("$f")
  agent_count=$((agent_count + 1))
done < <(find .claude/agents -maxdepth 1 -name '*.md' -print0 2>/dev/null)

rule_count=0
while IFS= read -r -d '' f; do
  surfaces+=("$f")
  rule_count=$((rule_count + 1))
done < <(find .claude/rules -name '*.md' -print0 2>/dev/null)

style_count=0
while IFS= read -r -d '' f; do
  surfaces+=("$f")
  style_count=$((style_count + 1))
done < <(find .claude/output-styles -maxdepth 1 -name '*.md' -print0 2>/dev/null)

# Hook scripts are enumerated (counted) but NOT grep-scanned: a prompt-type hook's
# instruction text is embedded in code, where a "never/do not" grep is noise. The
# model reads the hook bodies by hand in the skill's Phase 2 instead.
hook_count="$(find .claude/hooks -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

# --- Candidate detection over the collected surfaces -----------------------
prohibition_lines=0
prohibition_files=0
oversized_example_files=0
candidate_out=""

for f in "${surfaces[@]}"; do
  # grep -c prints the count (0 on no match) and exits 1 on zero matches; the
  # exit code is irrelevant here, so no `|| echo 0` (which would append a second
  # line and break the arithmetic below).
  hits="$(grep -icE "$PROHIBITION" "$f" 2>/dev/null)"
  hits="${hits:-0}"
  if ((hits > 0)); then
    prohibition_lines=$((prohibition_lines + hits))
    prohibition_files=$((prohibition_files + 1))
    if [[ "$MODE" == "candidates" ]]; then
      while IFS= read -r line; do
        candidate_out+="$f:$line"$'\n'
      done < <(grep -inE "$PROHIBITION" "$f" 2>/dev/null | cut -c1-200)
    fi
  fi
  fences="$(grep -cE '^[[:space:]]*```' "$f" 2>/dev/null)"
  tags="$(grep -cE '<example>' "$f" 2>/dev/null)"
  blocks=$(((${fences:-0} / 2) + ${tags:-0}))
  if ((blocks > EXAMPLE_BLOCK_THRESHOLD)); then
    oversized_example_files=$((oversized_example_files + 1))
    if [[ "$MODE" == "candidates" ]]; then
      candidate_out+="$f:0: EXAMPLE-DENSE ($blocks blocks > $EXAMPLE_BLOCK_THRESHOLD)"$'\n'
    fi
  fi
done

if [[ "$MODE" == "count" ]]; then
  printf '%s\n' "$prohibition_lines"
  exit 0
fi

if [[ "$MODE" == "candidates" ]]; then
  if [[ -z "$candidate_out" ]]; then
    printf 'No grep-able candidates found.\n'
  else
    printf '%s' "$candidate_out" | head -n 200
  fi
  exit 0
fi

cat <<EOF
Instruction surfaces scanned (project + user):
CLAUDE.md files: $claude_md_count
Skill SKILL.md: $skill_count (context/reference files: $context_count)
Agent definitions: $agent_count
Rule files (.claude/rules): $rule_count
Output styles: $style_count
Hook scripts (.claude/hooks): $hook_count (counted only — read bodies by hand in Phase 2)

Grep-able candidate smells (judgment still required per finding):
Bare-prohibition lines (never/do not/must not/shall not): $prohibition_lines across $prohibition_files files
Example-dense files (>$EXAMPLE_BLOCK_THRESHOLD fenced/<example> blocks): $oversized_example_files files

Over-prescriptive step lists, stale model-era workarounds, and the
"would removing this cause mistakes?" bar are model judgment — not scanned here.
EOF
