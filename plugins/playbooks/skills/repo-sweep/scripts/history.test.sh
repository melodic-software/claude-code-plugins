#!/usr/bin/env bash
# Tests for history.sh: a stub gh on PATH serves merged sweep PRs, a fixture repo holds
# Playbook-Step trailers, and a fixture installed_plugins.json supplies current versions.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/history.sh"
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
"pr list --state merged --search head:chore/repo-sweep- --limit 1000 "*) cat "$GH_DIR/merged.json" ;;
*) printf 'gh stub: unexpected: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

gitf() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
repo="$TMP/repo"
mkdir -p "$repo"
gitf -C "$repo" init --quiet
commit() { gitf -C "$repo" commit --quiet --no-verify --allow-empty -m "$1"; }
trailers() { printf 'step\n\nScope decisions:\n- q: a\n\nPlaybook: fixture\n%s\nCo-Authored-By: F <f@example.invalid>\n' "$1"; }
commit "$(trailers $'Playbook-Step: a:x@1.9\nPlaybook-Step: b:x@1.0')"
commit "$(trailers 'Playbook-Step: claude-api@builtin')"
gitf -C "$repo" update-ref refs/remotes/origin/main HEAD
gitf -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
commit "$(trailers 'Playbook-Step: new:x@1.0')" # local only: not on the default branch
assert_eq "fixture trailers parse" "claude-api@builtin" \
  "$(git -C "$repo" log -1 --format='%(trailers:key=Playbook-Step,valueonly)' origin/HEAD | awk NF)"

jq -n '{version: 2, plugins: {
  "a@m": [{scope: "user", version: "2.0"}], "b@m": [{scope: "user", version: "1.0"}],
  "c@m": [{scope: "user", version: "3.0"}], "d@m": [{scope: "user", version: "1.0"}],
  "new@m": [{scope: "user", version: "1.0"}]}}' >"$TMP/installed.json"

body() { # <done lines...>
  printf 'Summary\n<!-- repo-sweep:begin playbook=fixture -->\r\n'
  printf '%s\r\n' "$@"
  printf '<!-- repo-sweep:end -->\r\n'
}
jq -n --arg old "$(body '- [x] e-rerun: a:x@0.5, committed 1111111' '- [ ] e-run: new:x')" \
  --arg new "$(body '- [x] e-rerun: a:x@1.0, committed 2222222' '- [x] e-unknown: gone:x@3.0, no findings' \
    '- [x] e-multi: c:x@2.0, d:x, no findings' '- [x] e-bare: d:x')" \
  --arg decoy "$(body '- [x] e-run: new:x@9.0, no findings')" '[
  {headRefName: "chore/repo-sweep-fixture-20260101", mergedAt: "2026-01-01T00:00:00Z", body: $old},
  {headRefName: "chore/repo-sweep-fixture-20260201", mergedAt: "2026-02-01T00:00:00Z", body: $new},
  {headRefName: "fix/chore/repo-sweep-x", mergedAt: "2026-03-01T00:00:00Z", body: $decoy}]' >"$TMP/gh/merged.json"

printf '%s\n' '# Playbook: fixture' '## Phase 1: x' \
  '### e-run' '- skill: new:x' '### e-rerun' '- skill: a:x' '### e-same' '- skill: b:x' \
  '### e-builtin' '- skill: claude-api' '### e-unknown' '- skill: gone:x' \
  '### e-multi' '- skill: c:x, d:x' >"$TMP/cat.md"

run() {
  (cd "$repo" && PATH="$TMP/bin:$PATH" GH_DIR="$TMP/gh" GH_LOG="$TMP/gh.log" \
    REPO_SWEEP_INSTALLED_PLUGINS="$TMP/installed.json" REPO_SWEEP_PLUGIN_DIRS="" \
    GIT_CEILING_DIRECTORIES="$TMP" bash "$SCRIPT" "$@")
}

T=$'\t'
out=$(run "$TMP/cat.md" 2>"$TMP/err")
assert_eq "exit 0" "0" "$?"
assert_eq "recommendations: PR markers beat trailers, newest merge wins, decoy branch and HEAD-only trailer ignored" \
  "e-run${T}run${T}never ran: new:x
e-rerun${T}rerun${T}version changed: a:x 1.0 -> 2.0
e-same${T}rerun-optional${T}same version ran: b:x@1.0
e-builtin${T}rerun-optional${T}same version ran: claude-api@builtin
e-unknown${T}rerun-optional${T}same version ran: gone:x@3.0 (current version unknown)
e-multi${T}run${T}never ran: d:x" "$out"
assert_eq "no warning when gh works" "" "$(cat "$TMP/err")"
case "$(cat "$TMP/gh.log")" in
*"--limit 1000"*"--json headRefName,body,mergedAt"*) pass "gh called with --limit 1000" ;;
*) fail "gh called with --limit 1000" "--limit 1000" "$(cat "$TMP/gh.log")" ;;
esac

mv "$TMP/gh/merged.json" "$TMP/gh/merged.json.off"
out=$(run "$TMP/cat.md" 2>"$TMP/err")
assert_eq "gh failing: exit 0" "0" "$?"
assert_eq "gh failing: trailers only" "e-rerun${T}rerun${T}version changed: a:x 1.9 -> 2.0" "$(grep '^e-rerun' <<<"$out")"
case "$(cat "$TMP/err")" in
*"trailers only"*) pass "gh failing: warning on stderr" ;;
*) fail "gh failing: warning on stderr" "*trailers only*" "$(cat "$TMP/err")" ;;
esac

run >/dev/null 2>&1
assert_eq "no catalog: usage exit 2" "2" "$?"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'history.test.sh: all passed\n'
