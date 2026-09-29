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
# Seven report-only rules print and count, and never gate --check, --strict
# included:
#
#   testing/audit/rule-inert-assertion       an assertion statement that never
#                                            evaluates: an async matcher nothing
#                                            awaits, a Python tuple assert, a
#                                            bare .Should(), a bats run whose
#                                            result nothing checks (threshold:
#                                            >= 1 such statement). Can't fail.
#   testing/audit/rule-constant-restatement  a constant, or a local literal the
#                                            test never passes to code, compared
#                                            to a literal (threshold: >= 1).
#                                            A change detector: it can fail.
#   testing/audit/rule-source-text-read      a read of a tracked, non-test
#                                            source file by a static path
#                                            (threshold: >= 1). A change
#                                            detector: it can fail.
#   testing/audit/rule-conditional-assertion every assertion inside an if, a
#                                            catch or a loop over a result,
#                                            with no else and no length check
#                                            (threshold: 100%). Can't fail on
#                                            the path that skips them.
#   testing/audit/rule-recomputed-derived    an expected value built from the
#                                            arguments of the call under test
#                                            with an operator or an aggregate
#                                            (threshold: >= 1). Property-test
#                                            files and Playwright are exempt.
#   testing/audit/rule-snapshot-only         every assertion is a snapshot
#                                            call (threshold: 100%); never an
#                                            image comparison.
#   testing/audit/rule-weak-oracle           every assertion is a weak matcher
#                                            (toBeDefined, is not None,
#                                            Assert.NotNull) or an over-broad
#                                            exception check (threshold: 100%).
#
# Two runner-config rules find the same shape one level up, in the Playwright
# config rather than in a test body (engine: runner-config-scan.awk, one config
# per invocation, loaded beside the shared masker mask-js.awk):
#
#   testing/audit/rule-flaky-passes-suite    retries are configured and
#                                            failOnFlakyTests is absent or
#                                            literal false, so a test that fails
#                                            and passes on a retry leaves the run
#                                            green.
#   testing/audit/rule-only-not-forbidden    forbidOnly is absent or literal
#                                            false, so a committed test.only
#                                            shrinks the suite to one passing
#                                            test instead of failing the run.
#
# Both are advisory in --check unless --strict, which gates them together with
# mock-only-oracle; there is no finer switch. A config file is not a test file:
# config findings are reported wherever they are found, but the exit-2 rule for
# 0 examined TEST files is unchanged, and a config-only tree neither gates nor
# persists them.
#
# Ecosystems: whatever the adapters/*.yaml files claim by their files: globs
# (JS/TS, Python, C#, Bash, bats, Pester, Go). An adapter marked advisory
# (bash-harness) never gates --check without --strict. For bash *.test.sh this
# scan owns assertions only; scripts/check-discriminating-test-skips.sh keeps
# the skip-vacating shape.
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
#   --inventory <text>  (repeatable, needs --file) no rules: count test starts,
#                assertion tokens and skip markers per line of each <text>, and
#                list its equalities with a literal side, judged with the
#                adapter and config of the --file path; the test-weaken hook
#                compares the old and new side of an edit this way
#   --help
#
# Scan-root resolution: $CANT_FAIL_SCAN_ROOT (sanctioned operator lever, not a
# test-only seam), else the cwd's git toplevel, else $CLAUDE_PROJECT_DIR.
# Never $PWD: an unresolved root refuses (exit 2) rather than sweeping an
# unknown tree — a completed-looking scan of the wrong tree is
# indistinguishable from a clean bill.
#
# Config: .claude/testing.yaml, resolved against the root's git toplevel (else
# $CLAUDE_PROJECT_DIR) by ../../../scripts/resolve-config.sh, turns adapters
# off or on (a file whose adapter is off is not scanned, never handed to
# another), excludes or includes paths, extends adapter lists, loads consumer
# adapters and sets rule levels (off drops a finding, warn keeps it out of the
# gate, error gates it).
# With no layer file present the scan is exactly the shipped one.
#
# Every run reports a DENOMINATOR (coverage block): files enumerated and
# examined per ecosystem, test blocks parsed, exemptions, and what could not
# be read. "0 findings" over 0 examined files is a scan of nothing and is
# never reported as a clean bill.
set -uo pipefail

usage() {
  cat <<'EOF'
cant-fail-scan.sh — detect tests that cannot fail.

Usage: cant-fail-scan.sh [--file <path> [--lines <list>]] [--check [--strict] | --findings | --count | --help]
       cant-fail-scan.sh --file <path> --inventory <text> [--inventory <text>...]

  (no arg)    print one finding line per detection, then the coverage block; exit 0 (2 on scan gap)
  --check     exit 1 when a gating rule fired, 2 when the scan could not run, could not fully
              read its inputs, or examined 0 test files, 0 only for a fully read finding-free
              scan of at least one test file (fail closed)
  --strict    with --check: mock-only-oracle and the playwright config findings gate too
              (advisory otherwise; one switch for all three, no finer grain)
  --findings  emit a detector-findings-conforming findings file on stdout; coverage on stderr;
              refuses (exit 2) when no test file was examined or no branch is checked out
  --count     integer finding count on stdout, coverage block on stderr
  --file <p>  scan exactly one test file instead of the tree; same modes and exit codes
  --lines <l> with --file: report only findings whose test block overlaps these lines
              (a list like 12,20-24), for an edit hook scoped to what the edit changed
  --inventory <text>
              with --file, repeatable: no rules; for the n-th <text>, one record per line
              `n<TAB>test|assertion|skip<TAB><count><TAB><line>`, one per equality with a
              literal side `n<TAB>expect<TAB><actual><TAB><literal>`, and `n<TAB>unjudged`
              when the text ends inside a string or comment, judged with the adapter and
              config of the --file path. `rule<TAB><slug><TAB><level>` comes first per
              configured rule level; an excluded or unclaimed path prints nothing else

Rules v1: testing/audit/rule-zero-assertion, testing/audit/rule-recomputed-expectation,
testing/audit/rule-mock-only-oracle, and over each Playwright config found,
testing/audit/rule-flaky-passes-suite and testing/audit/rule-only-not-forbidden.
Report-only, never gating: testing/audit/rule-inert-assertion,
testing/audit/rule-constant-restatement, testing/audit/rule-source-text-read,
testing/audit/rule-conditional-assertion, testing/audit/rule-recomputed-derived,
testing/audit/rule-snapshot-only, testing/audit/rule-weak-oracle.
Exempt a deliberate case with `cant-fail-ok: <reason>` in the test, or anywhere in the
config. Scan root: $CANT_FAIL_SCAN_ROOT, else the cwd's git toplevel, else
$CLAUDE_PROJECT_DIR; unresolvable refuses rather than guessing.
EOF
}

