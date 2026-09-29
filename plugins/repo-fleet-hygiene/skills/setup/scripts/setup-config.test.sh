#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-config.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/proj/.claude/repo-fleet-hygiene.conf"

run() { bash "$SCRIPT" apply --config "$CONF" "$@" 2>&1; }

# apply adds the name and creates the parent directory
out="$(run --extend-skip third_party)"
if [[ $? -eq 0 && "$(git config --file "$CONF" --get-all fleet.skipAppend)" == "third_party" ]]; then
  pass "apply adds the name and creates the config directory"
else
  fail "apply adds the name" "$out"
fi

# second identical run is idempotent
before="$(cat "$CONF")"
out="$(run --extend-skip third_party)"
if [[ $? -eq 0 && "$(cat "$CONF")" == "$before" && "$out" == *"already configured"* ]]; then
  pass "second identical run is idempotent"
else
  fail "second identical run is idempotent" "$out"
fi

# unrelated entries and comments survive
printf '%s\n' '# keep this comment' '[fleet]' '  repo = ../keep-me' '  maxDepth = 4' \
  '[canonical "github.com/o/r"]' '  path = ../canon' >"$CONF"
if run --extend-skip vendored --max-depth 6 >/dev/null && grep -Fq '# keep this comment' "$CONF" &&
  grep -Fq 'repo = ../keep-me' "$CONF" && grep -Fq 'path = ../canon' "$CONF" &&
  [[ "$(git config --file "$CONF" --get fleet.maxDepth)" == "6" ]] &&
  [[ "$(git config --file "$CONF" --get-all fleet.skipAppend)" == "vendored" ]]; then
  pass "unrelated entries and comments survive; maxDepth updated"
else
  fail "unrelated entries and comments survive" "$(cat "$CONF")"
fi

# invalid input exits 2 and leaves the file byte-identical
before="$(cat "$CONF")"
bad_ok=1
backslash=$'\\'
for bad in "" "a/b" "a${backslash}b" ".." "."; do
  out="$(run --extend-skip "$bad")"
  code=$?
  if [[ $code -ne 2 || "$(cat "$CONF")" != "$before" ]]; then
    bad_ok=0
    fail "invalid name '$bad' exits 2 and writes nothing" "code=$code $out"
  fi
done
for args in "--max-depth 0" "--max-depth 13" "--max-depth x" "--root $TMP/missing" "--repo $TMP"; do
  # shellcheck disable=SC2086
  out="$(run $args)"
  code=$?
  if [[ $code -ne 2 || "$(cat "$CONF")" != "$before" ]]; then
    bad_ok=0
    fail "'$args' exits 2 and writes nothing" "code=$code $out"
  fi
done
((bad_ok)) && pass "invalid values exit 2 and leave the file byte-identical"

# symlink target refused
ln -s "$CONF" "$TMP/link.conf" 2>/dev/null
if [[ -L "$TMP/link.conf" ]]; then
  before="$(cat "$CONF")"
  out="$(bash "$SCRIPT" apply --config "$TMP/link.conf" --extend-skip x 2>&1)"
  if [[ $? -eq 2 && "$(cat "$CONF")" == "$before" ]]; then
    pass "symlink target is refused"
  else
    fail "symlink target is refused" "$out"
  fi
else
  printf 'SKIP: symlink target: ln -s unavailable\n'
fi

# --skip and --extend-skip write different keys; --skip usage text says REPLACES
rm -f "$CONF"
out="$(run --skip only --extend-skip more)"
usage_text="$(bash "$SCRIPT" 2>&1)"
if [[ "$(git config --file "$CONF" --get-all fleet.skip)" == "only" &&
  "$(git config --file "$CONF" --get-all fleet.skipAppend)" == "more" &&
  "$out" == *REPLACES* && "$usage_text" == *REPLACES* ]]; then
  pass "--skip writes fleet.skip, --extend-skip writes fleet.skipAppend, replace semantics stated"
else
  fail "--skip vs --extend-skip keys" "$out"
fi

# roots and repos are written relative to the config directory and deduplicated
mkdir -p "$TMP/proj/fleet"
git -C "$TMP" init -q -b main "$TMP/proj/repo1"
run --root "$TMP/proj/fleet" --repo "$TMP/proj/repo1" >/dev/null
run --root "$TMP/proj/fleet" --repo "$TMP/proj/repo1" >/dev/null
if [[ "$(git config --file "$CONF" --get-all fleet.root | wc -l)" -eq 1 &&
  "$(git config --file "$CONF" --get-all fleet.repo | wc -l)" -eq 1 ]]; then
  pass "root and repo entries are written once"
else
  fail "root and repo entries are written once" "$(cat "$CONF")"
fi

# no arguments is an error, not a silent empty write
out="$(run)"
if [[ $? -eq 2 ]]; then
  pass "apply with nothing to write exits 2"
else
  fail "apply with nothing to write exits 2" "$out"
fi

if [[ $FAILED -ne 0 ]]; then
  printf '%s test(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'All setup-config tests passed.\n'
