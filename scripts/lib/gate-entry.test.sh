#!/usr/bin/env bash
# Gate-entry protocol.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-harness.sh
source "$SCRIPT_DIR/test-harness.sh"
# shellcheck source=gate-entry.sh
source "$SCRIPT_DIR/gate-entry.sh"

REPO="$(mktemp -d)"
trap 'rm -rf "$REPO"' EXIT
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name Test
printf 'x\n' >"$REPO/f"
git -C "$REPO" add f
git -C "$REPO" commit -q -m init

mode="$(cd "$REPO" && gate_entry::begin --all && printf '%s' "$GATE_ENTRY_MODE")"
if [[ "$mode" == "all" ]]; then pass "all mode ignores refs"; else bad "all mode ignores refs" "$mode"; fi

NOGIT="$(mktemp -d)"
printf '#!/bin/sh\nexit 127\n' >"$NOGIT/git"
chmod +x "$NOGIT/git"
mode="$(PATH="$NOGIT:/usr/bin:/bin" bash -c 'source "$1"; gate_entry::begin --paths; printf %s "$GATE_ENTRY_MODE"' bash "$SCRIPT_DIR/gate-entry.sh")"
if [[ "$mode" == "paths" ]]; then pass "paths mode does not consult a ref"; else bad "paths mode does not consult a ref" "$mode"; fi

mode="$(cd "$REPO" && gate_entry::begin HEAD && printf '%s' "$GATE_ENTRY_MODE")"
if [[ "$mode" == "ref" ]]; then pass "a resolvable ref sets mode ref"; else bad "a resolvable ref sets mode ref" "$mode"; fi

bad_out="$(bash -c 'cd "$1" && source "$2" && gate_entry::begin definitely-not-a-ref' bash "$REPO" "$SCRIPT_DIR/gate-entry.sh" 2>&1)"
bad_rc=$?
if [[ "$bad_rc" -eq 2 ]]; then pass "unresolvable ref exits 2"; else bad "unresolvable ref exits 2" "exit $bad_rc"; fi
case "$bad_out" in
*"not resolvable"*) pass "unresolvable ref names itself" ;;
*) bad "unresolvable ref names itself" "$bad_out" ;;
esac

swallow="$REPO/swallow.sh"
cat >"$swallow" <<EOF
#!/usr/bin/env bash
set -uo pipefail
source "$SCRIPT_DIR/gate-entry.sh"
mapfile -t rows < <(gate_entry::begin 'definitely-not-a-ref'; printf 'listed\n')
echo survived
EOF
chmod +x "$swallow"
sw_out="$(bash "$swallow" 2>&1)"
sw_rc=$?
if [[ "$sw_rc" -eq 2 ]]; then pass "subshell cannot swallow a fatal base ref"; else bad "subshell cannot swallow a fatal base ref" "exit $sw_rc out=$sw_out"; fi
case "$sw_out" in
*survived*) bad "fatal base ref does not become an empty list" "$sw_out" ;;
*) pass "fatal base ref does not become an empty list" ;;
esac

empty_rc=0
( cd "$REPO" && gate_entry::begin --all ) || empty_rc=$?
if [[ "$empty_rc" -eq 0 ]]; then pass "an empty-capable mode is not a failed discovery"; else bad "an empty-capable mode is not a failed discovery" "exit $empty_rc"; fi

hits="$(grep -RIn --include='check-*.sh' 'rev-parse --verify --quiet' "$SCRIPT_DIR/.." || true)"
hits="$(printf '%s\n' "$hits" | grep -F '^{commit}' || true)"
if [[ -z "${hits//[[:space:]]/}" ]]; then
  pass "no gate hand-rolls the commit predicate"
else
  bad "no gate hand-rolls the commit predicate" "$hits"
fi

test_harness::report