mode="report"
strict=0
FILE=""
LINES=""
INV_TEXTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --check) mode="check" ;;
  --findings) mode="findings" ;;
  --count) mode="count" ;;
  --strict) strict=1 ;;
  --file)
    if [[ $# -lt 2 || -z "$2" ]]; then
      printf 'ERROR: --file needs a path\n' >&2
      usage >&2
      exit 2
    fi
    FILE="$2"
    shift
    ;;
  --lines)
    if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
      printf 'ERROR: --lines needs a list like 12,20-24\n' >&2
      exit 2
    fi
    LINES="$2"
    shift
    ;;
  --inventory)
    if [[ $# -lt 2 || ! -r "$2" ]]; then
      printf 'ERROR: --inventory needs a readable file\n' >&2
      exit 2
    fi
    mode="inventory"
    INV_TEXTS+=("$2")
    shift
    ;;
  *)
    printf 'ERROR: unknown argument %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK_PROG="$SCRIPT_DIR/cant-fail-scan.awk"
# The JavaScript masker is shared by both engines and lives in mask-js.awk; awk
# loads it as the first of two -f programs, so it is as load-bearing as the
# engine itself and refuses the same way when missing.
MASK_AWK="$SCRIPT_DIR/mask-js.awk"
CONFIG_AWK="$SCRIPT_DIR/runner-config-scan.awk"
require_readable() {
  # require_readable <path> <what it is>
  [[ -r "$1" ]] && return 0
  printf 'ERROR: %s not found: %s\n' "$2" "$1" >&2
  exit 2
}
require_readable "$AWK_PROG" 'rule engine'
require_readable "$MASK_AWK" 'shared JavaScript masker'
require_readable "$CONFIG_AWK" 'runner-config rule engine'
LOADER="$SCRIPT_DIR/adapter-load.awk"
require_readable "$LOADER" 'adapter loader'
ADAPTER_DIR="$SCRIPT_DIR/../adapters"

if [[ (-n "$LINES" || "$mode" == inventory) && -z "$FILE" ]]; then
  printf 'ERROR: --lines and --inventory need --file\n' >&2
  exit 2
fi
ROOT_SOURCE=""
if [[ -n "$FILE" ]]; then
  if [[ ! -f "$FILE" ]]; then
    printf 'ERROR: --file is not a file: %s\n' "$FILE" >&2
    exit 2
  fi
  ROOT="$(cd "$(dirname "$FILE")" && pwd)"
  FILE="$ROOT/$(basename "$FILE")"
  ROOT_SOURCE="--file"
elif [[ -n "${CANT_FAIL_SCAN_ROOT:-}" ]]; then
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
ADAPTER_TABLE="$(mktemp)"
EXTEND_FILE=""
trap 'rm -f "$WALK_ERR" "$ADAPTER_TABLE" "$EXTEND_FILE"' EXIT

# Location values are REPO-relative, not scan-root-relative: the fix action
# fences each remediation to Location, so a subdirectory scan root must not
# shorten the path. git's own prefix avoids any path-format reconciliation
# (drive-letter vs POSIX) a toplevel string comparison would need. Outside a
# repository the prefix is empty and Location degrades to root-relative.
# The same call yields the toplevel the config layers resolve against.
TOP=""
REPO_PREFIX=""
{
  IFS= read -r TOP
  IFS= read -r REPO_PREFIX
} < <(git -C "$ROOT" rev-parse --show-toplevel --show-prefix 2>/dev/null | tr -d '\r')

# --- Config -------------------------------------------------------------------
# .claude/testing.yaml, resolved by scripts/resolve-config.sh. With no layer
# file present nothing below runs, so a repository without one pays three file
# tests. Removals (adapters.disable, paths.exclude, rules off) apply here, so
# the test-scan hook, which runs this script, goes silent with no plugin change.
# The team and local layers are the scanned repository's own, so a file in a
# sibling worktree gets that worktree's config.
CFG_ROOT="${TOP:-${CLAUDE_PROJECT_DIR:-$ROOT}}"
tc_layers=0
for f in ${HOME:+"$HOME/.claude/testing.yaml"} "$CFG_ROOT/.claude/testing.yaml" \
  "$CFG_ROOT/.claude/testing.local.yaml"; do
  [[ -f "$f" ]] && tc_layers=$((tc_layers + 1))
done
tc_extra=()
tc_enable=()
tc_exclude_re=()
tc_include_re=()
tc_uncovered=()
declare -A tc_on=() tc_off=() rule_level=()
if ((tc_layers)); then
  RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
  require_readable "$RESOLVER" 'config resolver'
  # shellcheck source=../../../scripts/resolve-config.sh
  source "$RESOLVER"
  tc_out="$(bash "$RESOLVER" --root "$CFG_ROOT" ${FILE:+--quick})" || {
    printf 'ERROR: .claude/testing.yaml did not resolve (see above); refusing to scan.\n' >&2
    exit 2
  }
  while IFS=$'\t' read -r key val; do
    case "$key" in
    adapters.enable)
      tc_enable+=("$val")
      tc_on[$val]=1
      ;;
    adapters.disable) tc_off[$val]=1 ;;
    paths.exclude)
      tcfg_glob_re "$val"
      tc_exclude_re+=("$TCFG_RE")
      ;;
    paths.include)
      tcfg_glob_re "$val"
      tc_include_re+=("$TCFG_RE")
      ;;
    adapter_dirs) for f in "$val"/*.yaml; do [[ -f "$f" ]] && tc_extra+=("$f"); done ;;
    extend.*)
      val="${key#extend.}"$'\t'"$val"
      [[ -n "$EXTEND_FILE" ]] || EXTEND_FILE="$(mktemp)"
      printf '%s\t%s\n' "${val%%.*}" "${val#*.}" >>"$EXTEND_FILE"
      ;;
    rules.*) rule_level[${key#rules.}]="$val" ;;
    hook.uncovered) tc_uncovered+=("$val") ;;
    *) ;;
    esac
  done <<<"$tc_out"
fi
# adapter_on <id>: disable wins; a non-empty enable list is an allowlist.
adapter_on() {
  [[ -z "${tc_off[$1]:-}" ]] && [[ ${#tc_enable[@]} -eq 0 || -n "${tc_on[$1]:-}" ]]
}

# --- Adapters -----------------------------------------------------------------
# Every adapter is validated up front: a malformed one refuses the whole run
# (exit 2), never a per-file engine error the aggregate could absorb.
if ! awk -v EXTEND="$EXTEND_FILE" -f "$LOADER" "$ADAPTER_DIR"/*.yaml ${tc_extra[@]+"${tc_extra[@]}"} >"$ADAPTER_TABLE"; then
  printf 'ERROR: adapter load failed (see above); refusing to scan.\n' >&2
  exit 2
fi
# A disabled adapter still loads and still claims files: pick_adapter runs over
# every adapter, and a file whose winner is off is not scanned, rather than
# handed to a sibling that also matches its name (js-jest for a Vitest file).
adapter_ids=()
declare -A a_lang=() a_globs=() a_detect=() a_advisory=()
all_globs=()
while IFS=$'\t' read -r id key val; do
  [[ -n "${a_lang[$id]+x}" ]] || {
    adapter_ids+=("$id")
    a_lang[$id]=""
  }
  case "$key" in
  language) a_lang[$id]="$val" ;;
  files)
    a_globs[$id]+="$val"$'\n'
    all_globs+=("$val")
    ;;
  detect.any_regex) a_detect[$id]+="$val"$'\n' ;;
  advisory) [[ "$val" == true ]] && adapter_on "$id" && a_advisory[$id]=1 ;;
  *) ;;
  esac
done <"$ADAPTER_TABLE"

# pick_adapter <file>: the adapter claiming <file> by its files: globs; among
# several, the first in load order whose detect.any_regex matches the content,
# else the first in load order with no detect list, else the first in load
# order. Prints nothing when none claims the file.
pick_adapter() {
  local base="${1##*/}" id glob re first="" first_detects="" pats
  for id in ${adapter_ids[@]+"${adapter_ids[@]}"}; do
    while IFS= read -r glob; do
      # shellcheck disable=SC2053 # the glob is a pattern on purpose
      if [[ -n "$glob" && "$base" == $glob ]]; then
        # The fallback is the first claimant with no detect list (the default
        # for its language, as cs-xunit is), else the first claimant.
        if [[ -z "$first" || (-n "$first_detects" && -z "${a_detect[$id]:-}") ]]; then
          first="$id"
          first_detects="${a_detect[$id]:-}"
        fi
        pats=()
        while IFS= read -r re; do [[ -n "$re" ]] && pats+=(-e "$re"); done <<<"${a_detect[$id]:-}"
        if [[ ${#pats[@]} -gt 0 ]] && LC_ALL=C grep -qE "${pats[@]}" -- "$1" 2>/dev/null; then
          printf '%s' "$id"
          return
        fi
        break
      fi
    done <<<"${a_globs[$id]:-}"
  done
  printf '%s' "$first"
}

# --- Walk ---------------------------------------------------------------------
# Pruned: VCS/dependency/build trees, memory tiers, and evals/fixtures corpora
# (a detector's fixture corpus is deliberately defective test code; scanning it
# reports planted defects as the consumer's own). With --file the walk starts
# at that one file, so the prune never applies and only its name is tested.
collect_files() {
  find "${FILE:-$ROOT}" \
    \( -name .git -o -name node_modules -o -name vendor -o -name dist \
    -o -name build -o -name out -o -name obj -o -name bin -o -name target \
    -o -name .work -o -name __pycache__ -o -name .venv -o -name venv \
    -o \( -name fixtures -path '*/evals/fixtures' \) \) -prune \
    -o -type f \( "$@" \) -print 2>>"$WALK_ERR" | sort
}

# The walk takes the union of every adapter's files: globs. Each file is then
# bucketed by its adapter's language, and the buckets scan in the fixed order
# js, python, cs, bash, pwsh, go, so finding order does not depend on adapter
# file names.
name_args=()
declare -A glob_seen=()
for id in ${adapter_ids[@]+"${adapter_ids[@]}"}; do
  while IFS= read -r glob; do
    [[ -z "$glob" || -n "${glob_seen[$glob]:-}" ]] && continue
    glob_seen[$glob]=1
    [[ ${#name_args[@]} -gt 0 ]] && name_args+=(-o)
    name_args+=(-name "$glob")
  done <<<"${a_globs[$id]:-}"
done
[[ ${#name_args[@]} -gt 0 ]] || name_args=(-name '')

# include_files: files under the root that a paths.include glob names, walked
# past the prunes above (only .git and node_modules stay pruned); each still
# needs an adapter to claim it.
# ponytail: walks the whole root per run when include is set; walk each glob's
# literal leading directory instead if that shows up in a large tree.
include_files() {
  [[ ${#tc_include_re[@]} -gt 0 && -z "$FILE" ]] || return 0
  local f rel re
  while IFS= read -r f; do
    rel="$REPO_PREFIX${f#"$ROOT"/}"
    for re in "${tc_include_re[@]}"; do
      if [[ "$rel" =~ $re ]]; then
        printf '%s\n' "$f"
        break
      fi
    done
  done < <(find "$ROOT" \( -name .git -o -name node_modules \) -prune -o -type f -print 2>>"$WALK_ERR")
}

# excluded <file>: a paths.exclude glob names its repo-relative path.
excluded() {
  local rel="$REPO_PREFIX${1#"$ROOT"/}" re
  for re in ${tc_exclude_re[@]+"${tc_exclude_re[@]}"}; do
    [[ "$rel" =~ $re ]] && return 0
  done
  return 1
}

js_files=()
py_files=()
cs_files=()
sh_files=()
ps_files=()
go_files=()
tc_excluded=0
tc_unclaimed=0
tc_disabled=0
tc_off_winner=""
declare -A file_adapter=()
while IFS= read -r f; do
  [[ -n "$f" && -z "${file_adapter[$f]+x}" ]] || continue
  if [[ ${#tc_exclude_re[@]} -gt 0 ]] && excluded "$f"; then
    tc_excluded=$((tc_excluded + 1))
    file_adapter[$f]=""
    continue
  fi
  id="$(pick_adapter "$f")"
  if [[ -z "$id" ]]; then
    tc_unclaimed=$((tc_unclaimed + 1))
    file_adapter[$f]=""
    continue
  fi
  if ! adapter_on "$id"; then
    tc_disabled=$((tc_disabled + 1))
    tc_off_winner="$id"
    file_adapter[$f]=""
    continue
  fi
  file_adapter[$f]="$id"
  case "${a_lang[$id]}" in
  js) js_files+=("$f") ;;
  python) py_files+=("$f") ;;
  cs) cs_files+=("$f") ;;
  bash) sh_files+=("$f") ;;
  pwsh) ps_files+=("$f") ;;
  go) go_files+=("$f") ;;
  *) ;;
  esac
done < <(
  collect_files "${name_args[@]}"
  include_files
)

# --- Inventory ----------------------------------------------------------------
# The texts are judged with the --file path's adapter; the path itself decided
# exclusion and adapter choice above, so a fragment needs no git root or import.
if [[ "$mode" == inventory ]]; then
  for key in "${!rule_level[@]}"; do printf 'rule\t%s\t%s\n' "$key" "${rule_level[$key]}"; done
  id="${file_adapter[$FILE]:-}"
  [[ -n "$id" ]] || exit 0
  n=0
  for t in "${INV_TEXTS[@]}"; do
    n=$((n + 1))
    awk -v ADAPTER="$id" -v ADAPTER_TABLE="$ADAPTER_TABLE" -v INVENTORY="$n" \
      -f "$MASK_AWK" -f "$AWK_PROG" "$t" || exit 2
  done
  exit 0
fi

# Playwright runner configs: the same pruned walk, for the six filenames the
# runner probes. Playwright never walks upward, so every directory holding any
# of the six is its own Playwright root; within one directory only the first in
# probe order is loaded, and the rest are counted as shadowed without being read.
mapfile -t cfg_files < <(collect_files \
  -name 'playwright.config.ts' -o -name 'playwright.config.js' \
  -o -name 'playwright.config.mts' -o -name 'playwright.config.mjs' \
  -o -name 'playwright.config.cts' -o -name 'playwright.config.cjs')

# --- Denominator --------------------------------------------------------------
enum_js="${#js_files[@]}"
enum_py="${#py_files[@]}"
enum_cs="${#cs_files[@]}"
enum_sh="${#sh_files[@]}"
enum_ps="${#ps_files[@]}"
enum_go="${#go_files[@]}"
examined=0
unreadable=0
lost=0
blocks=0
exempted=0
cfg_enum="${#cfg_files[@]}"
cfg_examined=0
cfg_shadowed=0
cfg_unparsed=0
cfg_unreadable=0

# Findings: parallel arrays, file order.
f_rule=()
f_loc=()
f_detail=()
f_lang=()
n_cf1=0
n_adv=0
n_cf2=0
n_cf3=0
x_cf1=0
x_cf3=0
n_cfg1=0
n_cfg2=0
x_cfg1=0
x_cfg2=0
d_cfg1=0
d_cfg2=0
# Report-only rules: counted, printed, never in gating, advisory or n_adv.
n_ia=0
n_cr=0
n_st=0
n_ca=0
n_rd=0
n_so=0
n_wo=0

# source_target <test file> <path>: the repo-relative path <path> names when
# resolved against the test file's directory, then the repository root, and
# only when it is a git-tracked file with a source extension that no adapter
# claims as a test file. Prints nothing otherwise: the engine cannot see git,
# so this is where a candidate read becomes a finding or is dropped.
SOURCE_EXT_RE='\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|py|cs|razor|go|sh|bash|ps1|psm1|vue|svelte)$'
source_target() {
  local file="$1" path="$2" cand dir rel glob
  [[ "$path" =~ $SOURCE_EXT_RE && "$path" != /* ]] || return 0
  [[ -n "$TOP" ]] || TOP="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$TOP" ]] || return 0
  for cand in "${file%/*}/$path" "$TOP/$path"; do
    [[ -f "$cand" ]] || continue
    dir="$(cd "${cand%/*}" 2>/dev/null && pwd -P)" || continue
    rel="$dir/${cand##*/}"
    [[ "$rel" == "$TOP"/* ]] || continue
    rel="${rel#"$TOP"/}"
    for glob in "${all_globs[@]}"; do
      # shellcheck disable=SC2053 # the glob is a pattern on purpose
      [[ "${rel##*/}" == $glob ]] && return 0
    done
    git -C "$TOP" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || continue
    printf '%s' "$rel"
    return 0
  done
}

# rule_override <slug> <1 when the finding gates --check by default>: apply
# its rules.<slug> level from .claude/testing.yaml. off drops the finding
# (return 1), warn keeps it out of the gate, error puts it in.
tc_dropped=0
tc_gate=0
tc_ungate=0
rule_override() {
  case "${rule_level[$1]:-}" in
  off)
    tc_dropped=$((tc_dropped + 1))
    return 1
    ;;
  warn) [[ "$2" -eq 1 ]] && tc_ungate=$((tc_ungate + 1)) ;;
  error) [[ "$2" -eq 0 ]] && tc_gate=$((tc_gate + 1)) ;;
  *) ;;
  esac
  return 0
}

scan_one() {
  # scan_one <file>
  local file="$1" rel kind slug line detail target gates
  rel="$REPO_PREFIX${file#"$ROOT"/}"
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    unreadable=$((unreadable + 1))
    printf 'unreadable: %s\n' "$rel" >>"$WALK_ERR"
    return 0
  fi
  examined=$((examined + 1))
  while IFS=$'\t' read -r kind slug line detail; do
    # A source-read candidate: slug carries F or X, detail the static path.
    if [[ "$kind" == S ]]; then
      target="$(source_target "$file" "$detail")"
      [[ -n "$target" ]] || continue
      kind="$slug" slug=source-text-read detail="reads tracked source file $target as text"
    fi
    case "$kind" in
    B) blocks=$((blocks + slug)) ;;
    L) lost=$((lost + 1)) ;;
    F)
      if [[ ${#rule_level[@]} -gt 0 ]]; then
        gates=0
        case "$slug" in
        zero-assertion | recomputed-expectation) [[ -z "${a_advisory[${file_adapter[$file]}]:-}" || "$strict" -eq 1 ]] && gates=1 ;;
        mock-only-oracle) [[ "$strict" -eq 1 ]] && gates=1 ;;
        *) ;;
        esac
        rule_override "$slug" "$gates" || continue
      fi
      f_rule+=("$slug")
      f_loc+=("$rel:$line")
      f_detail+=("$detail")
      f_lang+=("${a_lang[${file_adapter[$file]}]}")
      case "$slug" in
      zero-assertion) n_cf1=$((n_cf1 + 1)) ;;
      recomputed-expectation) n_cf2=$((n_cf2 + 1)) ;;
      mock-only-oracle) n_cf3=$((n_cf3 + 1)) ;;
      inert-assertion) n_ia=$((n_ia + 1)) ;;
      constant-restatement) n_cr=$((n_cr + 1)) ;;
      source-text-read) n_st=$((n_st + 1)) ;;
      conditional-assertion) n_ca=$((n_ca + 1)) ;;
      recomputed-derived) n_rd=$((n_rd + 1)) ;;
      snapshot-only) n_so=$((n_so + 1)) ;;
      weak-oracle) n_wo=$((n_wo + 1)) ;;
      *) printf 'engine drift: unknown finding rule %s\n' "$slug" >>"$WALK_ERR" ;;
      esac
      # An advisory adapter's findings of the two gating rules stay out of the gate.
      case "$slug" in
      zero-assertion | recomputed-expectation) [[ -n "${a_advisory[${file_adapter[$file]}]:-}" ]] && n_adv=$((n_adv + 1)) ;;
      *) ;;
      esac
      ;;
    X)
      exempted=$((exempted + 1))
      case "$slug" in
      zero-assertion) x_cf1=$((x_cf1 + 1)) ;;
      # Recognized, no per-rule tally: nothing consumes an exempt count for the
      # line-scoped rules — x_cf1/x_cf3 feed the block-rule fired/declined math
      # below, and the aggregate `exempted` above already counted this record.
      recomputed-expectation | inert-assertion | constant-restatement | source-text-read | conditional-assertion | recomputed-derived | snapshot-only | weak-oracle) ;;
      mock-only-oracle) x_cf3=$((x_cf3 + 1)) ;;
      *) printf 'engine drift: unknown exempt rule %s\n' "$slug" >>"$WALK_ERR" ;;
      esac
      ;;
    E) printf 'engine: %s %s\n' "${slug:-}" "${line:-}" >>"$WALK_ERR" ;;
    *) printf 'engine drift: unrecognized record kind %s\n' "$kind" >>"$WALK_ERR" ;;
    esac
  done < <(awk -v ADAPTER="${file_adapter[$file]}" -v ADAPTER_TABLE="$ADAPTER_TABLE" -v SCOPE="$LINES" \
    -f "$MASK_AWK" -f "$AWK_PROG" "$file" 2>>"$WALK_ERR")
}

