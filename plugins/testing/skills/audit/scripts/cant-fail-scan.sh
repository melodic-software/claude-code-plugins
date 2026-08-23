#!/usr/bin/env bash
# cant-fail-scan.sh — deterministic detector for tests that cannot fail.
#
# Three rules, v1 (ids are the qualified detector-findings form; the per-file
# engine and its heuristics live in cant-fail-scan.awk next to this driver):
#
#   testing/audit/rule-zero-assertion        a runnable test body containing 0
#                                            assertion tokens (threshold: 0).
#   testing/audit/rule-recomputed-expectation an equality assertion whose actual
#                                            and expected sides are the identical
#                                            expression, i.e. the expected value
#                                            is recomputed rather than stated
#                                            (threshold: >= 1 such assertion).
#                                            v1 detects the decidable core —
#                                            textually identical sides — not
#                                            every recomputation shape.
#   testing/audit/rule-mock-only-oracle      a test constructing mocks whose
#                                            every assertion is a mock-interaction
#                                            assertion, with no assertion on a
#                                            real collaborator (threshold: 100%).
#                                            Interaction-style tests are the known
#                                            benign case, so this rule is advisory
#                                            in --check unless --strict.
#
# Ecosystems v1: JS/TS (*.test.* / *.spec.*), Python (test_*.py / *_test.py),
# C# (*Test.cs / *Tests.cs). Bash *.test.sh is deliberately out of scope: the
# repo-level incumbent scripts/check-discriminating-test-skips.sh owns the
# can't-fail shape that matters there (a skip vacating a discriminating case).
#
# Skipped tests (it.skip/x-prefixed/@skip/[Fact(Skip=…)]/[Ignore…]) are not
# judged — a test that does not run is the skip gate's concern, not this
# rule set's. A finding is exempted by an in-file annotation
# `cant-fail-ok: <reason>` on the test's declaration line, the line above it,
# or inside the body — the same recorded-decision shape as the incumbent
# discriminating-skip-ok annotation. Exemptions are counted, never silent.
#
# Remediation posture is REPAIR, not pruning: every Action proposes an
# assertion; none proposes deleting a test.
#
# Modes:
#   (default)    human-readable findings + coverage denominator; exit 0 on a
#                completed scan (advisory), 2 on an environment/scan gap
#   --check      gate mode, fail closed: exit 1 when a gating rule fired
#                (zero-assertion / recomputed-expectation; --strict adds
#                mock-only-oracle), exit 2 when the scan could not run, could
#                not fully read its inputs (unreadable files, walk errors), or
#                examined 0 test files (a wrong or empty root and a healthy
#                suite must not share an exit code), exit 0 only for a fully
#                read, finding-free scan that examined at least one test file
#   --findings   emit a findings file conforming to the detector-findings
#                contract on stdout (coverage block on stderr); the caller
#                resolves the destination per the contract
#   --count      integer finding count on stdout, coverage on stderr
#   --strict     with --check: mock-only-oracle findings gate too
#   --help
#
# Scan-root resolution: $CANT_FAIL_SCAN_ROOT (sanctioned operator lever, not a
# test-only seam), else the cwd's git toplevel, else $CLAUDE_PROJECT_DIR.
# Never $PWD: an unresolved root refuses (exit 2) rather than sweeping an
# unknown tree — a completed-looking scan of the wrong tree is
# indistinguishable from a clean bill.
#
# Every run reports a DENOMINATOR (coverage block): files enumerated and
# examined per ecosystem, test blocks parsed, exemptions, and what could not
# be read. "0 findings" over 0 examined files is a scan of nothing and is
# never reported as a clean bill.
set -uo pipefail

usage() {
  cat <<'EOF'
cant-fail-scan.sh — detect tests that cannot fail.

Usage: cant-fail-scan.sh [--check [--strict] | --findings | --count | --help]

  (no arg)    print one finding line per detection, then the coverage block; exit 0 (2 on scan gap)
  --check     exit 1 when a gating rule fired, 2 when the scan could not run, could not fully
              read its inputs, or examined 0 test files, 0 only for a fully read finding-free
              scan of at least one test file (fail closed)
  --strict    with --check: mock-only-oracle findings gate too (advisory otherwise)
  --findings  emit a detector-findings-conforming findings file on stdout; coverage on stderr;
              refuses (exit 2) when no test file was examined or no branch is checked out
  --count     integer finding count on stdout, coverage block on stderr

Rules v1: testing/audit/rule-zero-assertion, testing/audit/rule-recomputed-expectation,
testing/audit/rule-mock-only-oracle. Exempt a deliberate case with `cant-fail-ok: <reason>`
in the test. Scan root: $CANT_FAIL_SCAN_ROOT, else the cwd's git toplevel, else
$CLAUDE_PROJECT_DIR; unresolvable refuses rather than guessing.
EOF
}

