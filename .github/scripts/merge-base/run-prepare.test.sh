#!/usr/bin/env bash
# Tests for run-prepare.sh with a stand-in prepare.sh that prints what each
# case names, so every output rule is checked without a merge; prepare.sh's
# own tests cover the merge.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SCRIPT_DIR/run-prepare.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0
ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}
sha() {
  local s
  s=$(sha256sum <"$1")
  printf '%s' "${s%% *}"
}

H64=$(printf 'a%.0s' {1..64})
T0=$(printf 'b%.0s' {1..40})
BIN="$TMP/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/resolve-version-bump-conflict.sh"

# run <prepare-output> [env assignments...]: runs the step with a prepare.sh
# that prints <prepare-output>; sets RC, OUTPUT (GITHUB_OUTPUT) and LOG.
run() {
  printf '#!/usr/bin/env bash\nprintf %%s %q\n' "$1" >"$BIN/prepare.sh"
  shift
  : >"$TMP/output"
  local prepare_sum bump_sum
  prepare_sum=$(sha "$BIN/prepare.sh")
  bump_sum=$(sha "$BIN/resolve-version-bump-conflict.sh")
  RC=0
  LOG=$(env BIN="$BIN" OUT="$TMP/out" PREPARE_SHA256="$prepare_sum" BUMP_SHA256="$bump_sum" \
    HEAD_SHA=h BASE_SHA=b GITHUB_OUTPUT="$TMP/output" "$@" bash "$RUN" 2>&1) || RC=$?
  OUTPUT=$(cat "$TMP/output")
}
out() { sed -n "s/^$1=//p" <<<"$OUTPUT"; }
HASHES="config-sha256=$H64
attributes-sha256=absent
snapshot-sha256=$H64"
CONFLICTED="$HASHES
merge-state=conflicted
escalation-reason=
conflict-tree=$T0"

run "$CONFLICTED"
check 'a conflicted merge passes' 0 "$RC"
check 'its outputs' "conflicted||$T0|$H64|absent" "$(out merge-state)|$(out escalation-reason)|$(out conflict-tree)|$(out config-sha256)|$(out attributes-sha256)"
check 'no skip reason' '' "$(out skip-reason)"
if [[ $LOG == *'::stop-commands::'* ]]; then ok 'workflow commands stop while prepare.sh runs'; else not_ok 'workflow commands stop while prepare.sh runs'; fi

run "$HASHES
merge-state=escalate
escalation-reason=repeat-cap
conflict-tree="
check 'an escalation passes with awaiting-human' 0/escalate/repeat-cap/awaiting-human "$RC/$(out merge-state)/$(out escalation-reason)/$(out skip-reason)"

run "$CONFLICTED" EXPECT_STATE=conflicted EXPECT_TREE="$T0"
check 'the expected state and tree pass' 0 "$RC"
for expect in "EXPECT_STATE=conflicted EXPECT_TREE=$(printf 'c%.0s' {1..40})" "EXPECT_STATE=clean EXPECT_TREE=$T0" "EXPECT_STATE=conflicted EXPECT_TREE="; do
  # shellcheck disable=SC2086  # two assignments, split on purpose
  run "$CONFLICTED" $expect
  check "another state or tree fails ($expect)" 1/ "$RC/$OUTPUT"
done

for bad in "$CONFLICTED
extra=1" "$HASHES
merge-state=conflicted
escalation-reason=
conflict-tree=" "$HASHES
merge-state=escalate
escalation-reason=repeat-cap
conflict-tree=$T0" "$HASHES
merge-state=clean
escalation-reason=repeat-cap
conflict-tree=$T0" "config-sha256=x
merge-state=clean
escalation-reason=
conflict-tree=$T0" "$CONFLICTED
merge-state=clean"; do
  run "$bad"
  check "malformed output fails: $(tr '\n' ' ' <<<"$bad" | cut -c1-60)..." 1/ "$RC/$OUTPUT"
done

run "$CONFLICTED"
printf 'tampered\n' >>"$BIN/prepare.sh"
RC=0
env BIN="$BIN" OUT="$TMP/out" PREPARE_SHA256="$(printf '0%.0s' {1..64})" BUMP_SHA256=x HEAD_SHA=h BASE_SHA=b GITHUB_OUTPUT="$TMP/output" bash "$RUN" >/dev/null 2>&1 || RC=$?
check 'a copy that does not match its SHA-256 fails' 1 "$RC"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/prepare.sh"
: >"$TMP/output"
prepare_sum=$(sha "$BIN/prepare.sh")
bump_sum=$(sha "$BIN/resolve-version-bump-conflict.sh")
RC=0
env BIN="$BIN" OUT="$TMP/out" PREPARE_SHA256="$prepare_sum" BUMP_SHA256="$bump_sum" HEAD_SHA=h BASE_SHA=b GITHUB_OUTPUT="$TMP/output" bash "$RUN" >/dev/null 2>&1 || RC=$?
check 'a prepare.sh failure fails with no output' 1/ "$RC/$(cat "$TMP/output")"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all run-prepare.sh tests passed'
