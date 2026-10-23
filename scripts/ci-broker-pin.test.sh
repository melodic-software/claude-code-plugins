#!/usr/bin/env bash
# Runs the `Require a broker deploy PR for a resolve-config dependency change` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against a stub `gh` that applies the
# step's own --jq filter to a pull-request files fixture.
#
# The lanes token broker in melodic-software/azure-iac loads resolve-config's
# modules from main's tip but imports ajv and yaml from its own deployment, and
# denies every token while main's package.json or package-lock.json under
# .github/actions/resolve-config differs from the deployed one. A pull request
# that changes either file must name the azure-iac pull request that deploys
# the new dependencies.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" || fail "the ci-status gh_read helper step is missing or fails"

NAME='Require a broker deploy PR for a resolve-config dependency change'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
# shellcheck disable=SC2016 # workflow literals to match, not shell expansions
for line in "if: \${{ !cancelled() && github.event_name == 'pull_request' }}" \
  'PR_BODY: ${{ github.event.pull_request.body }}' \
  'PR_NUMBER: ${{ github.event.pull_request.number }}'; do
  if [[ "$step" == *"$line"* ]]; then ok "step carries '$line'"; else fail "step lost '$line'"; fi
done
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the gate"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line step_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$step_line" && "$step_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

# The stub logs its arguments, fails the first STUB_FAILS calls, then applies
# the --jq argument to STUB_JSON, as gh does to each page.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
calls=$(wc -l <"$STUB_LOG")
[[ "$calls" -gt "${STUB_FAILS:-0}" ]] || exit 1
filter=
while [[ $# -gt 0 ]]; do
  [[ "$1" == --jq ]] && { filter="$2"; shift; }
  shift
done
jq -r "$filter" <<<"$STUB_JSON"
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

RC=.github/actions/resolve-config
LINE='Broker deploy: melodic-software/azure-iac#44'

# files <path>... : a pulls/<n>/files page with one entry per path.
files() {
  local p out='['
  for p in "$@"; do out+="{\"filename\":\"$p\",\"status\":\"modified\"},"; done
  printf '%s]' "${out%,}"
}

# expect <label> <want-rc> <want-gh-calls> <STUB_JSON> <PR_BODY> <STUB_FAILS> [want-out]
expect() {
  local label="$1" want_rc="$2" want_calls="$3" out rc calls
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_JSON="$4" PR_BODY="$5" STUB_FAILS="$6" \
    PR_NUMBER=8313 GITHUB_REPOSITORY=o/r bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(wc -l <"$TMP_ROOT/log")
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls gh call(s) got $calls"
  elif [[ "$want_calls" -gt 0 && "$(sort -u "$TMP_ROOT/log")" != "api repos/o/r/pulls/8313/files?per_page=100 --paginate --jq "* ]]; then
    fail "$label: unexpected gh call '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${7:-}" && "$out" != *"$7"* ]]; then
    fail "$label: output lacks '$7': '$out'"
  else
    ok "$label"
  fi
}

for f in package.json package-lock.json; do
  expect "a change to $f without the line fails" 1 1 "$(files "$RC/$f")" "Closes #1" 0 "::error::"
  expect "a change to $f with the line passes" 0 1 "$(files "$RC/$f")" "Closes #1
$LINE" 0
done
expect "the error names the dependency path" 1 1 "$(files README.md "$RC/package-lock.json")" "" 0 "$RC/package-lock.json"
expect "the error names the required line" 1 1 "$(files "$RC/package.json")" "" 0 "Broker deploy: melodic-software/azure-iac#<n>"
expect "modules the broker loads from main need no line" 0 1 \
  "$(files "$RC/resolve.mjs" "$RC/dimensions.mjs" "$RC/predicate.mjs" "$RC/vocabulary.mjs")" "" 0
expect "files the broker does not load need no line" 0 1 \
  "$(files "$RC/README.md" "$RC/resolve.test.mjs" "$RC/resolve-config.mjs" "$RC/lane-rules.json" "$RC/fixtures/vocabulary.json")" "" 0
expect "a same-named file elsewhere needs no line" 0 1 "$(files "package.json" "$RC/sub/package.json" "$RC/package.json.orig")" "" 0
expect "a rename away from a dependency path fails" 1 1 \
  "[{\"filename\":\"$RC/old/package.json\",\"previous_filename\":\"$RC/package.json\",\"status\":\"renamed\"}]" "" 0 "$RC/package.json"
expect "a CRLF body line counts" 0 1 "$(files "$RC/package.json")" $'Closes #1\r\n'"$LINE"$'\r\n## Summary\r' 0
expect "trailing blanks after the number count" 0 1 "$(files "$RC/package.json")" "$LINE  " 0
expect "the line inside other text does not count" 1 1 "$(files "$RC/package.json")" "see $LINE" 0
expect "another repository does not count" 1 1 "$(files "$RC/package.json")" "Broker deploy: melodic-software/other#44" 0
expect "a line with no number does not count" 1 1 "$(files "$RC/package.json")" "Broker deploy: melodic-software/azure-iac#" 0
expect "the old pin line does not count" 1 1 "$(files "$RC/package.json")" "Broker pin: melodic-software/azure-iac#44" 0
expect "a transient files read failure is retried" 1 2 "$(files "$RC/package.json")" "" 1
expect "an unreadable file list fails closed" 1 3 "$(files README.md)" "$LINE" 3 "::error::could not read the files of #8313"

test_harness::report
