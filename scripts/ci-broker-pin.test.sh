#!/usr/bin/env bash
# Runs the `Require a broker pin PR for a broker-fetched change` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against a stub `gh` that applies the
# step's own --jq filter to a pull-request files fixture.
#
# The lanes token broker in melodic-software/azure-iac runs resolve-config at a
# pinned commit, fetched by azure-iac scripts/deploy/fetch-resolve-config.sh
# (runtime list: resolve.mjs predicate.mjs vocabulary.mjs package.json
# package-lock.json under .github/actions/resolve-config). A pull request that
# changes one of those files must name its paired pin pull request, or the
# broker keeps parsing the config with the old code (#8313, azure-iac#44).
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Require a broker pin PR for a broker-fetched change'
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
LINE='Broker pin: melodic-software/azure-iac#44'

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

for f in resolve.mjs predicate.mjs vocabulary.mjs package.json package-lock.json; do
  expect "a change to $f without the line fails" 1 1 "$(files "$RC/$f")" "Closes #1" 0 "::error::"
  expect "a change to $f with the line passes" 0 1 "$(files "$RC/$f")" "Closes #1
$LINE" 0
done
expect "the error names the broker-fetched path" 1 1 "$(files README.md "$RC/resolve.mjs")" "" 0 "$RC/resolve.mjs"
expect "the error names the required line" 1 1 "$(files "$RC/resolve.mjs")" "" 0 "Broker pin: melodic-software/azure-iac#<n>"
expect "files the broker does not fetch need no line" 0 1 \
  "$(files "$RC/README.md" "$RC/resolve.test.mjs" "$RC/resolve-config.mjs" "$RC/lane-rules.json" "$RC/fixtures/vocabulary.json")" "" 0
expect "a same-named file elsewhere needs no line" 0 1 "$(files "scripts/resolve.mjs" "$RC/sub/package.json" "$RC/resolve.mjs.orig")" "" 0
expect "a rename away from a broker-fetched path fails" 1 1 \
  "[{\"filename\":\"$RC/old/resolve.mjs\",\"previous_filename\":\"$RC/resolve.mjs\",\"status\":\"renamed\"}]" "" 0 "$RC/resolve.mjs"
expect "a CRLF body line counts" 0 1 "$(files "$RC/resolve.mjs")" $'Closes #1\r\n'"$LINE"$'\r\n## Summary\r' 0
expect "trailing blanks after the number count" 0 1 "$(files "$RC/resolve.mjs")" "$LINE  " 0
expect "the line inside other text does not count" 1 1 "$(files "$RC/resolve.mjs")" "see $LINE" 0
expect "another repository does not count" 1 1 "$(files "$RC/resolve.mjs")" "Broker pin: melodic-software/other#44" 0
expect "a line with no number does not count" 1 1 "$(files "$RC/resolve.mjs")" "Broker pin: melodic-software/azure-iac#" 0
expect "a transient files read failure is retried" 1 2 "$(files "$RC/resolve.mjs")" "" 1
expect "an unreadable file list fails closed" 1 3 "$(files README.md)" "$LINE" 3 "::error::could not read the files of #8313"

test_harness::report
