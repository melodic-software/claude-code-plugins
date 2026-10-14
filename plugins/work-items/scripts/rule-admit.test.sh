#!/usr/bin/env bash
# A fake `gh` on PATH serves one fixture case at a time (issue, comments, body
# edit time) from fixtures/rule-admit/cases.json, and each case's verdict is
# checked against the expectation it carries.
# test-scope: plugins/work-items/scripts/fixtures/rule-admit/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/rule-admit.sh"
FIX="$SCRIPT_DIR/fixtures/rule-admit"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
endpoint=""
for a in "$@"; do
  case "$a" in
  api | -*) : ;;
  *=*) [[ "$a" == */* ]] && [[ -z "$endpoint" ]] && endpoint="$a" ;;
  *) [[ -z "$endpoint" ]] && endpoint="$a" ;;
  esac
done
path="${endpoint%%\?*}"
fails=" ${FAKE_GH_FAIL:-} "
case "$path" in
graphql)
  [[ "$fails" == *" graphql "* ]] && exit 1
  jq -c '{data: {repository: {issue: {lastEditedAt: (if .last_edited_at == "" then null else .last_edited_at end)}}}}' "$FAKE_CASE"
  ;;
*/comments)
  [[ "$fails" == *" comments "* ]] && exit 1
  jq -c '.comments' "$FAKE_CASE"
  ;;
*)
  [[ "$fails" == *" issue "* ]] && exit 1
  jq -c '.issue' "$FAKE_CASE"
  ;;
esac
FAKE
chmod +x "$BIN/gh"
PATH="$BIN:$PATH"
export PATH

REPO=melodic-software/example-repo
if command -v sha256sum >/dev/null 2>&1; then
  BINDING_SHA="$(sha256sum "$FIX/binding.json" | cut -c1-12)"
else
  BINDING_SHA="$(shasum -a 256 "$FIX/binding.json" | cut -c1-12)"
fi

