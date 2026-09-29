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

mkdir -p "$TMP/deep/1/2/3/empty" "$TMP/named"; EMPTY="$TMP/deep/1/2/3/empty"
git -C "$TMP" init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.email t@t.t
git -C "$TMP/repo" config user.name t
git -C "$TMP/repo" config commit.gpgsign false

out="$(SCOPE_CWD="$EMPTY" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
code=$?
if [[ "$code" -eq 3 && -z "$out" ]]; then
  pass "no rung exits 3"
else
  fail "no rung exits 3" "code=$code out=$out"
fi

out="$(SCOPE_CWD="$EMPTY" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback "$TMP/named")"
if [[ "$?" -eq 0 && "$out" == *"repo"*"$TMP/named"* && "$out" == *provenance$'\t'named* ]]; then
  pass "named path wins"
else
  fail "named path wins" "$out"
fi

# The stub records its args and prints two roots only for `root --all`.
cat >"$TMP/ghq" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >"$TMP/ghq-args"
[ "\$*" = "root --all" ] || exit 1
printf '%s\n' '$TMP/ghq-root' '$TMP/ghq-root2'
EOF
mkdir -p "$TMP/ghq-root" "$TMP/ghq-root2"
chmod +x "$TMP/ghq"
out="$(SCOPE_CWD="$EMPTY" REPO_FLEET_GHQ_BIN="$TMP/ghq" scope_resolve_fallback)"
if [[ "$out" == *"root"$'\t'"$TMP/ghq-root"$'\n'* && "$out" == *"root"$'\t'"$TMP/ghq-root2"* \
  && "$out" == *provenance$'\t'ghq* && "$(cat "$TMP/ghq-args")" == "root --all" ]]; then
  pass "ghq root --all is the next rung and every root is emitted"
else
  fail "ghq root is the next rung" "$out"
fi

out="$(SCOPE_CWD="$TMP/repo" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
if [[ "$out" == *"repo"*"$TMP/repo"* && "$out" == *provenance$'\t'cwd* ]]; then
  pass "cwd git checkout is the last rung"
else
  fail "cwd git checkout is the last rung" "$out"
fi

# Ancestor rung: parents of a non-repo cwd.
mkfleet() { # dir count
  local i
  for ((i = 1; i <= $2; i++)); do git -C "$1" init -q -b main "$1/r$i"; done
}
mkdir -p "$TMP/a2/work" "$TMP/a1/w1/w2/w3/work" "$TMP/a5/x1/x2/x3/x4/x5"
mkfleet "$TMP/a2" 2
mkfleet "$TMP/a1" 1
mkfleet "$TMP/a5" 2

out="$(SCOPE_CWD="$TMP/a2/work" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
if [[ "$out" == "root"$'\t'"$TMP/a2"$'\n'"provenance"$'\t'"ancestor" ]]; then
  pass "parent holding 2 repos is emitted as ancestor"
else
  fail "parent holding 2 repos is emitted as ancestor" "$out"
fi

out="$(SCOPE_CWD="$TMP/a1/w1/w2/w3/work" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
code=$?
if [[ "$code" -eq 3 && -z "$out" ]]; then
  pass "parent holding 1 repo is not emitted"
else
  fail "parent holding 1 repo is not emitted" "code=$code out=$out"
fi

out="$(SCOPE_CWD="$TMP/a5/x1/x2/x3/x4/x5" REPO_FLEET_GHQ_BIN=/nonexistent scope_resolve_fallback)"
code=$?
if [[ "$code" -eq 3 && -z "$out" ]]; then
  pass "ancestor 5 levels up is not found"
else
  fail "ancestor 5 levels up is not found" "code=$code out=$out"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
exit 1
