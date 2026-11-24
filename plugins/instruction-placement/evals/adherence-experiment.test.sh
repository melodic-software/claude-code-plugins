#!/usr/bin/env bash
# fixture-isolation-scope: the harness under test builds git fixtures, so this
# suite clears the inherited git environment itself rather than sourcing a
# harness, keeping the plugin self-contained outside this marketplace.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/adherence-experiment.sh"

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

assert_lacks() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "does NOT contain: $3" "$2"; fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

STUB="$SANDBOX/stub-claude"
cat >"$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
set -uo pipefail
plan="${STUB_PLAN:?STUB_PLAN unset}"
state="${STUB_STATE:?STUB_STATE unset}"
n=$(($(cat "$state" 2>/dev/null || printf '0') + 1))
printf '%s' "$n" >"$state"
directive="$(sed -n "${n}p" "$plan")"
emit() {
  printf '\npublic %sclass InvoiceTotal\n{\n    private decimal %s;\n\n    public void Add(decimal amount) => %s += amount;\n\n    public decimal Total => %s;\n}\n' \
    "$1" "$2" "$2" "$2" >>src/Billing.cs
}
case "$directive" in
compliant) emit 'sealed ' '_total' ;;
bare) emit '' 'total' ;;
sealed-only) emit 'sealed ' 'total' ;;
underscore-only) emit '' '_total' ;;
primary-first)
  {
    printf 'public sealed class InvoiceTotal(decimal seed);\n\n'
    cat src/Billing.cs
  } >src/Billing.cs.new && mv src/Billing.cs.new src/Billing.cs
  ;;
brace-in-string)
  cat >>src/Billing.cs <<'CS'

public sealed class InvoiceTotal
{
    private decimal total;

    public void Add(decimal amount) => total += amount;

    public string Label => "unbalanced { brace";
}

public sealed class Trailer
{
    private decimal _shouldNotCount;
}
CS
  ;;
comment-decl)
  cat >>src/Billing.cs <<'CS'

public sealed class InvoiceTotal
// a class that tracks a running total
{
    private decimal _total;

    public decimal Total => _total;
}
CS
  ;;
decoy-class)
  cat >>src/Billing.cs <<'CS'

public sealed class InvoiceTotals
{
    private decimal _total;

    public void Add(decimal amount) => _total += amount;

    public decimal Total => _total;
}
CS
  ;;
auto-property)
  cat >>src/Billing.cs <<'CS'

public sealed class InvoiceTotal
{
    private decimal _total { get; set; }

    public void Add(decimal amount) => _total += amount;

    public decimal Total => _total;
}
CS
  ;;
expr-bodied)
  cat >>src/Billing.cs <<'CS'

public sealed class InvoiceTotal
{
    private decimal total;

    private decimal _Total => total;

    private decimal _GetTotal() => total;

    public void Add(decimal amount) => total += amount;
}
CS
  ;;
noop) : ;;
crash) exit 1 ;;
*)
  printf 'stub: no directive for invocation %s\n' "$n" >&2
  exit 1
  ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB"

PLAN="$SANDBOX/plan"
STATE="$SANDBOX/state"
export STUB_PLAN="$PLAN" STUB_STATE="$STATE"

run_with_plan() {
  local trials="$1" filler="$2"
  shift 2
  local extra=()
  while [[ "${1:-}" == --* ]]; do
    extra+=("$1")
    shift
  done
  : >"$PLAN"
  local d
  for d in "$@"; do printf '%s\n' "$d" >>"$PLAN"; done
  printf '0' >"$STATE"
  bash "$SCRIPT" --claude "$STUB" --trials "$trials" --filler "$filler" \
    "${extra[@]+"${extra[@]}"}" 2>&1
}

row() { printf '%s\t%s\t%s\t%s\t%s' "$@"; }
result_row() { printf 'RESULT\t%s\t%s\t%s\t%s\t%s' "$@"; }

assert_usage_error() {
  local desc="$1"
  shift
  bash "$SCRIPT" "$@" >/dev/null 2>&1
  assert_eq "$desc" "2" "$?"
}