mode="report"
strict=0
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    --check) mode="check" ;;
    --findings) mode="findings" ;;
    --count) mode="count" ;;
    --strict) strict=1 ;;
    *)
      printf 'ERROR: unknown argument %s\n' "$arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_PROG="$SCRIPT_DIR/cant-fail-scan.awk"
if [[ ! -r "$AWK_PROG" ]]; then
  printf 'ERROR: rule engine not found: %s\n' "$AWK_PROG" >&2
  exit 2
fi

ROOT_SOURCE=""
if [[ -n "${CANT_FAIL_SCAN_ROOT:-}" ]]; then
  ROOT="$CANT_FAIL_SCAN_ROOT"
  ROOT_SOURCE="\$CANT_FAIL_SCAN_ROOT"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  ROOT_SOURCE="git toplevel"
  if [[ -z "$ROOT" ]]; then
    ROOT="${CLAUDE_PROJECT_DIR:-}"
    ROOT_SOURCE="\$CLAUDE_PROJECT_DIR"
  fi
fi
if [[ -z "$ROOT" ]]; then
  cat >&2 <<'EOF'
ERROR: no scan root resolved — refusing to scan.

Tried, in order: $CANT_FAIL_SCAN_ROOT, the current directory's git toplevel,
then $CLAUDE_PROJECT_DIR. None resolved, and there is deliberately no fallback
to the current directory: outside a repository that is usually the user
profile, and a scan of the wrong tree that reports "no findings" is
indistinguishable from a clean bill.

Fix by running from inside the repository to scan, or set $CANT_FAIL_SCAN_ROOT
to the directory to scan explicitly (a supported operator lever; point it at a
subdirectory to narrow the scan).
EOF
  exit 2
fi
if [[ ! -d "$ROOT" ]]; then
  printf 'ERROR: scan root does not exist or is not a directory: %s\n' "$ROOT" >&2
  exit 2
fi

WALK_ERR="$(mktemp)"
trap 'rm -f "$WALK_ERR"' EXIT

# Location values are REPO-relative, not scan-root-relative: the fix action
# fences each remediation to Location, so a subdirectory scan root must not
# shorten the path. git's own prefix avoids any path-format reconciliation
# (drive-letter vs POSIX) a toplevel string comparison would need. Outside a
# repository the prefix is empty and Location degrades to root-relative.
REPO_PREFIX="$(git -C "$ROOT" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"

# --- Walk ---------------------------------------------------------------------
# Pruned: VCS/dependency/build trees, memory tiers, and evals/fixtures corpora
# (a detector's fixture corpus is deliberately defective test code; scanning it
# reports planted defects as the consumer's own).
collect_files() {
  find "$ROOT" \
    \( -name .git -o -name node_modules -o -name vendor -o -name dist \
    -o -name build -o -name out -o -name obj -o -name bin -o -name target \
    -o -name .work -o -name __pycache__ -o -name .venv -o -name venv \
    -o \( -name fixtures -path '*/evals/fixtures' \) \) -prune \
    -o -type f \( "$@" \) -print 2>>"$WALK_ERR" | sort
}

mapfile -t js_files < <(collect_files \
  -name '*.test.js' -o -name '*.test.jsx' -o -name '*.test.ts' -o -name '*.test.tsx' \
  -o -name '*.test.mjs' -o -name '*.test.cjs' -o -name '*.spec.js' -o -name '*.spec.jsx' \
  -o -name '*.spec.ts' -o -name '*.spec.tsx' -o -name '*.spec.mjs' -o -name '*.spec.cjs')
mapfile -t py_files < <(collect_files -name 'test_*.py' -o -name '*_test.py')
mapfile -t cs_files < <(collect_files -name '*Test.cs' -o -name '*Tests.cs')

# --- Denominator --------------------------------------------------------------
enum_js="${#js_files[@]}"
enum_py="${#py_files[@]}"
enum_cs="${#cs_files[@]}"
examined=0
unreadable=0
blocks=0
exempted=0

# Findings: parallel arrays, file order.
f_rule=()
f_loc=()
f_detail=()
n_cf1=0
n_cf2=0
n_cf3=0
x_cf1=0
x_cf2=0
x_cf3=0

