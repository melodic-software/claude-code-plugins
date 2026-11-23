#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REF="$SCRIPT_DIR/../../../reference/providers/github/pull-request/monitor.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export TMPDIR="$TEST_TMPDIR"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"

# The watch runs from a directory outside every checkout; <checkout> names a checkout whose one
# GitHub remote is acme/app, so the repository can come only from <checkout>.
CHECKOUT="$TEST_TMPDIR/checkout" OUTSIDE="$TEST_TMPDIR/outside"
git init -q "$CHECKOUT"
git -C "$CHECKOUT" remote add origin https://github.com/acme/app.git
mkdir -p "$OUTSIDE"
export GIT_CEILING_DIRECTORIES="$TEST_TMPDIR"
unset GH_REPO

PLUGIN="$TEST_TMPDIR/plugin"
mkdir -p "$PLUGIN/skills/pull-request/scripts" "$PLUGIN/scripts" "$PLUGIN/lib"
cp -p "$SCRIPT_DIR/monitor-poll.sh" "$SCRIPT_DIR/target-repo.sh" "$PLUGIN/skills/pull-request/scripts/"
cp -p "$SCRIPT_DIR/../../../lib/github-remote.sh" "$PLUGIN/lib/"
printf '#!/usr/bin/env bash\necho "THREADS_OK unresolved=0"\n' >"$PLUGIN/scripts/source-control-review-threads"
POLL="$PLUGIN/skills/pull-request/scripts/monitor-poll.sh"

cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "repo set-default" ]]; then
  echo "No default remote repository has been set." >&2
  exit 0
fi
if [[ "$1 $2" == "api repos/me/app" ]]; then
  echo acme/app
  exit 0
fi
# The PR on acme/app has the cross-repository head me:feature; a bare branch finds nothing.
if [[ "$1 $2" == "pr view" ]]; then
  [[ "$3" == me:feature && " $* " == *" -R acme/app "* ]] && { echo 17; exit 0; }
  echo "no pull requests found for branch \"$3\"" >&2
  exit 1
fi
[[ "$1" == api && " $* " == *" repos/acme/app/"* ]] || exit 1
case "$*" in
*/check-runs*)
  [[ -n "${STUB_FAIL_CHECKS:-}" ]] && exit 1
  b_status=${STUB_B:-completed}
  b_conclusion=null
  [[ "$b_status" == completed ]] && b_conclusion='"success"'
  printf '%s' '{"check_runs":[
    {"name":"a","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"completed","conclusion":"success"},
    {"name":"b","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"'"$b_status"'","conclusion":'"$b_conclusion"'},
    {"name":"c","check_suite":{"id":1},"started_at":"2026-01-01T00:00:00Z","status":"in_progress","conclusion":null}]}'
  ;;
