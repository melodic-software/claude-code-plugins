#!/usr/bin/env bash
# Runs the `Fail a draft` step body of .github/workflows/pr-require-checks.yml's ci-status
# under the shell Actions gives a step with no `shell:` (bash -e), against a
# stub `gh`.
#
# The case that matters is the re-run: a contract-only run drawn while the pull
# request was a draft keeps that payload when the full run re-runs it after the
# flip to ready, and must then pass. Every other combination stays red.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# The step, from its `- name:` line to the next step.
step="$(awk '/^      - name: Fail a draft$/ { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
# Its `run: |` body, de-indented.
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no 'Fail a draft' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
for line in "if: github.event.pull_request.draft == true" \
  "CONTRACT_ONLY: \${{ github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base)) }}" \
  "PR: \${{ github.event.pull_request.number }}"; do
  if [[ "$step" == *"$line"* ]]; then ok "step carries '$line'"; else fail "step lost '$line'"; fi
done

# The stub logs its arguments and answers with STUB_DRAFT, or fails when
# STUB_RC is non-zero.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[[ "${STUB_RC:-0}" -eq 0 ]] || exit "$STUB_RC"
printf '%s\n' "$STUB_DRAFT"
EOF
chmod +x "$TMP_ROOT/bin/gh"

# expect <label> <want-rc> <want-gh-call: yes|no> <CONTRACT_ONLY> <STUB_DRAFT> <STUB_RC>
expect() {
  local label="$1" want_rc="$2" want_call="$3" out rc called=no
  : >"$TMP_ROOT/log"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" CONTRACT_ONLY="$4" STUB_DRAFT="$5" STUB_RC="$6" \
    GITHUB_REPOSITORY=o/r PR=7 bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  [[ -s "$TMP_ROOT/log" ]] && called=yes
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$called" != "$want_call" ]]; then
    fail "$label: expected gh called=$want_call got $called"
  elif [[ "$called" == yes && "$(cat "$TMP_ROOT/log")" != "api repos/o/r/pulls/7 --jq .draft" ]]; then
    fail "$label: unexpected gh call '$(cat "$TMP_ROOT/log")'"
  elif [[ "$rc" -ne 0 && "$out" != *"::error::draft: lanes not run."* ]]; then
    fail "$label: red without the draft reason: '$out'"
  else
    ok "$label"
  fi
}

expect "contract-only re-run after the flip to ready passes" 0 yes true false 0
expect "contract-only run on a draft fails" 1 yes true true 0
expect "contract-only run with an unreadable draft state fails closed" 1 yes true false 1
expect "contract-only run with an empty draft state fails closed" 1 yes true "" 0
expect "full run on a draft payload fails without asking" 1 no false false 0
expect "unset contract-only flag fails without asking" 1 no "" false 0

test_harness::report