out="$(bash "$SCRIPT" --help)"
assert_eq "--help exits 0" "0" "$?"
assert_contains "--help prints the usage banner" "$out" "adherence-experiment.sh"
assert_contains "--help documents --filler" "$out" "--filler"

assert_usage_error "an unknown argument is a usage error" --bogus
assert_usage_error "--trials with no value is a usage error" --trials
assert_usage_error "a non-integer --trials is a usage error" --trials abc
assert_usage_error "--filler with no value is a usage error" --filler
assert_usage_error "a non-integer --filler is a usage error" --filler abc
assert_usage_error "--claude with no value is a usage error" --claude

out="$(bash "$SCRIPT" --claude /nonexistent-cli-xyz 2>&1)"
rc=$?
assert_eq "an absent CLI exits 3" "3" "$rc"
assert_contains "the absent CLI reports UNKNOWN" "$out" "UNKNOWN"
assert_lacks "an unmeasurable run prints no RESULT row" "$out" "RESULT"

out="$(run_with_plan 0 3 --keep)"
assert_eq "a zero-trial run still exits 0" "0" "$?"
kept="$(printf '%s\n' "$out" | sed -n 's/^Fixture kept at: //p')"
if [[ -n "$kept" && -d "$kept" ]]; then
  pass "--keep leaves the fixture on disk and names it"
else
  fail "--keep leaves the fixture on disk and names it" "an existing directory" "$kept"
fi

control_agents="$kept/control/AGENTS.md"
treatment_agents="$kept/treatment/AGENTS.md"
control_rule="$kept/control/.claude/rules/csharp.md"
treatment_rule="$kept/treatment/.claude/rules/csharp.md"

if [[ -f "$control_agents" && -f "$treatment_agents" ]]; then
  pass "both arms build an AGENTS.md"
else
  fail "both arms build an AGENTS.md" "two files" "$control_agents $treatment_agents"
fi

assert_eq "the control arm carries the convention in its always-loaded file" \
  "1" "$(grep -c '^## C# class conventions$' "$control_agents" | tr -d ' ')"
assert_eq "the treatment arm's always-loaded file does NOT carry it" \
  "0" "$(grep -c '^## C# class conventions$' "$treatment_agents" | tr -d ' ')"

if [[ -f "$treatment_rule" ]]; then
  pass "the treatment arm carries the convention as a path-scoped rule"
else
  fail "the treatment arm carries the convention as a path-scoped rule" \
    "$treatment_rule exists" "missing"
fi
if [[ -f "$control_rule" ]]; then
  fail "the control arm has NO path-scoped rule" "no $control_rule" "present"
else
  pass "the control arm has NO path-scoped rule"
fi

rule_body="$(cat "$treatment_rule" 2>/dev/null)"
assert_contains "the rule is scoped to the file type the task edits" "$rule_body" '**/*.cs'
assert_contains "the rule carries the identical convention text" "$rule_body" \
  '## C# class conventions'
# shellcheck disable=SC2016 # markdown code span; the backticks are literal
assert_contains "the rule carries the sealed clause verbatim" "$rule_body" 'declared `sealed`'
assert_contains "the rule carries the underscore clause verbatim" "$rule_body" '_camelCase'

assert_eq "both arms get identical filler volume (control)" \
  "6" "$(grep -c '^## Repository practice ' "$control_agents" | tr -d ' ')"
assert_eq "both arms get identical filler volume (treatment)" \
  "6" "$(grep -c '^## Repository practice ' "$treatment_agents" | tr -d ' ')"

if [[ -f "$kept/control/src/Billing.cs" ]] &&
  cmp -s "$kept/control/src/Billing.cs" "$kept/treatment/src/Billing.cs"; then
  pass "both arms seed the same existing .cs file for the edit task"
else
  fail "both arms seed the same existing .cs file for the edit task" \
    "identical Billing.cs in both arms" "differ or missing"
fi

