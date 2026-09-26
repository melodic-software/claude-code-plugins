#!/usr/bin/env bash
# Tests for tick.sh: a stub gh on PATH keeps the PR body in a temp file, so each edit is
# read back the way the real round trip would.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tick.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
"pr view --json body") jq -n --rawfile b "$GH_BODY" '{body: $b}' ;;
"pr edit --body-file -") if [[ -n ${GH_DROP-} ]]; then cat >/dev/null; else cat >"$GH_BODY"; fi ;;
*) printf 'gh stub: unexpected: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

body() { # <two-line> <three-line>: a CRLF body with no final newline, as GitHub returns it
  printf '%s\r\n' 'No related issue: sweep' '## Summary' '<!-- repo-sweep:begin playbook=fixture -->' \
    '- [x] one: p:a@1.0, committed abc1234' '- [ ] two-b: p:z' "$1" "$2" '<!-- repo-sweep:end -->' '' \
    'Not run:'
  printf '%s' '- [ ] four: p:q'
}
body '- [ ] two: p:b, p:c' '- [x] three: p:d' >"$TMP/body"
run() { # sets out, rc
  out=$(PATH="$TMP/bin:$PATH" GH_BODY="$TMP/body" bash "$SCRIPT" "$@" 2>"$TMP/err")
  rc=$?
}

run two in-progress
assert_eq "in-progress: exit 0, prints the new line" "0 - [~] two: p:b, p:c" "$rc $out"
body '- [~] two: p:b, p:c' '- [x] three: p:d' >"$TMP/want"
if cmp -s "$TMP/want" "$TMP/body"; then pass "in-progress: only that line changed, CRLF and other bytes kept"; else
  fail "in-progress: body bytes" "$(od -c "$TMP/want" | tail -3)" "$(od -c "$TMP/body" | tail -3)"
fi

run two in-progress
assert_eq "in-progress again (resume): exit 0" "0" "$rc"

run two committed abc1234 p:b@1.0 p:c@2.0
assert_eq "committed: exit 0" "0 - [x] two: p:b@1.0, p:c@2.0, committed abc1234" "$rc $out"
run three no-findings p:d@1
assert_eq "no-findings on a bare web-UI [x]" "0 - [x] three: p:d@1, no findings" "$rc $out"
body '- [x] two: p:b@1.0, p:c@2.0, committed abc1234' '- [x] three: p:d@1, no findings' >"$TMP/want"
if cmp -s "$TMP/want" "$TMP/body"; then pass "committed and no-findings: body bytes as expected"; else
  fail "done lines: body bytes" "$(cat "$TMP/want")" "$(cat "$TMP/body")"
fi

cp "$TMP/body" "$TMP/before"
run two committed abc1234 p:b@1.0
assert_eq "already done: exit 1" "1" "$rc"
run nope in-progress
assert_eq "missing id: exit 1" "1" "$rc"
run four in-progress
assert_eq "id only outside the markers: exit 1" "1" "$rc"
if cmp -s "$TMP/before" "$TMP/body"; then pass "failed ticks leave the body alone"; else fail "failed ticks" "unchanged" "changed"; fi

GH_DROP=1 run two-b in-progress
assert_eq "edit that does not land: exit 1" "1" "$rc"
case "$(cat "$TMP/err")" in *"did not land"*) pass "edit that does not land: stderr says so" ;; *) fail "did not land stderr" "*did not land*" "$(cat "$TMP/err")" ;; esac

for bad in "two" "two in-progress p:b@1" "two committed xyz p:b@1" "two committed abc1234" "two no-findings p:b" "two done p:b@1"; do
  read -ra args <<<"$bad"
  run "${args[@]}"
  assert_eq "usage: tick.sh $bad: exit 2" "2" "$rc"
done

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'tick.test.sh: all passed\n'
