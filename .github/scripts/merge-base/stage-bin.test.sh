#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGE="$SCRIPT_DIR/stage-bin.sh"

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

mkdir -p "$TMP/src/a" "$TMP/src/b"
printf 'echo one\n' >"$TMP/src/a/one.sh"
printf 'echo two-bump\n' >"$TMP/src/b/two-bump.sh"
ONE_SUM=0cb42bbdf016ecafd6c21ac6c4b1760bf5b346c70c4f96ba890ef3d74883c8c2
TWO_SUM=7fd6d3fdfe0d5ff02ef7373d66a9d9d3c70c855c68e63b559f3edff827747b1e

run_stage() {
  local dir
  dir=$(mktemp -d "$TMP/run.XXXXXX")
  printf '%s' "$1" >"$dir/resolved.json"
  shift
  BIN="$dir/bin"
  : >"$dir/out"
  RC=0
  BIN="$BIN" RESOLVED="$dir/resolved.json" GITHUB_OUTPUT="$dir/out" bash "$STAGE" "$@" >"$dir/stdout" 2>&1 || RC=$?
  OUT=$(cat "$dir/out")
  STDOUT=$(cat "$dir/stdout")
}

echo '# copies and hashes'
run_stage '{"loop":{"no-progress":3}}' "$TMP/src/a/one.sh" "$TMP/src/b/two-bump.sh"
check 'exit 0' 0 "$RC"
check 'one output line per script, then no-progress' "one-sha256=$ONE_SUM
two-bump-sha256=$TWO_SUM
no-progress=3" "$OUT"
check 'the copy keeps the content' 'echo one' "$(cat "$BIN/one.sh")"
check 'a copy is named by its basename' 'echo two-bump' "$(cat "$BIN/two-bump.sh")"
check 'only the named scripts are copied' 'one.sh two-bump.sh' "$(cd "$BIN" && echo *)"

echo '# the hash is of the copy, so a later edit to the source shows'
run_stage '{"loop":{"no-progress":12}}' "$TMP/src/a/one.sh"
printf 'echo changed\n' >"$TMP/src/a/one.sh"
check 'the recorded hash is the content at copy time' "one-sha256=$ONE_SUM" "$(head -1 <<<"$OUT")"
check 'a two-digit no-progress passes' 'no-progress=12' "$(tail -1 <<<"$OUT")"
printf 'echo one\n' >"$TMP/src/a/one.sh"

echo '# loop.no-progress must be a positive integer'
for config in '{}' '{"loop":{}}' '{"loop":{"no-progress":0}}' '{"loop":{"no-progress":-1}}' '{"loop":{"no-progress":"3x"}}' '{"loop":{"no-progress":1.5}}'; do
  run_stage "$config" "$TMP/src/a/one.sh"
  check "config $config fails" 1 "$RC"
  check "config $config writes no no-progress" '' "$(grep '^no-progress=' <<<"$OUT" || true)"
  check "config $config names the cause" '::error::the resolved config holds no loop.no-progress' "$STDOUT"
done

echo '# a missing script fails'
run_stage '{"loop":{"no-progress":3}}' "$TMP/src/a/one.sh" "$TMP/src/missing.sh"
check 'a missing script exits nonzero' 1 "$RC"
check 'no hash is written for it, nor no-progress' "one-sha256=$ONE_SUM" "$OUT"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all stage-bin.sh tests passed'
