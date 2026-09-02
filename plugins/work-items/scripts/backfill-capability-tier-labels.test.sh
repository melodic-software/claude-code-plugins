#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKFILL="$SCRIPT_DIR/backfill-capability-tier-labels.sh"
LIB_TEST="$SCRIPT_DIR/lib/legacy-frontier-tier-signal.test.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

chmod +x "$BACKFILL" "$LIB_TEST"

if bash "$LIB_TEST"; then
  pass "legacy signal unit tests"
else
  fail "legacy signal unit tests"
fi

# Offline: apply without gh should fail clearly.
if "$BACKFILL" apply --dry-run 2>/dev/null; then
  fail "apply without gh should not succeed"
else
  pass "apply without gh exits non-zero"
fi

# Empty repo_args under set -u must not abort (bash 4.0-4.3 unbound-variable).
# check and apply both expand repo_args=() when --repo is omitted; a stub gh
# lets the expansion run instead of dying at require_gh.
STUB_BIN="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN"' EXIT
cat >"$STUB_BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
  printf '%s\n' '[]'
  exit 0
fi
if [[ "$1" == "label" && "$2" == "list" ]]; then
  printf '%s\n' '[{"name":"capability-tier: frontier"}]'
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 1
EOF
chmod +x "$STUB_BIN/gh"

out="$(PATH="$STUB_BIN:$PATH" "$BACKFILL" check 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" != *"unbound variable"* ]]; then
  pass "check without --repo expands empty repo_args without aborting"
else
  fail "check without --repo must not abort on empty repo_args: rc=$rc out=$out"
fi

out="$(PATH="$STUB_BIN:$PATH" "$BACKFILL" apply --dry-run --yes 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" != *"unbound variable"* && "$out" == *"No legacy frontier-tier body stamps need backfill."* ]]; then
  pass "apply without --repo expands empty repo_args without aborting"
else
  fail "apply without --repo must not abort on empty repo_args: rc=$rc out=$out"
fi

out="$(PATH="$STUB_BIN:$PATH" "$BACKFILL" check --repo owner/repo 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" != *"unbound variable"* ]]; then
  pass "check with --repo still expands a populated repo_args"
else
  fail "check with --repo must still succeed: rc=$rc out=$out"
fi

if [[ "$FAILED" -eq 0 ]]; then
  exit 0
fi
exit 1