scan_config() {
  # scan_config <playwright config file>
  local file="$1" rel kind slug line detail
  rel="$REPO_PREFIX${file#"$ROOT"/}"
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    # Counted against the CONFIG denominator, never the test-file one: the
    # test-file counters and their messages speak only about test files. The
    # logged line keeps the run fail-closed through walk_errors, because an
    # enumerated input the scan could not read is never a clean one.
    cfg_unreadable=$((cfg_unreadable + 1))
    printf 'unreadable playwright config: %s\n' "$rel" >>"$WALK_ERR"
    return 0
  fi
  while IFS=$'\t' read -r kind slug line detail; do
    case "$kind" in
    C)
      # An unanchorable config is a coverage boundary, not a rule decline: it is
      # counted as enumerated and not examined, the same statement the test-file
      # denominator makes about a file of another ecosystem.
      if [[ "$slug" == "1" ]]; then
        cfg_examined=$((cfg_examined + 1))
      else
        cfg_unparsed=$((cfg_unparsed + 1))
      fi
      ;;
    F)
      if [[ ${#rule_level[@]} -gt 0 ]]; then
        rule_override "$slug" "$strict" || continue
      fi
      f_rule+=("$slug")
      f_loc+=("$rel:$line")
      f_detail+=("$detail")
      f_lang+=(config)
      case "$slug" in
      flaky-passes-suite) n_cfg1=$((n_cfg1 + 1)) ;;
      only-not-forbidden) n_cfg2=$((n_cfg2 + 1)) ;;
      *) printf 'engine drift: unknown config finding rule %s\n' "$slug" >>"$WALK_ERR" ;;
      esac
      ;;
    X)
      exempted=$((exempted + 1))
      case "$slug" in
      flaky-passes-suite) x_cfg1=$((x_cfg1 + 1)) ;;
      only-not-forbidden) x_cfg2=$((x_cfg2 + 1)) ;;
      *) printf 'engine drift: unknown config exempt rule %s\n' "$slug" >>"$WALK_ERR" ;;
      esac
      ;;
    D)
      case "$slug" in
      flaky-passes-suite) d_cfg1=$((d_cfg1 + 1)) ;;
      only-not-forbidden) d_cfg2=$((d_cfg2 + 1)) ;;
      *) printf 'engine drift: unknown config decline rule %s\n' "$slug" >>"$WALK_ERR" ;;
      esac
      ;;
    E) printf 'config engine: %s %s\n' "${slug:-}" "${line:-}" >>"$WALK_ERR" ;;
    *) printf 'engine drift: unrecognized config record kind %s\n' "$kind" >>"$WALK_ERR" ;;
    esac
  done < <(awk -f "$MASK_AWK" -f "$CONFIG_AWK" "$file" 2>>"$WALK_ERR")
}