*/pulls/5\ *)
  n=$(cat "$GH_STUB_COUNT" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$GH_STUB_COUNT"
  [[ "$n" -eq 0 ]] && echo "OPEN h1" || echo "MERGED h1"
  ;;
esac
exit 0
STUB_EOF
chmod +x "$STUB_DIR/gh"

run_poll() {
  rm -f "$TEST_TMPDIR/count"
  (cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" GH_STUB_COUNT="$TEST_TMPDIR/count" \
    timeout 30 bash "$POLL" --pr 5 --interval 0 --checkout "${TEST_CHECKOUT:-$CHECKOUT}" "$@" 2>&1)
}

out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$POLL" --checkout "$CHECKOUT" 2>&1)
assert_exit "no --pr: a usage error" 3 "$?"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$POLL" --pr 5 2>&1)
assert_exit "neither --checkout nor --repo: a usage error" 3 "$?"

out=$(TEST_CHECKOUT="$OUTSIDE" run_poll)
assert_exit "<checkout> names no repository: the watch exits 1" 1 "$?"
[[ -e "$TEST_TMPDIR/count" ]] && read_pr=yes || read_pr=no
assert_eq "<checkout> names no repository: no PR read is made" "no" "$read_pr"

out=$(run_poll)
assert_exit "no baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_not_contains "no baseline: the first poll only records, a is not emitted" "$out" "a: pass"
assert_not_contains "no baseline: the first poll only records, b is not emitted" "$out" "b: pass"
assert_contains "no baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"

out=$(STUB_B=in_progress run_poll --snapshot "$TEST_TMPDIR/baseline")
assert_exit "snapshot run: exits 0 after writing the snapshot" 0 "$?"
snap=$(cat "$TEST_TMPDIR/baseline" 2>/dev/null)
assert_contains "snapshot run: the snapshot holds the finished check" "$snap" "a: pass"
assert_not_contains "snapshot run: the snapshot leaves out the running check" "$snap" "b: "
assert_not_contains "snapshot run: emits no check lines" "$out" "a: pass"

out=$(run_poll --baseline "$TEST_TMPDIR/baseline")
assert_exit "baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_not_contains "baseline: a snapshot the script wrote is accepted" "$out" "BASELINE-UNREADABLE"
assert_contains "baseline: a check finished in the live read but not the baseline is emitted" "$out" "b: pass"
assert_not_contains "baseline: a check already in the baseline is not re-emitted" "$out" "a: pass"
assert_not_contains "baseline: a running check is not emitted" "$out" "c: "

out=$(run_poll --baseline "$TEST_TMPDIR/missing")
assert_exit "an unreadable baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "an unreadable baseline is reported, so the session runs a full scan" "$out" "BASELINE-UNREADABLE"
assert_contains "an unreadable baseline: the watch completes" "$out" "PR #5 MERGED — watch complete"
assert_not_contains "an unreadable baseline file falls back to record-only (a)" "$out" "a: pass"
assert_not_contains "an unreadable baseline file falls back to record-only (b)" "$out" "b: pass"

# A readable baseline the script did not write: rows in `gh pr checks` shape, and correct-looking
# lines with no snapshot marker. Either must fail closed to record-only plus a full scan, never
# re-emit finished checks as new.
printf 'a\tpass\t1m\thttps://x/1\nb\tpass\t1m\thttps://x/2\n' >"$TEST_TMPDIR/malformed"
out=$(run_poll --baseline "$TEST_TMPDIR/malformed")
assert_exit "a malformed baseline: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "a malformed baseline is refused, so the session runs a full scan" "$out" "BASELINE-UNREADABLE"
assert_not_contains "a malformed baseline: a is not re-emitted" "$out" "a: pass"
assert_not_contains "a malformed baseline: b is not re-emitted" "$out" "b: pass"

printf 'b: pass\n' >"$TEST_TMPDIR/handmade"
out=$(run_poll --baseline "$TEST_TMPDIR/handmade")
assert_contains "a hand-written baseline without the marker is refused" "$out" "BASELINE-UNREADABLE"
assert_not_contains "a hand-written baseline: a is not emitted" "$out" "a: pass"

rm -f "$TEST_TMPDIR/failed-snap"
out=$(STUB_FAIL_CHECKS=1 run_poll --snapshot "$TEST_TMPDIR/failed-snap")
assert_exit "snapshot run with a failed checks read exits non-zero" 1 "$?"
assert_contains "snapshot run with a failed checks read says so" "$out" "SNAPSHOT-FAILED"
[[ -e "$TEST_TMPDIR/failed-snap" ]] && snap_written=yes || snap_written=no
assert_eq "snapshot run with a failed checks read writes no file" "no" "$snap_written"

TRI="$TEST_TMPDIR/triangular"
git init -q -b feature "$TRI"
git -C "$TRI" remote add origin https://github.com/me/app.git
git -C "$TRI" remote add upstream https://github.com/acme/app.git
fork=$(PATH="$STUB_DIR:$PATH" bash "$SCRIPT_DIR/target-repo.sh" --dir "$TRI" 2>/dev/null)
assert_eq "triangular flow: target-repo.sh resolves the checkout to the fork" "me/app" "$fork"

identity_block() {
  awk -v n="$1" '/^## Resolve PR identity/ { on = 1; next } on && /^## / { exit }
    on && /^```bash/ { if (++i == n) f = 1; next } f && /^```/ { exit } f' "$REF" |
    sed -e "s#<skill-dir>#$SCRIPT_DIR/..#" -e "s#<checkout>#$TRI#" -e 's#<base-owner>/<repo>#acme/app#'
  # shellcheck disable=SC2016 # expands in the generated script
  echo 'echo "PR_NUMBER=$PR_NUMBER OWNER=$OWNER REPO=$REPO"'
}
identity_block 2 >"$TEST_TMPDIR/identity-triangular.sh"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$TEST_TMPDIR/identity-triangular.sh" 2>&1)
assert_exit "triangular identity block: exits 0" 0 "$?"
assert_contains "triangular identity block: finds the PR by its fork-namespaced head on the base" "$out" \
  "PR_NUMBER=17 OWNER=acme REPO=app"
identity_block 1 >"$TEST_TMPDIR/identity-plain.sh"
out=$(cd "$OUTSIDE" && PATH="$STUB_DIR:$PATH" bash "$TEST_TMPDIR/identity-plain.sh" 2>&1)
assert_exit "plain identity block on a triangular checkout: an empty PR_NUMBER stops it" 1 "$?"
assert_not_contains "plain identity block on a triangular checkout: no identity is printed" "$out" "PR_NUMBER="

BASE_LINE=$(identity_block 2 | grep '^OWNER_REPO=')
assert_eq "triangular flow: the reference names the base repository explicitly" \
  'OWNER_REPO="acme/app"   # the PR'"'"'s target, not the push destination' "$BASE_LINE"
out=$(TEST_CHECKOUT="$TRI" run_poll --repo acme/app)
assert_exit "triangular flow with the base named: the watch runs to the merge and exits 0" 0 "$?"
assert_contains "triangular flow with the base named: the watch completes" "$out" "PR #5 MERGED — watch complete"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
