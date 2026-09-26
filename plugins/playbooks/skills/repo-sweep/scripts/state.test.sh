#!/usr/bin/env bash
# Tests for state.sh: a stub gh on PATH serves PR JSON, a fixture repo holds the sweep
# branch with Playbook-Step trailers, all in a temp dir.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

mkdir -p "$TMP/bin" "$TMP/gh"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
"pr list --state all --head "*" --limit 1000 "*) cat "$GH_DIR/head.json" ;;
"pr list --state open --search head:chore/repo-sweep- --limit 1000 "*) cat "$GH_DIR/open.json" ;;
*) printf 'gh stub: unexpected: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

gitf() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
repo="$TMP/repo"
sweep=chore/repo-sweep-fixture-20260926
mkdir -p "$repo"
gitf -C "$repo" init --quiet
commit() { gitf -C "$repo" commit --quiet --no-verify --allow-empty -m "$1"; }
step() { # <trailer lines>: a step commit, trailers in one final paragraph
  commit "$(printf 'step\n\nScope decisions:\n- q: a\n\nPlaybook: fixture\n%s\nCo-Authored-By: F <f@example.invalid>\n' "$1")"
  git -C "$repo" log -1 --format=%h
}
mkdir -p "$repo/.work"
printf 'tracked\n' >"$repo/.work/tracked"
gitf -C "$repo" add .work/tracked
commit "$(printf 'prior sweep\n\nPlaybook-Step: p:h@0.9\n')" # before the base: never reconciled
gitf -C "$repo" update-ref refs/remotes/origin/main HEAD
gitf -C "$repo" checkout --quiet -b "$sweep"
commit 'repo-sweep: seed'
sha_two=$(step 'Playbook-Step: p:b@2.0')
sha_four=$(step $'Playbook-Step: p:d@1\nPlaybook-Step: p:e@1')
step $'Playbook-Step: p:f@1\nPlaybook-Step: p:g@1' >/dev/null # superset of step five: no match
assert_eq "fixture trailers parse" "p:f@1 p:g@1" \
  "$(git -C "$repo" log -1 --format='%(trailers:key=Playbook-Step,valueonly,separator=%x20)')"

body() { # <eol> <checklist lines...>
  local eol=$1
  shift
  printf 'No related issue: hygiene sweep%s\n## Summary%s\n<!-- repo-sweep:begin playbook=fixture -->%s\n' "$eol" "$eol" "$eol"
  printf "%s$eol\n" "$@"
  printf '<!-- repo-sweep:end -->%s\n\nNot run:%s\n- tidy: not selected%s\n' "$eol" "$eol" "$eol"
}
pr() { # <state> <body> [<number>] [<branch>]
  jq -n --arg s "$1" --arg b "$2" --argjson n "${3:-7}" --arg h "${4:-$sweep}" \
    '{number: $n, state: $s, headRefName: $h, baseRefName: "main", body: $b}'
}
serve() { jq -s . >"$TMP/gh/$1.json"; }
run() { # sets out, rc
  out=$(cd "${RUN_DIR:-$repo}" && PATH="$TMP/bin:$PATH" GH_DIR="$TMP/gh" GH_LOG="$TMP/gh.log" \
    GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" 2>"$TMP/err")
  rc=$?
}

lines=('- [x] one: p:a@1.0, committed abc1234' '- [ ] two: p:b' '- [x] three: p:c'
  '- [x] four: p:d, p:e' '- [ ] five: p:f' '- [ ] six: p:h')
expected="pr 7
branch $sweep
pr-state OPEN
playbook fixture
dirty no
untick-committed two $sha_two p:b@2.0
done-unverified three
untick-committed four $sha_four p:d@1 p:e@1
next five pending"

pr OPEN "$(body '' "${lines[@]}")" | serve head
run
assert_eq "reconcile: exit 0" "0" "$rc"
assert_eq "reconcile: committed lines, web-UI tick, exact skill sets, base excluded" "$expected" "$out"

pr OPEN "$(body $'\r' "${lines[@]}")" | serve head
RUN_DIR="$repo/.work" run
assert_eq "CRLF body from a subdirectory: same report" "$expected" "$out"

mkdir -p "$repo/.work/scratch"
printf 'y\n' >"$repo/.work/scratch/new"
printf 'changed\n' >"$repo/.work/tracked"
run
assert_eq ".work changes only: not dirty" "0 dirty no" "$rc $(grep '^dirty' <<<"$out")"

printf 'z\n' >"$repo/stray"
run
assert_eq "dirty tree, pending next step: exit 12" "12 dirty yes" "$rc $(grep '^dirty' <<<"$out")"

pr OPEN "$(body '' '- [ ] six: p:h' '- [~] five: p:f' '- [ ] seven: p:q')" | serve head
run
assert_eq "[~] resume: dirty tree is not a stop" "0 next five in-progress" "$rc $(grep '^next' <<<"$out")"
rm -f "$repo/stray"

pr OPEN "$(body '' '- [~] two: p:b' '- [ ] five: p:f')" | serve head
run
assert_eq "[~] line whose commit landed before its tick: reconciled, next moves on" "0 untick-committed two $sha_two p:b@2.0
next five pending" "$rc $(grep -E '^(untick|next)' <<<"$out")"

pr OPEN "$(body '' '- [x] one: p:a@1.0, committed abc1234' '- [X] two: p:b@2.0, no findings')" | serve head
run
assert_eq "all steps done: exit 13, no next line" "13 " "$rc $(grep '^next' <<<"$out")"

{
  pr CLOSED "$(body '' '- [ ] a: p:a')" 9
  pr OPEN "$(body '' '- [ ] a: p:a')" 7
} | serve head
run
assert_eq "open PR beats a newer closed one" "0 pr 7" "$rc $(head -1 <<<"$out")"

pr MERGED "$(body '' '- [ ] a: p:a')" | serve head
run
assert_eq "merged PR: exit 11" "11 pr-state MERGED" "$rc $(grep '^pr-state' <<<"$out")"

serve head </dev/null
run
assert_eq "no PR for the sweep branch: exit 10" "10" "$rc"

pr OPEN 'no markers here' | serve head
run
assert_eq "body without markers: exit 1" "1" "$rc"

rm "$TMP/gh/head.json"
run
assert_eq "gh failing: exit 1" "1" "$rc"

gitf -C "$repo" checkout --quiet -b other
: >"$TMP/gh.log"
{
  pr OPEN x 7
  pr OPEN x 8 fix/chore/repo-sweep-decoy
} | serve open
run
assert_eq "other branch, one open sweep: exit 14 names the branch" "14 pr 7
branch $sweep
pr-state OPEN" "$rc $out"
case "$(cat "$TMP/gh.log")" in
*"--search head:chore/repo-sweep- --limit 1000"*) pass "discovery searches head:chore/repo-sweep- with --limit 1000" ;;
*) fail "discovery gh args" "--search head:chore/repo-sweep- --limit 1000" "$(cat "$TMP/gh.log")" ;;
esac

{
  pr OPEN x 7
  pr OPEN x 9 chore/repo-sweep-fixture-20260927
} | serve open
run
assert_eq "other branch, two open sweeps: exit 15 lists them" "15 sweep 7 $sweep
sweep 9 chore/repo-sweep-fixture-20260927" "$rc $out"

pr OPEN x 8 fix/chore/repo-sweep-decoy | serve open
run
assert_eq "other branch, decoy only: exit 10" "10 " "$rc $out"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'state.test.sh: all passed\n'