for f in ${js_files[@]+"${js_files[@]}"} ${py_files[@]+"${py_files[@]}"} ${cs_files[@]+"${cs_files[@]}"} \
  ${sh_files[@]+"${sh_files[@]}"} ${ps_files[@]+"${ps_files[@]}"} ${go_files[@]+"${go_files[@]}"}; do
  scan_one "$f"
done

# One config per directory, in Playwright's probe order. Everything else the
# walk enumerated in that directory is shadowed: the runner would never load it,
# so judging it would report a file the suite does not run.
cfg_dirs=()
declare -A cfg_seen=()
for f in ${cfg_files[@]+"${cfg_files[@]}"}; do
  cfg_dir="$(dirname "$f")"
  if [[ -z "${cfg_seen[$cfg_dir]:-}" ]]; then
    cfg_seen["$cfg_dir"]=1
    cfg_dirs+=("$cfg_dir")
  fi
done
cfg_shadowed=$((cfg_enum - ${#cfg_dirs[@]}))
for d in ${cfg_dirs[@]+"${cfg_dirs[@]}"}; do
  for ext in ts js mts mjs cts cjs; do
    if [[ -f "$d/playwright.config.$ext" ]]; then
      scan_config "$d/playwright.config.$ext"
      break
    fi
  done
done

cfg_findings=$((n_cfg1 + n_cfg2))
advisory=$((n_cf3 + cfg_findings + n_adv))
report_only=$((n_ia + n_cr + n_st + n_ca + n_rd + n_so + n_wo))
total=$((n_cf1 + n_cf2 + n_cf3 + cfg_findings + report_only))
gating=$((n_cf1 + n_cf2 - n_adv))
[[ "$strict" -eq 1 ]] && gating=$((gating + n_cf3 + cfg_findings + n_adv))
gating=$((gating + tc_gate - tc_ungate))
walk_errors="$(awk 'NF { n++ } END { print n + 0 }' "$WALK_ERR" 2>/dev/null)"
[[ -n "$walk_errors" ]] || walk_errors=0
enumerated=$((enum_js + enum_py + enum_cs + enum_sh + enum_ps + enum_go))
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
  flaky-passes-suite) printf 'threshold: retries > 0 or an expression, failOnFlakyTests absent or literal false' ;;
  only-not-forbidden) printf 'threshold: forbidOnly absent or literal false' ;;
  inert-assertion) printf 'threshold: >=1 assertion statement that never evaluates' ;;
  constant-restatement) printf 'threshold: >=1 constant or local literal compared to a literal, with no call under test' ;;
  source-text-read) printf 'threshold: >=1 static-path read of a tracked non-test source file' ;;
  conditional-assertion) printf 'threshold: 100%% of assertions inside an if, a catch or a loop over a result, no else and no length check' ;;
  recomputed-derived) printf 'threshold: >=1 expected value built from the arguments of the call under test' ;;
  snapshot-only) printf 'threshold: 100%% of assertions are snapshot calls' ;;
  weak-oracle) printf 'threshold: 100%% of assertions are weak matchers or over-broad exception checks' ;;
  *) printf 'threshold: unknown rule' ;;
  esac
}