for arm in control treatment; do
  dirty="$(git -C "$kept/$arm" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  assert_eq "the $arm arm is a committed git repo (reset can work)" "0" "$dirty"
done

assert_contains "the header reports both always-loaded file sizes" "$out" \
  "CONTROL AGENTS.md is"
control_lines="$(wc -l <"$control_agents" | tr -d ' ')"
treatment_lines="$(wc -l <"$treatment_agents" | tr -d ' ')"
if ((control_lines > treatment_lines)); then
  pass "the control arm's always-loaded file is the larger one"
else
  fail "the control arm's always-loaded file is the larger one" \
    "control > treatment" "$control_lines vs $treatment_lines"
fi
rm -rf "$kept"

out="$(run_with_plan 1 2 compliant bare)"
assert_contains "a compliant trial scores sealed, underscore and both" "$out" \
  "$(row control 1 1 1 1)"
assert_contains "a non-compliant trial scores zero on every criterion" "$out" \
  "$(row treatment 1 0 0 0)"

out="$(run_with_plan 1 2 sealed-only underscore-only)"
assert_contains "sealed without the underscore scores 1/0, not both" "$out" \
  "$(row control 1 1 0 0)"
assert_contains "the underscore without sealed scores 0/1, not both" "$out" \
  "$(row treatment 1 0 1 0)"

out="$(run_with_plan 1 2 noop noop)"
assert_contains "a trial that writes nothing scores zero (control)" "$out" \
  "$(row control 1 0 0 0)"
assert_contains "a trial that writes nothing scores zero (treatment)" "$out" \
  "$(row treatment 1 0 0 0)"

out="$(run_with_plan 1 2 comment-decl primary-first)"
assert_contains "a comment before the opening brace does not lose the body" "$out" \
  "$(row control 1 1 1 1)"
assert_contains "a body-less class is not credited with a later class's field" "$out" \
  "$(row treatment 1 1 0 0)"

out="$(run_with_plan 1 2 brace-in-string noop)"
assert_contains "a brace inside a string literal does not leak the next class in" \
  "$out" "$(row control 1 1 0 0)"

out="$(run_with_plan 1 2 decoy-class auto-property)"
assert_contains "a class whose name merely STARTS with InvoiceTotal scores nothing" \
  "$out" "$(row control 1 0 0 0)"
assert_contains "an underscore auto-property is not an underscore field" "$out" \
  "$(row treatment 1 1 0 0)"

out="$(run_with_plan 1 2 expr-bodied noop)"
assert_contains "an expression-bodied member is not an underscore field" "$out" \
  "$(row control 1 1 0 0)"

out="$(run_with_plan 2 2 compliant crash bare compliant)"
assert_eq "a run with a failed trial still exits 0" "0" "$?"
assert_contains "round 1 control scores compliant" "$out" "$(row control 1 1 1 1)"
assert_contains "a failed trial is reported as an ERROR row" "$out" \
  "$(printf 'treatment\t1\t-\t-\tERROR')"

assert_contains "each trial starts from a reset tree, not the last trial's edit" \
  "$out" "$(row control 2 0 0 0)"
assert_contains "round 2 treatment scores compliant" "$out" "$(row treatment 2 1 1 1)"

assert_contains "the control arm tallies both of its scored trials" "$out" \
  "$(result_row control 2 1 1 1)"
assert_contains "a crashed trial is excluded from the arm's n" "$out" \
  "$(result_row treatment 1 1 1 1)"

assert_contains "the honesty bound is restated with the numbers" "$out" \
  "no p-value is computed"

PRIVATE_TMP="$SANDBOX/tmp"
mkdir -p "$PRIVATE_TMP"
out="$(TMPDIR="$PRIVATE_TMP" run_with_plan 1 2 compliant compliant)"
assert_lacks "a run without --keep does not announce a kept fixture" "$out" "Fixture kept at"
leftover="$(find "$PRIVATE_TMP" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
assert_eq "a run without --keep removes its fixture" "0" "$leftover"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
