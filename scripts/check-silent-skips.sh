#!/usr/bin/env bash
# Gate: a hook that skips because a CLI prerequisite is absent must make the
# skip visible. The prerequisite-visibility doctrine classifies absence as
# required (stop with remediation), optional (visible warn + skip), or
# not-applicable (quiet) — a quiet skip is only ever a deliberate,
# documented classification, never a default.
#
#   scripts/check-silent-skips.sh          fail if any hook entry script
#                                          silently skips on a missing CLI,
#                                          or if a scripts/*.test.sh scores
#                                          a skip as PASS without annotation
#
# Two shapes are flagged in plugins/*/hooks/*.sh (entry scripts only —
# hook-utils.sh lib copies have their own sync gate and review; *.test.sh
# files under hooks/ exercise these patterns as fixtures):
#
#   1. same-line guard:   command -v X ... || exit 0    (also `return 0`, or
#                         a skip-named helper such as `|| emit_skipped`)
#   2. block guard:       if ! command -v X ...; then ... fi   where the block
#                         reaches `exit 0` / `return 0`
#
# A third shape is flagged in scripts/*.test.sh (self-tests that own
# load-bearing historical proofs — #2807):
#
#   3. skip-scored-as-pass:  ok "skip ..." / ok 'skip ...'
#      A test that cannot run its assertion must fail (or declare the soft
#      path with `# silent-skip-ok: <reason>`), never report PASS for the skip.
#
# A flagged site passes when the skip is visible — the guard line or block
# carries one of the sanctioned visibility calls (hook::emit_skip_notice,
# hook::emit_system_message, hook::notice_once, hook::require_jq) — or when
# it is a documented quiet classification: an annotation comment
# `# silent-skip-ok: <reason>` on the guard line, in the comment block
# immediately above it, or inside the guard block. The annotation is the
# recorded decision; a bare quiet skip is a defect.
#
# A bare stderr write (`>&2`) is NOT a sanctioned visibility call: every site
# this gate inspects is, by construction, an exit-0 skip path, and per the
# official Claude Code hooks reference (re-fetched 2026-08-10,
# docs/conventions/hook-observability/) "Stderr from a hook that exits 0 goes
# to the debug log only, never the transcript, and Claude never sees it" — so
# it reaches neither the user nor the agent on any path this gate inspects.
# A `>&2`-only notice on such a path is invisible regardless of intent.
# (Before 2026-08-10 this comment said such stderr was "discarded entirely";
# the debug log is the one place it does survive, which changes nothing for
# the gate — a debug-only sink is not a visibility surface.)
#
# This is a grep-level tripwire, not a semantic proof: it does not chase
# helper-function bodies and does not flag a positive-form
# `if command -v X; then ... else exit 0` (the current corpus uses the
# else-branch for its visible notice). Its job is to stop the historical
# regression — a new hook quietly no-op'ing when an optional CLI is absent,
# or a self-test quietly scoring an unrun proof as PASS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

errors=0

scan_hook() {
  local hook="$1"
  awk '
    function is_annotated(l) { return l ~ /#[[:space:]]*silent-skip-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    function is_visible(l) {
      return l ~ /hook::emit_skip_notice/ || l ~ /hook::emit_system_message/ ||
        l ~ /hook::notice_once/ || l ~ /hook::require_jq/
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
  ' "$hook"
}

# Shape 3: a self-test that scores a skip as PASS. Message must start with
# "skip " / 'skip ' (space-delimited) so descriptions like
# `ok "skip-named-helper ... fails"` are not flagged.
scan_test_skip_pass() {
  local test_file="$1"
  awk '
    function is_annotated(l) { return l ~ /#[[:space:]]*silent-skip-ok:/ }
    function is_comment(l) { return l ~ /^[[:space:]]*#/ }
    function is_skip_ok(l) {
      # Match at a shell command boundary (not only line-start), so one-line
      # forms like `if x; then ok "skip ..."; fi` are caught too.
      return l ~ /(^|[^[:alnum:]_])ok[[:space:]]+["'\'']skip[[:space:]]/
    }
    {
      line = $0
      annotated_above = pending_annot
      if (is_comment(line)) {
        if (is_annotated(line)) pending_annot = 1
      } else {
        pending_annot = 0
      }
      if (is_skip_ok(line) && !is_annotated(line) && !annotated_above)
        printf "%d: skip scored as PASS via ok \"skip ...\" — fail closed or annotate with # silent-skip-ok:\n", NR
    }
  ' "$test_file"
}

report_hits() {
  local path="$1"
  local out="$2"
  if [[ -n "$out" ]]; then
    while IFS= read -r v; do
      echo "SILENT SKIP: ${path}:${v}" >&2
      errors=$((errors + 1))
    done <<<"$out"
  fi
}

for hook in plugins/*/hooks/*.sh; do
  base="${hook##*/}"
  case "$base" in
  hook-utils.sh | *.test.sh) continue ;;
  *) ;;
  esac
  [[ -f "$hook" ]] || continue
  report_hits "$hook" "$(scan_hook "$hook")"
done

shopt -s nullglob
for test_file in scripts/*.test.sh; do
  [[ -f "$test_file" ]] || continue
  # The silent-skip unit suite embeds shape-1/2 fixtures as quoted strings;
  # scanning it for hook guards would false-positive. Shape 3 still applies.
  report_hits "$test_file" "$(scan_test_skip_pass "$test_file")"
done
shopt -u nullglob

if ((errors > 0)); then
  {
    echo
    echo "A missing-CLI skip must be visible (hook::emit_skip_notice /"
    echo "hook::emit_system_message / hook::notice_once / hook::require_jq)"
    echo "or carry a documented quiet classification:"
    echo "'# silent-skip-ok: <reason>' at the site. A bare stderr write is"
    echo "NOT sufficient — stderr on exit 0 is never shown to the user or"
    echo "the agent (docs/conventions/hook-observability/)."
    echo
    echo "A scripts/*.test.sh that cannot run an assertion must fail closed"
    echo "(or annotate with '# silent-skip-ok: <reason>'), never score the"
    echo "skip as PASS via ok \"skip ...\"."
  } >&2
  exit 1
fi
echo "No silent prerequisite skips found in hook entry scripts or scripts/*.test.sh."