action_of() {
  # action_of <slug> <lexer language>. Repair, not pruning — every Action
  # proposes an assertion, never a deletion. The inert-assertion remedy is
  # scoped to the language it fires in: "await" means nothing to a Python
  # tuple, and "assert_*" nothing to a Playwright matcher.
  case "$1:${2:-}" in
  inert-assertion:js)
    printf 'Make the assertion evaluate: await (or return) the async matcher so it settles before the test ends, and call a matcher on every expect(...).'
    ;;
  inert-assertion:cs)
    printf 'Make the assertion evaluate: await the async assertion (await Assert.ThrowsAsync<...>(...)), chain a matcher after .Should() (.Should().Be(...)), and assert a condition the code computes rather than a literal true.'
    ;;
  inert-assertion:python)
    printf "Make the assertion evaluate: write assert cond, msg without the tuple's parentheses, and call the mock's assert_* method (m.assert_called_once_with(...)) instead of the plain attribute."
    ;;
  inert-assertion:bash)
    # shellcheck disable=SC2016  # literal remedy text names bats variables
    printf 'Make the assertion evaluate: check what run captured ($status, $output, or assert_success / assert_output), or use run -N / run ! cmd; a ! cmd fails the test only as its last line; in a harness end a [ ] test with || fail.'
    ;;
  inert-assertion:pwsh)
    # shellcheck disable=SC2016  # literal remedy text names a PowerShell variable
    printf 'Make the assertion evaluate: pipe the value to a Should assertion ($x | Should -Be 5); Pester discards the bool a bare comparison returns.'
    ;;
  inert-assertion:go)
    printf 'Make the assertion evaluate: report the mismatch with t.Errorf or t.Fatalf in the branch; an empty branch or t.Log never fails the test.'
    ;;
  constant-restatement:*)
    printf 'Assert the behavior that uses the constant (the input it accepts or rejects) instead of restating its value; a contract constant fixed by a spec records that with a cant-fail-ok: <why> annotation.'
    ;;
  source-text-read:*)
    printf 'Exercise the code (render it, call it, run it) instead of reading its source text; a policy test over many files reads them through a glob or a directory walk.'
    ;;
  conditional-assertion:*)
    printf 'Make every path assert: assert an expected error with the framework'"'"'s throws or rejects assertion instead of inside a catch, move the assertion out of the if, and assert the length of a result before looping over it, so an empty result fails.'
    ;;
  recomputed-derived:*)
    printf 'State the expected value independently (a literal worked out by hand or taken from the spec) instead of rebuilding it from the same inputs the way the code does; an invariant checked over generated inputs belongs in a property-based test.'
    ;;
  snapshot-only:*)
    printf 'Review the snapshot as code, and beside it assert the one value the test exists for with a literal, so an approved wrong snapshot still fails.'
    ;;
  weak-oracle:*)
    printf 'Assert the value the code should produce (an exact value, or the exact exception type and message) instead of only that a value exists or that something threw.'
    ;;
  *) ;;
  esac
  case "$1" in
  inert-assertion | constant-restatement | source-text-read | conditional-assertion | recomputed-derived | snapshot-only | weak-oracle) return 0 ;;
  zero-assertion)
    printf 'Repair, not pruning: add an assertion on the observable behavior this test exercises; today it passes vacuously and its coverage claim is false.'
    ;;
  recomputed-expectation)
    printf 'State the expected value independently (a literal or precomputed constant) instead of recomputing it with the same expression, so the assertion can discriminate.'
    ;;
  mock-only-oracle)
    printf "Review whether the mock-interaction contract is the intended oracle; if not, assert on a real collaborator's output or state. A deliberate interaction-style test records that with a cant-fail-ok: annotation."
    ;;
  # failOnFlakyTests as a config option shipped in Playwright 1.52, the
  # --fail-on-flaky-tests CLI flag it mirrors in 1.45 (VR-2, verified against
  # v1.63.0 as of 2026-09-11; recheck on a release note renaming or deprecating
  # the option). The detector does not read the installed version, so the Action
  # names the floor rather than assuming it.
  flaky-passes-suite)
    printf 'Set failOnFlakyTests: true in the Playwright config so a test that fails and passes on a retry fails the run (config option from Playwright 1.52; the --fail-on-flaky-tests CLI flag covers 1.45 and later), or set retries: 0 where the suite is meant to be deterministic. A deliberate flaky tolerance records that with a cant-fail-ok: annotation.'
    ;;
  only-not-forbidden)
    printf 'Set forbidOnly: !!process.env.CI in the Playwright config, the scaffold idiom, so a committed test.only fails CI instead of shrinking the suite to one passing test.'
    ;;
  *) printf 'unknown rule — report this as a detector defect' ;;
  esac
}