scan_one() {
  # scan_one <lang> <file>
  local lang="$1" file="$2" rel kind slug line detail
  rel="$REPO_PREFIX${file#"$ROOT"/}"
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    unreadable=$((unreadable + 1))
    printf 'unreadable: %s\n' "$rel" >>"$WALK_ERR"
    return 0
  fi
  examined=$((examined + 1))
  while IFS=$'\t' read -r kind slug line detail; do
    case "$kind" in
      B) blocks=$((blocks + slug)) ;;
      F)
        f_rule+=("$slug")
        f_loc+=("$rel:$line")
        f_detail+=("$detail")
        case "$slug" in
          zero-assertion) n_cf1=$((n_cf1 + 1)) ;;
          recomputed-expectation) n_cf2=$((n_cf2 + 1)) ;;
          mock-only-oracle) n_cf3=$((n_cf3 + 1)) ;;
          *) printf 'engine drift: unknown finding rule %s\n' "$slug" >>"$WALK_ERR" ;;
        esac
        ;;
      X)
        exempted=$((exempted + 1))
        case "$slug" in
          zero-assertion) x_cf1=$((x_cf1 + 1)) ;;
          recomputed-expectation) x_cf2=$((x_cf2 + 1)) ;;
          mock-only-oracle) x_cf3=$((x_cf3 + 1)) ;;
          *) printf 'engine drift: unknown exempt rule %s\n' "$slug" >>"$WALK_ERR" ;;
        esac
        ;;
      E) printf 'engine: %s %s\n' "${slug:-}" "${line:-}" >>"$WALK_ERR" ;;
      *) printf 'engine drift: unrecognized record kind %s\n' "$kind" >>"$WALK_ERR" ;;
    esac
  done < <(awk -v LANG_ID="$lang" -f "$AWK_PROG" "$file" 2>>"$WALK_ERR")
}

for f in ${js_files[@]+"${js_files[@]}"}; do scan_one js "$f"; done
for f in ${py_files[@]+"${py_files[@]}"}; do scan_one py "$f"; done
for f in ${cs_files[@]+"${cs_files[@]}"}; do scan_one cs "$f"; done

total=$((n_cf1 + n_cf2 + n_cf3))
gating=$((n_cf1 + n_cf2))
[[ "$strict" -eq 1 ]] && gating=$((gating + n_cf3))
walk_errors="$(awk 'NF { n++ } END { print n + 0 }' "$WALK_ERR" 2>/dev/null)"
[[ -n "$walk_errors" ]] || walk_errors=0
enumerated=$((enum_js + enum_py + enum_cs))
fired_blocks=$((n_cf1 + n_cf3 + x_cf1 + x_cf3))
declined_cf1=$((blocks - n_cf1 - x_cf1))
declined_cf3=$((blocks - n_cf3 - x_cf3))

rule_id() {
  printf 'testing/audit/rule-%s' "$1"
}

threshold_of() {
  case "$1" in
    zero-assertion) printf 'threshold: 0 assertion tokens' ;;
    recomputed-expectation) printf 'threshold: >=1 self-identical equality assertion' ;;
    mock-only-oracle) printf 'threshold: 100%% of assertions are mock-interaction' ;;
    *) printf 'threshold: unknown rule' ;;
  esac
}

action_of() {
  # Repair, not pruning — every Action proposes an assertion, never a deletion.
  case "$1" in
    zero-assertion)
      printf 'Repair, not pruning: add an assertion on the observable behavior this test exercises; today it passes vacuously and its coverage claim is false.'
      ;;
    recomputed-expectation)
      printf 'State the expected value independently (a literal or precomputed constant) instead of recomputing it with the same expression, so the assertion can discriminate.'
      ;;
    mock-only-oracle)
      printf "Review whether the mock-interaction contract is the intended oracle; if not, assert on a real collaborator's output or state. A deliberate interaction-style test records that with a cant-fail-ok: annotation."
      ;;
    *) printf 'unknown rule — report this as a detector defect' ;;
  esac
}

confidence_of() {
  # zero-assertion / recomputed-expectation: the fired condition IS the defect —
  # confidence-of-realness is high. mock-only-oracle: the pattern is certain but
  # its defect-hood is not (interaction-style tests are legitimate), so the
  # field is omitted per the contract's high-or-omitted rule — never 'low'.
  case "$1" in
    zero-assertion | recomputed-expectation) printf 'high' ;;
    mock-only-oracle) printf '' ;;
    *) printf '' ;;
  esac
}

