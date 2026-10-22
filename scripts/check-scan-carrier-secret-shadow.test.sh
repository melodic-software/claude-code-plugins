#!/usr/bin/env bash
# Black-box test for check-scan-carrier-secret-shadow.sh, with a stub gh on
# PATH: it answers the two secret listings from STUB_* variables and records
# each call. Never reaches the live API. Mutates only its own mktemp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-scan-carrier-secret-shadow.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"

STUB_DIR="$(mktemp -d)"
trap 'rm -rf "${STUB_DIR:?}"' EXIT
cat >"$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
  *"repos/o/r/actions/secrets"*) [[ ${STUB_REPO_STATUS:-0} -eq 0 ]] || exit 1; printf '%b' "${STUB_REPO_NAMES:-}" ;;
  *"orgs/o/actions/secrets"*) [[ ${STUB_ORG_STATUS:-0} -eq 0 ]] || { echo 'HTTP 403' >&2; exit 1; }; printf '%b' "${STUB_ORG_NAMES:-}" ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$STUB_DIR/gh"

# check <label> <expected-rc> <must-name> [VAR=value...]
check() {
  local label=$1 expected=$2 must=$3 out rc
  shift 3
  : >"$STUB_DIR/log"
  out=$(env -i PATH="$STUB_DIR:/usr/bin:/bin" STUB_LOG="$STUB_DIR/log" "$@" bash "$SUT" o/r 2>&1)
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got $rc: $out"
  elif ! grep -qF -- "$must" <<<"$out"; then
    fail "$label: '$must' not in: $out"
  elif grep -qv -- '--jq .secrets\[\].name$' "$STUB_DIR/log"; then
    fail "$label: a gh call read more than secret names: $(cat "$STUB_DIR/log")"
  else
    ok "$label"
  fi
}

check "no shadow anywhere passes" 0 "neither o/r nor organization o" \
  STUB_REPO_NAMES='OTHER\nCLAUDE_API_KEY\n' STUB_ORG_NAMES='ORG_ONE\n'
check "a repository secret of the name fails" 1 "repository o/r has a secret named SCAN_CARRIER_PRIVATE_KEY" \
  STUB_REPO_NAMES='OTHER\nSCAN_CARRIER_PRIVATE_KEY\n'
check "an organization secret of the name fails" 1 "organization o has a secret named SCAN_CARRIER_PRIVATE_KEY" \
  STUB_ORG_NAMES='SCAN_CARRIER_PRIVATE_KEY\n'
check "a name that only contains it is no shadow" 0 "neither" \
  STUB_REPO_NAMES='SCAN_CARRIER_PRIVATE_KEY_OLD\n' STUB_ORG_NAMES='X_SCAN_CARRIER_PRIVATE_KEY\n'
check "a forbidden organization listing degrades to exit 2" 2 "cannot list the secrets of organization o" \
  STUB_ORG_STATUS=1
check "a forbidden organization listing still reports a repository shadow as a hit" 1 "repository o/r has a secret" \
  STUB_ORG_STATUS=1 STUB_REPO_NAMES='SCAN_CARRIER_PRIVATE_KEY\n'
check "an unreadable repository listing exits 2" 2 "cannot list the secrets of o/r" \
  STUB_REPO_STATUS=1

out=$(bash "$SUT" 2>&1)
if [[ $? -eq 2 && $out == usage:* ]]; then ok "no argument is usage, exit 2"; else fail "no argument: $out"; fi
out=$(bash "$SUT" 'o/r;x' 2>&1)
if [[ $? -eq 2 ]]; then ok "a malformed repository is usage, exit 2"; else fail "malformed repository: $out"; fi

test_harness::report