# --- every fixture case -----------------------------------------------------
count="$(jq '.cases | length' "$FIX/cases.json")"
for ((i = 0; i < count; i++)); do
  jq --argjson i "$i" '.base as $b | .cases[$i] as $c
    | {issue: ($b.issue * ($c.issue // {})),
       comments: ($c.comments // $b.comments),
       last_edited_at: ($c.last_edited_at // $b.last_edited_at),
       name: $c.name, expect: $c.expect}' "$FIX/cases.json" >"$WORK/case.json"
  name="$(jq -r .name "$WORK/case.json")"
  FAKE_CASE="$WORK/case.json" bash "$CHECK" --repo "$REPO" --binding "$FIX/binding.json" --issue 1 >"$WORK/out" 2>"$WORK/err"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$name (exit $rc: $(cat "$WORK/err"))"
    continue
  fi
  if jq -e --slurpfile c "$WORK/case.json" --arg sha "$BINDING_SHA" '
      $c[0].expect as $e
      | .verdict == $e.verdict
        and ($e.rule == null or .rule == $e.rule)
        and ($e.constraint == null or .constraint == $e.constraint)
        and ($e.reason == null or (.reason | contains($e.reason)))
        and .binding_sha == $sha
        and (.verdict != "admit" or .reason == "admitted-by-rule: \($e.rule)@\($sha)")' \
    "$WORK/out" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name (got: $(cat "$WORK/out"))"
  fi
done

# --- read failures refuse, never admit -------------------------------------
jq '{issue: .base.issue, comments: .base.comments, last_edited_at: .base.last_edited_at}' "$FIX/cases.json" >"$WORK/case.json"
for what in issue comments graphql; do
  if FAKE_CASE="$WORK/case.json" FAKE_GH_FAIL="$what" bash "$CHECK" --repo "$REPO" --binding "$FIX/binding.json" --issue 1 >"$WORK/out" 2>/dev/null &&
    jq -e '.verdict == "refuse" and (.reason | test("read failed"))' "$WORK/out" >/dev/null; then
    pass "a failed $what read refuses"
  else
    fail "a failed $what read refuses (got: $(cat "$WORK/out"))"
  fi
done

# --- several issues: one row each, in order ---------------------------------
FAKE_CASE="$WORK/case.json" bash "$CHECK" --repo "$REPO" --binding "$FIX/binding.json" --issue 1 --issue 2 >"$WORK/out" 2>/dev/null
if [[ "$(jq -s -c '[.[].issue]' "$WORK/out")" == "[1,2]" ]]; then pass "one row per issue"; else fail "one row per issue (got: $(cat "$WORK/out"))"; fi

# --- a binding with no usable rules admits nothing --------------------------
FAKE_CASE="$WORK/case.json"
export FAKE_CASE
binding_case() { # $1 label, $2 binding JSON
  printf '%s\n' "$2" >"$WORK/binding.json"
  bash "$CHECK" --repo "$REPO" --binding "$WORK/binding.json" --issue 1 >"$WORK/out" 2>/dev/null
  local rc=$?
  if [[ $rc -eq 4 && ! -s "$WORK/out" ]]; then pass "$1 exits 4"; else fail "$1 exits 4 (got $rc: $(cat "$WORK/out"))"; fi
}
binding_case "no rule_admission" '{"admission": {}}'
binding_case "a C3 rule" '{"admission": {"rule_admission": [{"id": "R1", "work_class": "C3", "proposed_class": "work-class: scoped"}]}}'
binding_case "a verified term" '{"admission": {"rule_admission": [{"id": "R1", "work_class": "C1", "proposed_class": "work-class: read-only", "verified": true}]}}'
binding_case "duplicate proposed classes" '{"admission": {"rule_admission": [{"id": "R1", "work_class": "C1", "proposed_class": "work-class: read-only"}, {"id": "R2", "work_class": "C2", "proposed_class": "work-class: read-only"}]}}'
binding_case "unparsable JSON" '{'

# The posture and the decision table gate rule admission (owner disposition of
# security finding 3): R2 here is valid, so only the gate can stop it.
R2='"rule_admission": [{"id": "R2", "work_class": "C2", "proposed_class": "work-class: mechanical"}]'
C2_ELIGIBLE='{"signal_class": "*", "provenance": "*", "work_class": "C2", "disposition": "autonomous-eligible"}'
binding_case "dispatch_posture human-gated-only" "{\"dispatch_posture\": \"human-gated-only\", \"admission\": {\"rules\": [$C2_ELIGIBLE], $R2}}"
binding_case "no decision-table rules" "{\"admission\": {$R2}}"
binding_case "no decision-table rule for C2 (default human-gated)" "{\"admission\": {\"rules\": [], $R2}}"
binding_case "C2 human-gated for agent provenance, most specific wins" "{\"admission\": {\"rules\": [$C2_ELIGIBLE, {\"signal_class\": \"tracker-vcs-event\", \"provenance\": \"agent\", \"work_class\": \"C2\", \"disposition\": \"human-gated\"}], $R2}}"
# Control: a narrower rule for another signal class leaves issues admissible.
printf '%s\n' "{\"admission\": {\"rules\": [$C2_ELIGIBLE, {\"signal_class\": \"temporal\", \"provenance\": \"*\", \"work_class\": \"C2\", \"disposition\": \"human-gated\"}], $R2}}" >"$WORK/binding.json"
if bash "$CHECK" --repo "$REPO" --binding "$WORK/binding.json" --issue 1 >"$WORK/out" 2>/dev/null &&
  jq -e '.verdict == "admit" and .rule == "R2"' "$WORK/out" >/dev/null; then
  pass "a C2 gate on another signal class still admits an issue"
else
  fail "a C2 gate on another signal class still admits an issue (got: $(cat "$WORK/out"))"
fi
bash "$CHECK" --repo "$REPO" --binding "$WORK/missing.json" --issue 1 >/dev/null 2>&1
rc=$?
if [[ $rc -eq 4 ]]; then pass "a missing binding exits 4"; else fail "a missing binding exits 4 (got $rc)"; fi

# --- usage ------------------------------------------------------------------
for args in "--binding $FIX/binding.json --issue 1" "--repo $REPO --issue 1" "--repo $REPO --binding $FIX/binding.json" "--repo $REPO --binding $FIX/binding.json --issue 0" "--repo $REPO --binding $FIX/binding.json --issue 1 --bogus x"; do
  # shellcheck disable=SC2086 # word splitting builds the argument list
  bash "$CHECK" $args >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then pass "usage exits 2: $args"; else fail "usage exits 2: $args (got $rc)"; fi
done

if ((FAILED > 0)); then
  printf '%d check(s) failed\n' "$FAILED" >&2
  exit 1
fi
echo "All rule-admit checks passed."