confidence_of() {
  # zero-assertion / recomputed-expectation / inert-assertion: the fired
  # condition IS the defect —
  # confidence-of-realness is high. mock-only-oracle: the pattern is certain but
  # its defect-hood is not (interaction-style tests are legitimate), so the
  # field is omitted per the contract's high-or-omitted rule — never 'low'.
  # The two config rules omit it for the same reason: the configuration state is
  # read exactly, but whether it is a defect is a team policy call (a team may
  # accept flaky tolerance, or trust review to catch a committed .only).
  # constant-restatement and source-text-read omit it too: a contract constant
  # or a codegen test is the known benign case. So do the four heuristic rules:
  # an if whose branch always runs, a derivation checked on purpose, a reviewed
  # snapshot and a null check that is the contract are benign cases the text
  # cannot tell apart.
  case "$1" in
  zero-assertion | recomputed-expectation | inert-assertion) printf 'high' ;;
  *) printf '' ;;
  esac
}

tier_of() {
  # The two change-detector rules flag tests that CAN fail, on a harmless
  # change, and a derived expectation, a snapshot or a weak oracle can fail
  # too, so all five sit below the can't-fail rules (detector-findings
  # crosswalk).
  case "$1" in
  constant-restatement | source-text-read | recomputed-derived | snapshot-only | weak-oracle) printf 'SUGGESTION' ;;
  *) printf 'IMPORTANT' ;;
  esac
}

