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
#                                          an unlisted skip as PASS
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
#      path in the exemption list), never report PASS for the skip.
#
# A flagged site passes when the skip is visible — the guard line or block
# carries one of the sanctioned visibility calls (hook::emit_skip_notice,
# hook::emit_system_message, hook::notice_once, hook::require jq) — or when
# scripts/silent-skip-exemptions.txt records it as a quiet classification.
# An entry names the file and the guard (the tool after `command -v`, or the
# quoted ok "skip ..." message) with its reason; its format is in that file's
# header. An entry that matches no flagged site fails as stale.
#
# A bare stderr write (`>&2`) is not a sanctioned visibility call: every site
# this gate inspects is, by construction, an exit-0 skip path, and per the
# official Claude Code hooks reference
# (https://code.claude.com/docs/en/hooks#exit-code-0, re-fetched 2026-08-10,
# docs/contracts/hook-observability/) "Stderr from a hook that exits 0 goes
# to the debug log only, never the transcript, and Claude never sees it" — so
# it reaches neither the user nor the agent on any path this gate inspects.
# A `>&2`-only notice on such a path is invisible regardless of intent.
# Recheck when the hooks reference says exit-0 stderr reaches the transcript or
# the model.
#
# This is a grep-level tripwire, not a semantic proof: it does not chase
# helper-function bodies and does not flag a positive-form
# `if command -v X; then ... else exit 0` (the current corpus uses the
# else-branch for its visible notice). Its job is to stop the historical
# regression — a new hook quietly no-op'ing when an optional CLI is absent,
# or a self-test quietly scoring an unrun proof as PASS.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# shellcheck source=lib/read-list.sh
. scripts/lib/read-list.sh

EXEMPTIONS=scripts/silent-skip-exemptions.txt
errors=0

if [[ ! -f "$EXEMPTIONS" || ! -r "$EXEMPTIONS" ]]; then
  echo "check-silent-skips: exemption list not readable: ${EXEMPTIONS}" >&2
  exit 2
fi
entries=()
read_list::into entries "$EXEMPTIONS" --comments leading
declare -A exempt_by_site=()
declare -A exempt_hits=()
for entry in ${entries[@]+"${entries[@]}"}; do
  path="${entry%%[[:space:]]*}"
  rest="${entry#"$path"}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  if [[ "$rest" == '"'*'"'* ]]; then
    key="${rest#\"}"
    key="${key%%\"*}"
    reason="${rest#\""$key"\"}"
  else
    key="${rest%%[[:space:]]*}"
    reason="${rest#"$key"}"
  fi
  reason="${reason#"${reason%%[![:space:]]*}"}"
  if [[ -z "$key" || -z "$reason" ]]; then
    echo "MALFORMED EXEMPTION: ${EXEMPTIONS}: '${entry}' has no reason; write '<path> <guard>  <reason>'" >&2
    errors=$((errors + 1))
    continue
  fi
  exempt_by_site["$path"$'\t'"$key"]="$entry"
done