surfaces_line() {
  printf 'Ran: [testing:audit — %d test file(s) examined (js/ts %d, python %d, csharp %d), %d test block(s) parsed; findings: testing/audit/rule-zero-assertion %d, testing/audit/rule-recomputed-expectation %d, testing/audit/rule-mock-only-oracle %d; declined (examined, rule did not fire): rule-zero-assertion %d, rule-mock-only-oracle %d, rule-recomputed-expectation not tallied (line-scoped rule; v1 does not count candidate assertions); exempted via cant-fail-ok: %d]. Returned no result: [%s].\n' \
    "$examined" "$enum_js" "$enum_py" "$enum_cs" "$blocks" \
    "$n_cf1" "$n_cf2" "$n_cf3" "$declined_cf1" "$declined_cf3" "$exempted" \
    "$( if [[ "$unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then
      printf '%d unreadable test file(s), %d walk/read error line(s)' "$unreadable" "$walk_errors"
    else
      printf 'none — every discovered test file was examined'
    fi )"
}

coverage_block() {
  printf '\nScan coverage (the denominator — what this run actually read):\n'
  printf '  root: %s (resolved from %s)\n' "$ROOT" "$ROOT_SOURCE"
  printf '  test files: %d examined of %d enumerated (js/ts %d, python %d, csharp %d); %d unreadable\n' \
    "$examined" "$enumerated" "$enum_js" "$enum_py" "$enum_cs" "$unreadable"
  printf '  test blocks parsed: %d; blocks that fired a block rule: %d; exempted findings (cant-fail-ok): %d\n' \
    "$blocks" "$fired_blocks" "$exempted"
  printf '  walk/read/engine error lines: %d\n' "$walk_errors"
  printf '  never in scope here: skipped/ignored tests, bash *.test.sh (owned by the discriminating-skip gate), test files of other ecosystems, evals/fixtures corpora, and pruned dependency/build/memory dirs\n'
  if [[ "$examined" -eq 0 ]]; then
    printf '  NOTE: 0 test files examined — this run has no denominator. It is a scan of nothing, not a clean bill.\n'
  fi
}

esc_cell() {
  # detector-findings cell-escaping rule: literal | becomes \| ; the engine
  # already flattened tabs/newlines out of details.
  local s="$1"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

yaml_scalar() {
  # Quote a frontmatter value only when the plain form would misparse. git
  # accepts branch names starting with a YAML indicator ("@foo", "!foo",
  # "#foo"); emitted bare, "#foo" reads as a comment and the rest as
  # indicators, so the value the consumer compares is not the branch name.
  # The consumer (review/fanout fix-pass-mode.md "Step 1") admits a findings
  # file only on an EXACT branch match, so a misparse silently drops every
  # finding for that branch — the hidden-findings shape reached through the
  # frontmatter rather than through the scan.
  #
  # Conditional, not unconditional: an ordinary name stays a byte-identical
  # plain scalar, so the wire format for the common path does not move.
  # Predicate deliberately IDENTICAL to the two sibling awk producers
  # (claude-config/audit-instructions/scripts/emit-findings.sh and
  # ai-slop/audit/scripts/emit-findings.sh) — three producers answering one
  # frontmatter contract must agree, or a consumer sees three shapes. The
  # indicator set below is the same 19 characters as their awk character
  # class, and the ": " / " #" / empty / trailing-blank tests mirror theirs.
  # Space and tab only in the trailing test (NOT [:space:]), matching awk's
  # /[ \t]$/.
  local s="$1" needs_quote=0
  case "${s:0:1}" in
    '-' | '?' | ':' | ',' | '[' | ']' | '{' | '}' | '#' | '&' | '*' | '!' | '|' | '>' | '%' | '@' | '`' | '"' | "'")
      needs_quote=1
      ;;
    *) ;;
  esac
  case "$s" in
    *': '* | *' #'*) needs_quote=1 ;;
    *) ;;
  esac
  if [[ -z "$s" || "$s" == *[$' \t'] ]]; then needs_quote=1; fi
  lc=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
    true | false | yes | no | on | off | null | '~') needs_quote=1 ;;
  esac
  if [[ "$s" =~ ^[+-]?[0-9]+$ || "$s" =~ ^0[xXoObB][0-9a-fA-F_]+$ ]]; then
    needs_quote=1
  fi
  if ((needs_quote)); then
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
  else
    printf '%s' "$s"
  fi
}

