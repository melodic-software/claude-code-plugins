#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scope-resolve.sh
source "$SCRIPT_DIR/scope-resolve.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/empty" "$TMP/named"
git -C "$TMP" init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.email t@t.t
git -C "$TMP/repo" config user.name t
git -C "$TMP/repo" config commit.gpgsign false

out="$(SCOPE_CWD="$TMP/empty" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
code=$?
if [[ "$code" -eq 3 && -z "$out" ]]; then
  pass "no rung exits 3"
else
  fail "no rung exits 3" "code=$code out=$out"
fi

out="$(SCOPE_CWD="$TMP/empty" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback "$TMP/named")"
if [[ "$?" -eq 0 && "$out" == *"repo"*"$TMP/named"* && "$out" == *provenance$'\t'named* ]]; then
  pass "named path wins"
else
  fail "named path wins" "$out"
fi

# ghq root prints the root. The stub ignores args and prints one root.
cat >"$TMP/ghq" <<EOF
#!/bin/sh
printf '%s\n' '$TMP/ghq-root'
EOF
mkdir -p "$TMP/ghq-root"
chmod +x "$TMP/ghq"
out="$(SCOPE_CWD="$TMP/empty" REPO_FLEET_GHQ_BIN="$TMP/ghq" scope_resolve_fallback)"
if [[ "$out" == *"root"*"$TMP/ghq-root"* && "$out" == *provenance$'\t'ghq* ]]; then
  pass "ghq root is the next rung"
else
  fail "ghq root is the next rung" "$out"
fi

out="$(SCOPE_CWD="$TMP/repo" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
if [[ "$out" == *"repo"*"$TMP/repo"* && "$out" == *provenance$'\t'cwd* ]]; then
  pass "cwd git checkout is the last rung"
else
  fail "cwd git checkout is the last rung" "$out"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
exit 1