AWK_SITE_LIB='
    function emit(f, n, key, msg) { printf "%s\t%d\t%s\t%s\n", f, n, (key == "" ? "-" : key), msg }
    function guarded_tool(l, tok) {
      if (!match(l, /command -v[[:space:]]+[^[:space:];|&)]+/)) return ""
      tok = substr(l, RSTART, RLENGTH)
      sub(/^command -v[[:space:]]+/, "", tok)
      gsub(/["\047]/, "", tok)
      return tok
    }
'

scan_hook() {
  awk "$AWK_SITE_LIB"'
    function is_visible(l) {
      return l ~ /hook::emit_skip_notice/ || l ~ /hook::emit_system_message/ ||
        l ~ /hook::notice_once/ || l ~ /hook::require(_jq_blocking| jq)/
    }
    function flag_open_block() {
      if (in_block && block_skips && !block_visible)
        emit(file, block_start, block_tool, "silent block skip: unterminated `if ! command -v` block reaches exit/return 0 with no visible notice")
    }
    function reset_file() {
      in_block = 0; depth = 0
      block_visible = 0; block_skips = 0; block_start = 0; block_tool = ""
    }
    FNR == 1 {
      if (NR > 1) flag_open_block()
      file = FILENAME
      reset_file()
    }
    {
      line = $0

      # Shape 2: block guard. Statement-per-line shell (shfmt-formatted), so
      # `if`/`fi` sit at line start; comment lines never open or close a block.
      if (in_block) {
        if (line ~ /^[[:space:]]*if[[:space:]]/) depth++
        if (line ~ /^[[:space:]]*fi([[:space:]]*(#.*)?)?$/) depth--
        if (is_visible(line)) block_visible = 1
        if (line ~ /(^|[[:space:]])(exit|return)[[:space:]]+0([[:space:]]|$|;)/) block_skips = 1
        if (depth == 0) {
          if (block_skips && !block_visible)
            emit(FILENAME, block_start, block_tool, "silent block skip: `if ! command -v ...` reaches exit/return 0 with no visible notice")
          in_block = 0
        }
        next
      }

      if (line ~ /^[[:space:]]*(el)?if[[:space:]]+!.*command -v/) {
        in_block = 1; depth = 1; block_start = FNR
        block_visible = is_visible(line)
        block_tool = guarded_tool(line)
        block_skips = 0
        next
      }

      # Shape 1: same-line guard.
      if (line ~ /command -v/ &&
        (line ~ /\|\|[[:space:]]*exit[[:space:]]+0/ ||
          line ~ /\|\|[[:space:]]*return[[:space:]]+0/ ||
          line ~ /\|\|[[:space:]]*[A-Za-z_][A-Za-z0-9_:]*[Ss]kip/)) {
        if (!is_visible(line))
          emit(FILENAME, FNR, guarded_tool(line), "silent skip: `command -v ... ||` quiet skip with no visible notice")
      }
    }
    END {
      flag_open_block()
    }
  ' "$@"
}

scan_test_skip_pass() {
  awk "$AWK_SITE_LIB"'
    function is_skip_ok(l) {
      # Match at a shell command boundary (not only line-start), so one-line
      # forms like `if x; then ok "skip ..."; fi` are caught too.
      return l ~ /(^|[^[:alnum:]_])ok[[:space:]]+["'\'']skip[[:space:]]/
    }
    function skip_message(l, q, rest, end) {
      match(l, /(^|[^[:alnum:]_])ok[[:space:]]+["'\'']skip[[:space:]]/)
      rest = substr(l, RSTART + RLENGTH - 6)
      q = substr(rest, 1, 1)
      rest = substr(rest, 2)
      end = index(rest, q)
      return end ? substr(rest, 1, end - 1) : rest
    }
    {
      line = $0
      if (is_skip_ok(line))
        emit(FILENAME, FNR, skip_message(line), "skip scored as PASS via ok \"skip ...\" — fail closed or list it in '"$EXEMPTIONS"'")
    }
  ' "$@"
}

report_hits() {
  local file line key msg entry
  [[ -n "$1" ]] || return 0
  while IFS=$'\t' read -r file line key msg; do
    entry="${exempt_by_site["$file"$'\t'"$key"]:-}"
    if [[ -n "$entry" && -z "${exempt_hits["$entry"]:-}" ]]; then
      exempt_hits["$entry"]=1
      read_list::mark_used "$entry"
      continue
    fi
    [[ -n "$entry" ]] && msg="${msg} (its ${EXEMPTIONS} entry already covers an earlier guard on ${key} in this file)"
    echo "SILENT SKIP: ${file}:${line}: ${msg}" >&2
    errors=$((errors + 1))
  done <<<"$1"
}

hooks=()
for hook in plugins/*/hooks/*.sh; do
  case "${hook##*/}" in
  hook-utils.sh | *.test.sh) continue ;;
  *) ;;
  esac
  [[ -f "$hook" ]] || continue
  hooks+=("$hook")
done
if ((${#hooks[@]} > 0)); then
  report_hits "$(scan_hook "${hooks[@]}")"
fi

test_files=()
for test_file in scripts/*.test.sh; do
  # An unmatched glob arrives as its own literal text, which is not a file, so
  # the same `-f` guard the hook loop above uses covers the empty case here too.
  # The silent-skip unit suite embeds shape-3 fixtures as quoted strings in its
  # own body; scanning it would false-positive on those embeddings. Shape 3 is
  # still exercised via the suite's throwaway fixtures under /tmp.
  [[ -f "$test_file" && "$test_file" != scripts/check-silent-skips.test.sh ]] || continue
  test_files+=("$test_file")
done
if ((${#test_files[@]} > 0)); then
  report_hits "$(scan_test_skip_pass "${test_files[@]}")"
fi

stale=()
read_list::stale_to stale entries
for entry in ${stale[@]+"${stale[@]}"}; do
  read_list::stale_line "$EXEMPTIONS" "$entry" "matches no quiet skip this gate flags; delete the entry"
  errors=$((errors + 1))
done

if ((errors > 0)); then
  {
    echo
    echo "A missing-CLI skip must be visible (hook::emit_skip_notice /"
    echo "hook::emit_system_message / hook::notice_once / hook::require jq)"
    echo "or carry a documented quiet classification: an entry in"
    echo "${EXEMPTIONS} naming the file, the guard and the reason."
    echo "A bare stderr write is not sufficient — stderr on exit 0 is never"
    echo "shown to the user or the agent (docs/contracts/hook-observability/)."
    echo
    echo "A scripts/*.test.sh that cannot run an assertion must fail closed"
    echo "(or be listed in ${EXEMPTIONS}), never score the skip as PASS"
    echo "via ok \"skip ...\"."
  } >&2
  exit 1
fi
echo "No silent prerequisite skips found in hook entry scripts or scripts/*.test.sh."