emit_findings_file() {
  local branch ts i rank conf
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null | tr -d '\r')"
  if [[ -z "$branch" ]]; then
    printf 'ERROR: --findings needs a checked-out branch at the scan root (the consumer matches files by exact branch): %s\n' "$ROOT" >&2
    exit 2
  fi
  if [[ "$examined" -eq 0 ]]; then
    printf 'ERROR: --findings refused — 0 test files were examined, so there is no coverage to persist and a findings file would assert a scan that never ran.\n' >&2
    exit 2
  fi
  if [[ "$blocks" -eq 0 && "$walk_errors" -gt 0 ]]; then
    # Dead-engine guard: files were enumerated but nothing parsed and errors
    # occurred. Emitting here would hand the consumer a conforming file that
    # asserts zero findings from a scan that read nothing — a caller that
    # redirects stdout and drops the exit code would persist that lie.
    printf 'ERROR: --findings refused — 0 test blocks were parsed and %d error line(s) occurred; the scan did not actually read its inputs.\n' "$walk_errors" >&2
    exit 2
  fi
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf -- '---\ntype: review-findings\ndate: %s\nbranch: %s\n---\n\n## Findings\n\n' "$ts" "$(yaml_scalar "$branch")"
  printf '| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |\n'
  printf '|------|------|------------|----------|------------|---------|--------|\n'
  rank=0
  for i in ${f_rule[@]+"${!f_rule[@]}"}; do
    rank=$((rank + 1))
    conf="$(confidence_of "${f_rule[$i]}")"
    printf '| %d | IMPORTANT | %s | %s | testing:audit | %s: %s (%s) | %s |\n' \
      "$rank" "$conf" "${f_loc[$i]}" \
      "$(rule_id "${f_rule[$i]}")" "$(esc_cell "${f_detail[$i]}")" "$(threshold_of "${f_rule[$i]}")" \
      "$(esc_cell "$(action_of "${f_rule[$i]}")")"
  done
  printf '\n## Surfaces\n\n'
  surfaces_line
}

print_findings_lines() {
  local i
  for i in ${f_rule[@]+"${!f_rule[@]}"}; do
    printf 'finding [%s] %s: %s (%s). Action: %s\n' \
      "$(rule_id "${f_rule[$i]}")" "${f_loc[$i]}" "${f_detail[$i]}" \
      "$(threshold_of "${f_rule[$i]}")" "$(action_of "${f_rule[$i]}")"
  done
}

case "$mode" in
  count)
    printf '%d\n' "$total"
    coverage_block >&2
    if [[ "$unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
    exit 0
    ;;
  findings)
    emit_findings_file
    coverage_block >&2
    if [[ "$unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
    exit 0
    ;;
  check)
    if [[ "$total" -gt 0 ]]; then
      print_findings_lines
      if [[ "$strict" -eq 0 && "$n_cf3" -gt 0 ]]; then
        printf 'note: %d mock-only-oracle finding(s) are advisory in --check (use --strict to gate them).\n' "$n_cf3"
      fi
    fi
    coverage_block
    if [[ "$gating" -gt 0 ]]; then
      printf '\nFAIL: %d gating finding(s).\n' "$gating"
      exit 1
    fi
    if [[ "$examined" -eq 0 ]]; then
      printf '\nFAIL (closed): 0 test files were examined — a scan of nothing is not a clean gate. A wrong or empty scan root and a healthy suite must not share an exit code; point the gate at a tree that contains test files.\n'
      exit 2
    fi
    if [[ "$unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then
      printf '\nFAIL (closed): 0 gating findings, but %d unreadable test file(s) and %d walk/read/engine error line(s) — an input the scan could not fully read is never a clean one.\n' \
        "$unreadable" "$walk_errors"
      exit 2
    fi
    printf '\nPASS: no gating findings; %d test file(s) fully read.\n' "$examined"
    exit 0
    ;;
  report)
    if [[ "$total" -eq 0 ]]; then
      if [[ "$examined" -eq 0 ]]; then
        echo "NOTHING TO AUDIT: 0 test files were examined under this root. That is a scan of nothing, not a clean bill — see the coverage block."
      else
        echo "No can't-fail tests found."
      fi
    else
      print_findings_lines
    fi
    coverage_block
    if [[ "$unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
    exit 0
    ;;
  *)
    printf 'ERROR: unhandled mode %s\n' "$mode" >&2
    exit 2
    ;;
esac
