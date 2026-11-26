#!/usr/bin/env bash
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

T0=$(printf 'b%.0s' {1..40})
BIN="$TMP/bin"
mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/resolve-version-bump-conflict.sh"

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
CONFLICTED="merge-state=conflicted
escalation-reason=
conflict-tree=$T0"

run "$CONFLICTED"
check 'a conflicted merge passes' 0 "$RC"
check 'its outputs' "conflicted||$T0" "$(out merge-state)|$(out escalation-reason)|$(out conflict-tree)"
check 'no skip reason' '' "$(out skip-reason)"
if [[ $LOG == *'::stop-commands::'* ]]; then ok 'workflow commands stop while prepare.sh runs'; else not_ok 'workflow commands stop while prepare.sh runs'; fi

check 'no unmerged-paths file gives no conflict paths' '' "$(out conflict-paths)"

mkdir -p "$TMP/out"
printf 'docs/contract.md\0src/a b.mjs\0' >"$TMP/out/unmerged-paths"
run "$CONFLICTED"
check 'the unmerged paths are one JSON array line' '["docs/contract.md","src/a b.mjs"]' "$(out conflict-paths)"
printf 'a\nb.md\0' >"$TMP/out/unmerged-paths"
run "$CONFLICTED"
check 'a newline in a path stays inside the one line' '["a\nb.md"]' "$(out conflict-paths)"
head -c 20000 /dev/zero | tr '\0' x >"$TMP/out/unmerged-paths"
run "$CONFLICTED"
check 'paths past 16,384 characters give none' 0/ "$RC/$(out conflict-paths)"
printf 'bad\xffname\0' >"$TMP/out/unmerged-paths"
run "$CONFLICTED"
check 'a path that is not UTF-8 gives none' 0/ "$RC/$(out conflict-paths)"
rm -f "$TMP/out/unmerged-paths"

run "merge-state=escalate
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
extra=1" "merge-state=conflicted
escalation-reason=
conflict-tree=" "merge-state=escalate
escalation-reason=repeat-cap
conflict-tree=$T0" "merge-state=clean
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
