#!/usr/bin/env bash
# shellcheck disable=SC2319 # check reads the status of the condition on the line above it
# Cases for scripts/check-changed-links-online.sh against a throwaway repository
# and a stub lychee. The stub's --dump prints a fixed list standing in for
# lychee's extraction (which skips code spans and fenced blocks); the cases
# check which of those links the script keeps, what it hands the online run,
# and how it maps lychee's exit codes onto the check-script contract.
# test-scope: scripts/check-changed-links-online.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG RUNNER_TEMP
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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

standards="$TMP_ROOT/standards"
mkdir -p "$standards" "$TMP_ROOT/bin"
: >"$standards/lychee.toml"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMPDIR/gh-calls"
printf 'from = "api"\n'
EOF
chmod +x "$TMP_ROOT/bin/gh"

run() {
  local envs=()
  while [[ $1 != -- ]]; do envs+=("$1"); shift; done
  shift
  (cd "$repo" && env PATH="$TMP_ROOT/bin:$PATH" LYCHEE="$stub" STUB_DUMP="$dump" STANDARDS_DIR="$standards" "${envs[@]}" bash "$SCRIPT" "$@")
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
grep -qx -- '--config' "$TMP_ROOT/args" && grep -qx "$standards/lychee.toml" "$TMP_ROOT/args" && ! grep -qx -- '--offline' "$TMP_ROOT/args"
check $? "the online run reads standards' lychee.toml with the network on" "$(cat "$TMP_ROOT/args")"
[[ "$(cat "$TMP_ROOT/input")" == $'<https://host.test/>\n<https://new.test/page#section>\n<https://wiki.test/Rule_(programming)>' ]]
check $? "the online run's input is the kept links as autolinks" "$(cat "$TMP_ROOT/input")"

out="$(run STUB_EXIT=2 'STUB_REPORT=[ERROR] https://new.test/page#section | Cannot find fragment' -- "$base" 2>"$TMP_ROOT/err")"
rc=$?
[[ $rc -eq 1 && -z $out ]] && grep -q 'Cannot find fragment' "$TMP_ROOT/err"
check $? "a broken link exits 1 with the finding on stderr only" "rc=$rc out=$out err=$(cat "$TMP_ROOT/err")"
grep -qE '^::error file=docs/a\.md,line=[0-9]+::broken link https://new\.test/page#section: Cannot find fragment$' "$TMP_ROOT/err"
check $? "a broken link is annotated at the changed file and line that hold it" "$(cat "$TMP_ROOT/err")"
grep -q '1 of 3 added or changed external link(s) broken' < <(tail -n 1 "$TMP_ROOT/err")
check $? "a broken-link run ends with a count the aggregator's last lines show" "$(tail -n 2 "$TMP_ROOT/err")"

out="$(run STUB_EXIT=2 'STUB_REPORT=[ERROR] https://host.test/ | Network error' -- "$base" 2>"$TMP_ROOT/err")"
rc=$?
grep -qx '::error::broken link https://host.test/: Network error' "$TMP_ROOT/err" && grep -q '1 of 3 added or changed external link(s) broken' < <(tail -n 1 "$TMP_ROOT/err")
check $? "a broken URL no changed file holds verbatim gets a file-less annotation and the count" "rc=$rc err=$(cat "$TMP_ROOT/err")"
lychee_0_24_2_report=$'[/tmp/x.md]:\n[404] https://new.test/page#section (at 2:2) | Rejected status code: 404 Not Found\n[TIMEOUT] https://wiki.test/Rule_(programming) (at 3:2) | Request timed out\n[404] https://new.test/page#section (at 2:2) | Rejected status code: 404 Not Found'
out="$(run STUB_EXIT=2 "STUB_REPORT=$lychee_0_24_2_report" -- "$base" 2>"$TMP_ROOT/err")"
grep -qE '^::error file=docs/a\.md,line=[0-9]+::broken link https://new\.test/page#section: Rejected status code: 404 Not Found$' "$TMP_ROOT/err" &&
  grep -qE '^::error file=docs/a\.md,line=[0-9]+::broken link https://wiki\.test/Rule_\(programming\): Request timed out$' "$TMP_ROOT/err"
check $? "a status-code or TIMEOUT failure is annotated at its changed file and line, its location stripped" "$(cat "$TMP_ROOT/err")"
grep -q '2 of 3 added or changed external link(s) broken' < <(tail -n 1 "$TMP_ROOT/err")
check $? "a URL lychee lists twice counts once" "$(tail -n 2 "$TMP_ROOT/err")"

out="$(run STUB_EXIT=2 'STUB_REPORT=something lychee never printed before' -- "$base" 2>"$TMP_ROOT/err")"
rc=$?
[[ $rc -eq 1 ]] && grep -q 'in a form this script does not parse' < <(tail -n 1 "$TMP_ROOT/err") && ! grep -q '0 of' "$TMP_ROOT/err"
check $? "a failing run with no parsable finding says so instead of counting 0 broken" "rc=$rc err=$(cat "$TMP_ROOT/err")"

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

# A file moved and edited in one change is a rename to git; its new path still
# goes to lychee --dump, and only its added line counts.
moved_base="$(g rev-parse HEAD)"
mkdir -p "$repo/docs/guide"
g mv docs/a.md docs/guide/a.md
printf 'Moved [x](https://moved.test/m#f).\n' >>"$repo/docs/guide/a.md"
g commit -q -am move
out="$(run STUB_DUMP=$'https://kept.test/a\nhttps://moved.test/m#f' -- --list "$moved_base")"
grep -qx 'docs/guide/a.md' "$TMP_ROOT/dump-args" && [[ $out == 'https://moved.test/m#f' ]]
check $? "a moved and edited file's added link is kept" "out=$out args=$(cat "$TMP_ROOT/dump-args")"

g branch -f trunk
printf 'Own [adr](https://github.com/o/r/blob/trunk/docs/guide/a.md#x), [gone](https://github.com/o/r/blob/trunk/docs/gone.md).\n' >>"$repo/docs/guide/a.md"
g commit -q -am self
dump=$'https://github.com/o/r/blob/trunk/docs/guide/a.md#x\nhttps://github.com/o/r/blob/trunk/docs/gone.md'
out="$(run SELF_REPO=o/r STUB_DUMP="$dump" -- --list trunk)"
[[ $out == 'https://github.com/o/r/blob/trunk/docs/gone.md' ]]
check $? "a base-branch link to a file present at HEAD is skipped; a missing one is kept" "out=$out"
out="$(run SELF_REPO=other/r STUB_DUMP="$dump" -- --list trunk)"
[[ $out == "$(LC_ALL=C sort <<<"$dump")" ]]
check $? "a link to another repository is kept" "out=$out"

configs() { grep -x -A1 -- '--config' "$TMP_ROOT/dump-args" | grep -vx -- '--config' | grep -vx -- '--'; }

run -- --list "$base" >/dev/null
[[ "$(configs)" == "$standards/lychee.toml" ]]
check $? "with no lychee.toml here, the standards checkout's is the only config" "$(configs)"
: >"$repo/lychee.toml"
run -- --list "$base" >/dev/null
[[ "$(configs)" == "$standards/lychee.toml"$'\n'lychee.toml ]]
check $? "this repository's own lychee.toml is layered after the standards checkout's" "$(configs)"
run LYCHEE_CONFIG=own.toml -- --list "$base" >/dev/null
[[ "$(configs)" == own.toml ]]
check $? "LYCHEE_CONFIG is a complete override, read alone" "$(configs)"
rm "$repo/lychee.toml"

out="$(run STANDARDS_DIR="$TMP_ROOT/no-standards" -- --list "$base" 2>&1)"
rc=$?
[[ $rc -eq 2 && $out == *"has no lychee.toml"* ]]
check $? "a standards checkout without lychee.toml exits 2" "rc=$rc out=$out"

mkdir -p "$repo/docs/conventions"
printf 'standards_repository: example-org/standards\n' >"$repo/docs/conventions/source-control.yaml"
rm -f "$TMP_ROOT/gh-calls"
run STANDARDS_DIR= -- --list "$base" >/dev/null
first="$(configs | head -n 1)"
grep -qxE 'api( -i)? -H Accept: application/vnd\.github\.raw repos/example-org/standards/contents/lychee\.toml' "$TMP_ROOT/gh-calls"
check $? "with no standards checkout, standards_repository's lychee.toml is read through the API" "$(cat "$TMP_ROOT/gh-calls" 2>&1)"
[[ "$(configs | wc -l)" -eq 1 && $first == *.toml && $first != "$standards"/* ]]
check $? "the API-read standards file is the config" "$(configs)"
rm "$repo/docs/conventions/source-control.yaml"

rm -f "$TMP_ROOT/gh-calls"
out="$(run STANDARDS_DIR= -- --list "$base" 2>&1)"
rc=$?
[[ $rc -eq 2 && $out == *"no standards_repository"* && ! -e $TMP_ROOT/gh-calls ]]
check $? "no standards checkout and no standards_repository exits 2 without an API read" "rc=$rc out=$out"

test_harness::report