surfaces_line() {
  printf 'Ran: [testing:audit — %d test file(s) examined (js/ts %d, python %d, csharp %d, bash %d, powershell %d, go %d), %d test block(s) parsed; findings: testing/audit/rule-zero-assertion %d, testing/audit/rule-recomputed-expectation %d, testing/audit/rule-mock-only-oracle %d; report-only findings (never gate --check): testing/audit/rule-inert-assertion %d, testing/audit/rule-constant-restatement %d, testing/audit/rule-source-text-read %d, testing/audit/rule-conditional-assertion %d, testing/audit/rule-recomputed-derived %d, testing/audit/rule-snapshot-only %d, testing/audit/rule-weak-oracle %d; declined (examined, rule did not fire): rule-zero-assertion %d, rule-mock-only-oracle %d, rule-recomputed-expectation not tallied (line-scoped rule; v1 does not count candidate assertions); exempted via cant-fail-ok: %d; playwright configs: %d examined of %d enumerated (%d shadowed, %d without a recognizable config object, %d unreadable); config findings: testing/audit/rule-flaky-passes-suite %d, testing/audit/rule-only-not-forbidden %d; config declined (examined, rule did not fire): rule-flaky-passes-suite %d, rule-only-not-forbidden %d; config exempted via cant-fail-ok: rule-flaky-passes-suite %d, rule-only-not-forbidden %d]. Returned no result: [%s].\n' \
    "$examined" "$enum_js" "$enum_py" "$enum_cs" "$enum_sh" "$enum_ps" "$enum_go" "$blocks" \
    "$n_cf1" "$n_cf2" "$n_cf3" "$n_ia" "$n_cr" "$n_st" "$n_ca" "$n_rd" "$n_so" "$n_wo" "$declined_cf1" "$declined_cf3" "$exempted" \
    "$cfg_examined" "$cfg_enum" "$cfg_shadowed" "$cfg_unparsed" "$cfg_unreadable" \
    "$n_cfg1" "$n_cfg2" "$d_cfg1" "$d_cfg2" "$x_cfg1" "$x_cfg2" \
    "$(if [[ "$unreadable" -gt 0 || "$cfg_unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then
      printf '%d unreadable test file(s), %d unreadable playwright config(s), %d walk/read error line(s)' "$unreadable" "$cfg_unreadable" "$walk_errors"
    else
      printf 'none — every discovered test file was examined'
    fi)"
}

