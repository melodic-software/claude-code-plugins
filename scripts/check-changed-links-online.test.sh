#!/usr/bin/env bash
# shellcheck disable=SC2319 # check reads the status of the condition on the line above it
# Cases for scripts/check-changed-links-online.sh against a throwaway repository
# and a stub lychee. The stub's --dump prints a fixed list standing in for
# lychee's extraction (which skips code spans and fenced blocks); the cases
# check which of those links the script keeps, what it hands the online run,
# and how it maps lychee's exit codes onto the check-script contract.
# test-scope: scripts/check-changed-links-online.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-changed-links-online.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
export TMPDIR="$TMP_ROOT"

repo="$TMP_ROOT/repo"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid "$@"; }

mkdir -p "$repo/docs" "$repo/scripts/fixtures"
printf 'Kept: <https://kept.test/a>\nGone: <https://gone.test/b>\n' >"$repo/docs/a.md"
g add -A
g commit -q -m base
base="$(g rev-parse HEAD)"

cat >"$repo/docs/a.md" <<'EOF'
Kept: <https://kept.test/a>
New [link](https://new.test/page#section) and `https://span.test/c`.
See [rule](https://wiki.test/Rule_(programming)) and <https://host.test>.
EOF
printf 'See https://txt.test/c\n' >"$repo/docs/b.txt"
printf '| a | <https://fixture.test/f> |\n' >"$repo/scripts/fixtures/hooks-lifecycle-table.md"
g add -A
g commit -q -m change

# The stub: --dump prints STUB_DUMP and records the files it was given; any
# other run records its arguments and input, prints STUB_REPORT and exits
# STUB_EXIT.
stub="$TMP_ROOT/lychee"
cat >"$stub" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --dump "* ]]; then
  printf '%s\n' "$@" >"$TMPDIR/dump-args"
  printf '%s\n' "${STUB_DUMP:-}"
  exit 0
fi
printf '%s\n' "$@" >"$TMPDIR/args"
cat "${@: -1}" >"$TMPDIR/input"
printf '%s\n' "${STUB_REPORT:-}"
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$stub"

# What lychee's parser would extract from docs/a.md at head: no code span URL.
dump=$'https://kept.test/a\nhttps://new.test/page#section\nhttps://wiki.test/Rule_(programming)\nhttps://host.test/\nhttps://fixture.test/f'

# run [VAR=value ...] -- <script args>: the script in the repo with the stub.
run() {
  local envs=()
  while [[ $1 != -- ]]; do envs+=("$1"); shift; done
  shift
  (cd "$repo" && env LYCHEE="$stub" STUB_DUMP="$dump" "${envs[@]}" bash "$SCRIPT" "$@")
}
check() { if [[ $1 == 0 ]]; then pass "$2"; else bad "$2" "${3:-}"; fi; }

out="$(run -- --list "$base")"
want=$'https://host.test/\nhttps://new.test/page#section\nhttps://wiki.test/Rule_(programming)'
[[ $out == "$want" ]]
check $? "--list keeps extracted links that are on an added line" "want: $want; got: $out"
[[ $out != *kept.test* ]]
check $? "an extracted link only on an unchanged line is dropped" "$out"
[[ $out != *span.test* ]]
check $? "a URL lychee does not extract (a code span) is not checked" "$out"
grep -qx 'docs/a.md' "$TMP_ROOT/dump-args" && ! grep -qE 'b\.txt|hooks-lifecycle' "$TMP_ROOT/dump-args"
check $? "only changed markdown outside the fixtures goes to lychee --dump" "$(cat "$TMP_ROOT/dump-args")"

out="$(run -- "$base" 2>"$TMP_ROOT/err")"
check $? "a clean online run exits 0" "$out $(cat "$TMP_ROOT/err")"
[[ $out == *"3 added or changed external link(s) resolve"* ]]
check $? "a clean run states its result on stdout" "$out"
grep -qx -- '--config' "$TMP_ROOT/args" && grep -qx 'lychee.toml' "$TMP_ROOT/args" && ! grep -qx -- '--offline' "$TMP_ROOT/args"
check $? "the online run reads lychee.toml with the network on" "$(cat "$TMP_ROOT/args")"
[[ "$(cat "$TMP_ROOT/input")" == $'<https://host.test/>\n<https://new.test/page#section>\n<https://wiki.test/Rule_(programming)>' ]]
check $? "the online run's input is the kept links as autolinks" "$(cat "$TMP_ROOT/input")"

out="$(run STUB_EXIT=2 'STUB_REPORT=[ERROR] https://new.test/page#section | Cannot find fragment' -- "$base" 2>"$TMP_ROOT/err")"
rc=$?
[[ $rc -eq 1 && -z $out ]] && grep -q 'Cannot find fragment' "$TMP_ROOT/err"
check $? "a broken link exits 1 with the finding on stderr only" "rc=$rc out=$out err=$(cat "$TMP_ROOT/err")"

run STUB_EXIT=3 -- "$base" >/dev/null 2>&1
rc=$?
[[ $rc -eq 2 ]]
check $? "a lychee error other than link failures exits 2" "rc=$rc"

out="$(run LYCHEE="$TMP_ROOT/missing" -- "$base" 2>"$TMP_ROOT/err")"
rc=$?
[[ $rc -eq 2 && -z $out && -s $TMP_ROOT/err ]]
check $? "a missing lychee exits 2 with a diagnostic on stderr only" "rc=$rc out=$out"

out="$(run -- no-such-ref 2>/dev/null)"
rc=$?
[[ $rc -eq 2 ]]
check $? "a base ref git cannot resolve exits 2" "rc=$rc out=$out"

rm -f "$TMP_ROOT/args"
out="$(run -- "$(g rev-parse HEAD)")"
rc=$?
[[ $rc -eq 0 && ! -e $TMP_ROOT/args && $out == *"no external links"* ]]
check $? "no changed markdown exits 0 without an online run" "rc=$rc out=$out"

run -- >/dev/null 2>&1
[[ $? -eq 2 ]]
check $? "a missing base ref is a usage error (exit 2)"

test_harness::report
