#!/usr/bin/env bash
# Gate: a hook that skips because a CLI prerequisite is absent must make the
# skip visible. The prerequisite-visibility doctrine classifies absence as
# required (stop with remediation), optional (visible warn + skip), or
# not-applicable (quiet) — a quiet skip is only ever a deliberate,
# documented classification, never a default.
#
#   scripts/check-silent-skips.sh          fail if any hook entry script
#                                          silently skips on a missing CLI
#
# Two shapes are flagged in plugins/*/hooks/*.sh (entry scripts only —
# hook-utils.sh lib copies have their own sync gate and review; *.test.sh
# files exercise these patterns as fixtures):
#
#   1. same-line guard:   command -v X ... || exit 0    (also `return 0`, or
#                         a skip-named helper such as `|| emit_skipped`)
#   2. block guard:       if ! command -v X ...; then ... fi   where the block
#                         reaches `exit 0` / `return 0`
#
# A flagged site passes when the skip is visible — the guard line or block
# carries one of the sanctioned visibility calls (hook::emit_skip_notice,
# hook::emit_system_message, hook::notice_once, hook::require_jq, or a
# stderr write) — or when it is a documented quiet classification: an
# annotation comment `# silent-skip-ok: <reason>` on the guard line, in the
# comment block immediately above it, or inside the guard block. The
# annotation is the recorded decision; a bare quiet skip is a defect.
#
# This is a grep-level tripwire, not a semantic proof: it does not chase
# helper-function bodies and does not flag a positive-form
# `if command -v X; then ... else exit 0` (the current corpus uses the
# else-branch for its visible notice). Its job is to stop the historical
# regression — a new hook quietly no-op'ing when an optional CLI is absent.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

errors=0

for hook in plugins/*/hooks/*.sh; do
  base="${hook##*/}"
  case "$base" in
  hook-utils.sh | *.test.sh) continue ;;
  *) ;;
  esac
  [[ -f "$hook" ]] || continue

  out=$(awk '
    function is_annotated(l) { return l ~ /#[[:space:]]*silent-skip-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    function is_visible(l) {
      return l ~ /hook::emit_skip_notice/ || l ~ /hook::emit_system_message/ ||
        l ~ /hook::notice_once/ || l ~ /hook::require_jq/ || l ~ />&2/
    }
    {
      line = $0

      # Shape 2: block guard. Statement-per-line shell (shfmt-formatted), so
      # `if`/`fi` sit at line start; comment lines never open or close a block.
      if (in_block) {
        if (line ~ /^[[:space:]]*if[[:space:]]/) depth++
        if (line ~ /^[[:space:]]*fi([[:space:]]*(#.*)?)?$/) depth--
        if (is_visible(line)) block_visible = 1
        if (is_annotated(line)) block_annotated = 1
        if (line ~ /(^|[[:space:]])(exit|return)[[:space:]]+0([[:space:]]|$|;)/) block_skips = 1
        if (depth == 0) {
          if (block_skips && !block_visible && !block_annotated)
            printf "%d: silent block skip: `if ! command -v ...` reaches exit/return 0 with no visible notice\n", block_start
          in_block = 0
        }
        next
      }

      # An annotation anywhere in the contiguous comment block directly above
      # a guard sanctions that guard; any code line ends the pending block.
      annotated_above = pending_annot
      if (is_comment(line)) {
        if (is_annotated(line)) pending_annot = 1
      } else {
        pending_annot = 0
      }

      if (line ~ /^[[:space:]]*(el)?if[[:space:]]+!.*command -v/) {
        in_block = 1; depth = 1; block_start = NR
        block_visible = is_visible(line)
        block_annotated = is_annotated(line) || annotated_above
        block_skips = 0
        next
      }

      # Shape 1: same-line guard.
      if (line ~ /command -v/ &&
        (line ~ /\|\|[[:space:]]*exit[[:space:]]+0/ ||
          line ~ /\|\|[[:space:]]*return[[:space:]]+0/ ||
          line ~ /\|\|[[:space:]]*[A-Za-z_][A-Za-z0-9_:]*[Ss]kip/)) {
        if (!is_visible(line) && !is_annotated(line) && !annotated_above)
          printf "%d: silent skip: `command -v ... ||` quiet skip with no visible notice\n", NR
      }
    }
    END {
      if (in_block && block_skips && !block_visible && !block_annotated)
        printf "%d: silent block skip: unterminated `if ! command -v` block reaches exit/return 0 with no visible notice\n", block_start
    }
  ' "$hook")

  if [[ -n "$out" ]]; then
    while IFS= read -r v; do
      echo "SILENT SKIP: ${hook}:${v}" >&2
      errors=$((errors + 1))
    done <<<"$out"
  fi
done

if ((errors > 0)); then
  {
    echo
    echo "A missing-CLI skip must be visible (hook::emit_skip_notice /"
    echo "hook::emit_system_message / a stderr write) or carry a documented"
    echo "quiet classification: '# silent-skip-ok: <reason>' at the site."
  } >&2
  exit 1
fi
echo "No silent prerequisite skips found in hook entry scripts."