coverage_block() {
  printf '\nScan coverage (the denominator — what this run actually read):\n'
  printf '  root: %s (resolved from %s)\n' "$ROOT" "$ROOT_SOURCE"
  printf '  test files: %d examined of %d enumerated (js/ts %d, python %d, csharp %d, bash %d, powershell %d, go %d); %d unreadable\n' \
    "$examined" "$enumerated" "$enum_js" "$enum_py" "$enum_cs" "$enum_sh" "$enum_ps" "$enum_go" "$unreadable"
  if [[ -n "$FILE" ]]; then
    if [[ -n "$tc_off_winner" ]]; then
      printf '  adapter: none (%s claims this file and is off in .claude/testing.yaml)\n' "$tc_off_winner"
    else
      printf '  adapter: %s\n' "${file_adapter[$FILE]:-none (no adapter claims this file)}"
    fi
  fi
  printf '  test blocks parsed: %d; blocks that fired a block rule: %d; exempted findings (cant-fail-ok): %d\n' \
    "$blocks" "$fired_blocks" "$exempted"
  if [[ "$cfg_enum" -eq 0 ]]; then
    printf '  playwright configs: 0 enumerated; config rules not applicable\n'
  else
    printf '  playwright configs: %d examined of %d enumerated (%d shadowed, %d without a recognizable config object, %d unreadable)\n' \
      "$cfg_examined" "$cfg_enum" "$cfg_shadowed" "$cfg_unparsed" "$cfg_unreadable"
  fi
  if ((tc_layers)); then
    printf '  .claude/testing.yaml: %d layer(s); excluded by paths.exclude: %d; included but claimed by no adapter: %d; claimed by a disabled adapter: %d; findings dropped by rules off: %d, kept out of the gate by warn: %d, gated by error: %d\n' \
      "$tc_layers" "$tc_excluded" "$tc_unclaimed" "$tc_disabled" "$tc_dropped" "$tc_ungate" "$tc_gate"
    if [[ -z "$FILE" && ${#tc_uncovered[@]} -gt 0 ]]; then
      printf '  test-scan hook: no shipped hook row matches %s, so the hook skips those files; /testing:setup check prints a hook entry to add\n' \
        "$(printf '%s, ' "${tc_uncovered[@]}" | sed 's/, $//')"
    fi
  fi
  printf '  files whose lexer lost sync (not judged): %d\n' "$lost"
  printf '  walk/read/engine error lines: %d\n' "$walk_errors"
  printf '  never in scope here: skipped/ignored tests, test files of other ecosystems, evals/fixtures corpora, and pruned dependency/build/memory dirs; a skip that vacates a discriminating case in a bash *.test.sh is scripts/check-discriminating-test-skips.sh'"'"'s, not this scan'"'"'s\n'
  if [[ "$examined" -eq 0 ]]; then
    printf '  NOTE: 0 test files examined — this run has no denominator. It is a scan of nothing, not a clean bill.\n'
  fi
}

config_findings_note() {
  # Appended to the two 0-examined-test-files refusals. Config findings are
  # reported wherever they are found, but a config file is not a test file:
  # without an examined test file the run has no test denominator, so the
  # findings are named rather than gated or persisted.
  if [[ "$cfg_findings" -gt 0 ]]; then
    printf ' (%d config finding(s) were reported; they are not gated or persisted without an examined test file)' "$cfg_findings"
  fi
}

advisory_note() {
  # Printed only when the gate is not strict. One switch escalates
  # mock-only-oracle and both config rules together, so the note counts them
  # apart and names the switch.
  if [[ "$strict" -eq 0 && "$advisory" -gt 0 ]]; then
    local ids
    ids="$(printf '%s\n' "${!a_advisory[@]}" | sort | paste -sd, - | sed 's/,/, /g')"
    printf 'note: %d finding(s) are advisory in --check (use --strict to gate them): mock-only-oracle %d, playwright config rules %d, advisory adapters (%s) %d.\n' \
      "$advisory" "$n_cf3" "$cfg_findings" "$ids" "$n_adv"
  fi
  # A rule raised to error in .claude/testing.yaml gates, so it is not listed.
  local pair n=0 list=""
  for pair in "inert-assertion $n_ia" "constant-restatement $n_cr" "source-text-read $n_st" \
    "conditional-assertion $n_ca" "recomputed-derived $n_rd" "snapshot-only $n_so" "weak-oracle $n_wo"; do
    [[ "${rule_level[${pair% *}]:-}" != error ]] || continue
    n=$((n + ${pair#* }))
    list+="${list:+, }$pair"
  done
  if [[ "$n" -gt 0 ]]; then
    printf 'note: %d finding(s) are report-only and never gate --check, --strict included: %s.\n' "$n" "$list"
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
  case "$s" in
  true | True | TRUE | false | False | FALSE | yes | Yes | YES | no | No | NO | \
    on | On | ON | off | Off | OFF | null | Null | NULL | '~')
    needs_quote=1
    ;;
  *) ;;
  esac
  if [[ "$s" =~ ^[+-]?[0-9]+$ || "$s" =~ ^[+-]?[0-9]*\.[0-9]+([eE][+-]?[0-9]+)?$ ||
    "$s" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} || "$s" =~ ^0[xXoObB][0-9a-fA-F_]+$ ]]; then
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
    printf 'ERROR: --findings refused — 0 test files were examined, so there is no coverage to persist and a findings file would assert a scan that never ran.%s\n' "$(config_findings_note)" >&2
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
    printf '| %d | %s | %s | %s | testing:audit | %s: %s (%s) | %s |\n' \
      "$rank" "$(tier_of "${f_rule[$i]}")" "$conf" "${f_loc[$i]}" \
      "$(rule_id "${f_rule[$i]}")" "$(esc_cell "${f_detail[$i]}")" "$(threshold_of "${f_rule[$i]}")" \
      "$(esc_cell "$(action_of "${f_rule[$i]}" "${f_lang[$i]}")")"
  done
  printf '\n## Surfaces\n\n'
  surfaces_line
}

print_findings_lines() {
  local i
  for i in ${f_rule[@]+"${!f_rule[@]}"}; do
    printf 'finding [%s] %s: %s (%s). Action: %s\n' \
      "$(rule_id "${f_rule[$i]}")" "${f_loc[$i]}" "${f_detail[$i]}" \
      "$(threshold_of "${f_rule[$i]}")" "$(action_of "${f_rule[$i]}" "${f_lang[$i]}")"
  done
}

case "$mode" in
count)
  printf '%d\n' "$total"
  coverage_block >&2
  if [[ "$unreadable" -gt 0 || "$cfg_unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
  exit 0
  ;;
findings)
  emit_findings_file
  coverage_block >&2
  if [[ "$unreadable" -gt 0 || "$cfg_unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
  exit 0
  ;;
check)
  if [[ "$total" -gt 0 ]]; then
    print_findings_lines
    advisory_note
  fi
  coverage_block
  # The 0-examined refusal is decided BEFORE the gating count, so a tree holding
  # only a Playwright config exits 2 under --strict as well: a config file is
  # not a test denominator, and every gating test-body finding implies an
  # examined test file, so this order changes no test-file path.
  if [[ "$examined" -eq 0 ]]; then
    printf '\nFAIL (closed): 0 test files were examined — a scan of nothing is not a clean gate. A wrong or empty scan root and a healthy suite must not share an exit code; point the gate at a tree that contains test files.%s\n' "$(config_findings_note)"
    exit 2
  fi
  if [[ "$gating" -gt 0 ]]; then
    printf '\nFAIL: %d gating finding(s).\n' "$gating"
    exit 1
  fi
  if [[ "$unreadable" -gt 0 || "$cfg_unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then
    printf '\nFAIL (closed): 0 gating findings, but %d unreadable test file(s), %d unreadable playwright config(s), and %d walk/read/engine error line(s) — an input the scan could not fully read is never a clean one.\n' \
      "$unreadable" "$cfg_unreadable" "$walk_errors"
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
  if [[ "$unreadable" -gt 0 || "$cfg_unreadable" -gt 0 || "$walk_errors" -gt 0 ]]; then exit 2; fi
  exit 0
  ;;
*)
  printf 'ERROR: unhandled mode %s\n' "$mode" >&2
  exit 2
  ;;
esac
