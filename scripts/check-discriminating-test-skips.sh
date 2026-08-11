#!/usr/bin/env bash
# Gate: a *.test.sh that would vacate the only discriminating assertions in a
# case group must not call skip_case and exit 0. Optional platform skips are
# fine; a skip that costs the entire point of a case group must fail (or use
# fail_discriminating_skip) so CI cannot report green while proving nothing.
#
#   scripts/check-discriminating-test-skips.sh
#
# Two shapes are flagged in plugins/**/*.test.sh and .claude/hooks/*.test.sh:
#
#   1. skip_case whose reason matches the git copy-pairing vacuous-pass messages
#      this repo has already shipped — the canonical discriminating-skip defect.
#   2. skip_case on a line annotated with discriminating-skip-required: the
#      author marked the branch as load-bearing; skip_case there is forbidden.
#
# A flagged site passes when the line calls fail_discriminating_skip instead,
# or carries a documented exemption:
#   # discriminating-skip-ok: <reason>
# on the skip_case line, in the comment block immediately above it, or inside
# the enclosing if/else block.
#
# This is a grep-level tripwire, not a semantic proof — its job is to stop the
# regression where a discriminating branch quietly no-ops via skip_case.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

errors=0

mapfile -t test_files < <(find plugins .claude/hooks -type f -name '*.test.sh' 2>/dev/null | sort)

for test_file in "${test_files[@]}"; do

  out=$(awk '
    function is_annotated(l) { return l ~ /#[[:space:]]*discriminating-skip-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    function is_required(l) { return l ~ /#[[:space:]]*discriminating-skip-required:/ }
    function is_fail_disc(l) {
      return l ~ /fail_discriminating_skip/
    }
    function is_bad_skip(l) {
      return l ~ /skip_case/ &&
        (l ~ /did not pair/ || l ~ /did not produce both/)
    }
    {
      line = $0

      if (in_block) {
        if (line ~ /^[[:space:]]*if[[:space:]]/) depth++
        if (line ~ /^[[:space:]]*fi([[:space:]]*(#.*)?)?$/) depth--
        if (is_annotated(line)) block_annotated = 1
        if (is_required(line)) block_required = 1
        if (is_bad_skip(line) && !is_annotated(line)) block_bad = 1
        if (depth == 0) {
          if (block_bad && !block_annotated)
            printf "%d: discriminating skip via skip_case — use fail_discriminating_skip\n", block_start
          if (block_required && block_bad && !block_annotated)
            printf "%d: discriminating-skip-required branch uses skip_case\n", block_start
          in_block = 0
        }
        next
      }

      annotated_above = pending_annot
      required_above = pending_req
      if (is_comment(line)) {
        if (is_annotated(line)) pending_annot = 1
        if (is_required(line)) pending_req = 1
      } else {
        pending_annot = 0
        pending_req = 0
      }

      if (is_bad_skip(line)) {
        if (!is_annotated(line) && !annotated_above)
          printf "%d: discriminating skip via skip_case — use fail_discriminating_skip\n", NR
      }

      if (is_required(line) && !is_comment(line)) {
        in_block = 1
        depth = 1
        block_start = NR
        block_annotated = is_annotated(line)
        block_required = 1
        block_bad = 0
        next
      }

      if (line ~ /^[[:space:]]*if[[:space:]]/) {
        in_block = 1
        depth = 1
        block_start = NR
        block_annotated = is_annotated(line) || annotated_above
        block_required = is_required(line) || required_above
        block_bad = 0
        next
      }
    }
    END {
      if (in_block && block_bad && !block_annotated)
        printf "%d: discriminating skip via skip_case — use fail_discriminating_skip\n", block_start
    }
  ' "$test_file")

  if [[ -n "$out" ]]; then
    while IFS= read -r v; do
      echo "DISCRIMINATING TEST SKIP: ${test_file}:${v}" >&2
      errors=$((errors + 1))
    done <<<"$out"
  fi
done

if ((errors > 0)); then
  {
    echo
    echo "A skip that vacates discriminating coverage must call"
    echo "fail_discriminating_skip (failure + DISCRIMINATING SKIP marker), not"
    echo "skip_case. Documented exemptions carry '# discriminating-skip-ok:"
    echo "<reason>' at the site."
  } >&2
  exit 1
fi
echo "No discriminating skip_case sites found in plugin test entry scripts."
