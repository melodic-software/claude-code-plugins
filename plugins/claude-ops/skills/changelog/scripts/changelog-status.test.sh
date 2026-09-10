#!/usr/bin/env bash
# Regression tests for changelog-status.sh.
#
# Coverage:
#   - the marker line in the ledger wins, and the default range runs from it to
#     the newest release, oldest first, with [VSCode] lines excluded from the count
#   - a marker at the newest release reports "up to date"
#   - with no ledger, a Conventional Commits SUBJECT naming an applied release
#     is the fallback, and the highest version across such subjects wins
#   - a commit BODY mentioning a Claude Code version is never read as an apply
#   - no ledger and no subject: last-applied none, whole feed, recommendation
#   - the cap fires on releases and on items, with the marker-reset recommendation
#   - --range A..B is inclusive at both ends and ignores the marker; --range X is
#     one release; a malformed range exits 3
#   - --no-fetch without --changelog reports the marker and "not computed", exit 0
#   - a body whose first heading is not the changelog page is refused
#   - CLAUDE_OPS_CHANGELOG_LEDGER overrides the default path; --ledger wins over it
#   - a PATH-stub `claude` older than the newest release produces the warn line
#   - an unknown argument exits 3
#
# Uses the fixtures under ../evals/fixtures (changelog-sample.md, ledger-marker.md),
# per-case fixture git repositories, and a PATH-stub `claude` so no real CLI or
# network is touched. Every invocation passes --changelog, so curl is never run.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git commit` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/changelog-status.sh"
FIXTURES="$SCRIPT_DIR/../evals/fixtures"
CHANGELOG="$FIXTURES/changelog-sample.md"
LEDGER="$FIXTURES/ledger-marker.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# PATH stub for `claude --version`: the version is read from CLAUDE_STUB_VERSION.
mkdir -p "$TMP/stub"
cat >"$TMP/stub/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s (Claude Code)\n' "${CLAUDE_STUB_VERSION:-2.1.263}"
STUB
chmod +x "$TMP/stub/claude"
export PATH="$TMP/stub:$PATH"

# A fixture repository with the given commits (subject, optional body), no ledger.
make_repo() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "chore: seed"
  while (($#)); do
    local subject="$1" body="${2:-}"
    if [[ -n "$body" ]]; then
      git -C "$dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$subject" -m "$body"
    else
      git -C "$dir" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "$subject"
    fi
    shift 2 || shift
  done
}

# Run the script from inside a directory, capturing stdout and the exit code.
run_in() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && bash "$SCRIPT" "$@" 2>"$TMP/stderr")"
  RC=$?
  ERR="$(cat "$TMP/stderr")"
}

# --- Case 1: marker line wins; default range from marker to newest ----------------
EMPTY="$TMP/empty"
mkdir -p "$EMPTY"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG"
assert_eq "marker: exit 0" 0 "$RC"
assert_contains "marker: last-applied from the ledger line" "$OUT" "last-applied: 2.1.260"
assert_contains "marker: source names the ledger" "$OUT" "source: ledger:$LEDGER"
assert_contains "marker: ledger present" "$OUT" "ledger: $LEDGER (present)"
assert_contains "marker: latest is the newest block" "$OUT" "latest: 2.1.263"
assert_contains "marker: range excludes the marker, includes the newest" "$OUT" "range: 2.1.261..2.1.263 (2 releases, 6 core items)"
assert_contains "marker: releases listed oldest first" "$OUT" "releases: 2.1.261 2.1.263"
assert_contains "marker: within budget at the defaults" "$OUT" "cap: within budget (10 releases / 300 items)"
assert_not_contains "marker: no recommendation when a marker exists and the cap holds" "$OUT" "recommend:"
assert_not_contains "marker: no warn when installed equals latest" "$OUT" "warn:"

# --- Case 2: marker at the newest release -> up to date -----------------------------
sed 's/2\.1\.260/2.1.263/' "$LEDGER" >"$TMP/ledger-current.md"
run_in "$EMPTY" --ledger "$TMP/ledger-current.md" --changelog "$CHANGELOG"
assert_eq "current: exit 0" 0 "$RC"
assert_contains "current: last-applied 2.1.263" "$OUT" "last-applied: 2.1.263"
assert_contains "current: up to date" "$OUT" "range: up to date"
assert_not_contains "current: no cap line" "$OUT" "cap:"

# --- Case 3: no ledger; subject fallback; highest subject version wins --------------
REPO_SUBJ="$TMP/repo-subject"
make_repo "$REPO_SUBJ" \
  "chore(claude-config): address Claude Code v2.1.257..2.1.259 changelog" "" \
  "chore(lanes): address Claude Code v2.1.260 changelog" "" \
  "docs: unrelated" ""
run_in "$REPO_SUBJ" --changelog "$CHANGELOG"
assert_eq "subject: exit 0" 0 "$RC"
assert_contains "subject: highest subject version" "$OUT" "last-applied: 2.1.260"
assert_contains "subject: source git-subject" "$OUT" "source: git-subject"
assert_contains "subject: ledger absent at the default path" "$OUT" "ledger: $REPO_SUBJ/docs/upstream/claude-code.md (absent)"
assert_contains "subject: range from the subject marker" "$OUT" "range: 2.1.261..2.1.263 (2 releases, 6 core items)"

# --- Case 4: body mentions are never read --------------------------------------------
REPO_BODY="$TMP/repo-body"
make_repo "$REPO_BODY" \
  "docs(claude-config): refresh the permission stamps" "Verified against Claude Code v2.1.252 changelog on 2026-08-20." \
  "fix(guardrails): quote the worktree path" "Recheck when Claude Code v2.1.255 changelog names the isolation checks." \
  "chore(lanes): refresh the lane prompts" "Prompts now cite CC v2.1.250."
run_in "$REPO_BODY" --changelog "$CHANGELOG" --cap-releases 1
assert_eq "body: exit 0" 0 "$RC"
assert_contains "body: last-applied none" "$OUT" "last-applied: none"
assert_contains "body: source none" "$OUT" "source: none"
assert_not_contains "body: 2.1.252 never surfaces" "$OUT" "2.1.252"
assert_not_contains "body: 2.1.255 never surfaces" "$OUT" "2.1.255"
assert_contains "body: whole feed is the range" "$OUT" "range: 2.1.257..2.1.263 (6 releases, 20 core items)"
assert_contains "body: cap exceeded on releases" "$OUT" "cap: exceeded (1 releases / 300 items)"
assert_contains "body: release list omitted beyond the release cap" "$OUT" "releases: (6 releases, list omitted beyond the cap)"
assert_contains "body: recommendation names the ledger and the reset version" "$OUT" "recommend: replay cost scales with items"
assert_contains "body: recommendation sets the marker to the newest in range" "$OUT" "to 2.1.263 and diff only from there"

# --- Case 5: no marker, cap holds -> recommend creating the ledger after the apply ----
run_in "$REPO_BODY" --changelog "$CHANGELOG"
assert_contains "no-marker: within budget at the defaults" "$OUT" "cap: within budget (10 releases / 300 items)"
assert_contains "no-marker: recommend creating the ledger" "$OUT" "recommend: no read marker. After this range is applied, create $REPO_BODY/docs/upstream/claude-code.md with the marker line at 2.1.263"

# --- Case 6: cap fires on items -----------------------------------------------------
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --cap-items 5
assert_contains "cap-items: exceeded" "$OUT" "cap: exceeded (10 releases / 5 items)"
assert_contains "cap-items: release list kept when only the item cap fires" "$OUT" "releases: 2.1.261 2.1.263"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --cap-items 6
assert_contains "cap-items: boundary is inclusive" "$OUT" "cap: within budget (10 releases / 6 items)"

# --- Case 7: explicit ranges ---------------------------------------------------------
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --range v2.1.258..v2.1.261
assert_eq "range: exit 0" 0 "$RC"
assert_contains "range: inclusive at both ends, marker ignored" "$OUT" "range: 2.1.258..2.1.261 (4 releases, 14 core items)"
assert_contains "range: releases oldest first" "$OUT" "releases: 2.1.258 2.1.259 2.1.260 2.1.261"
assert_contains "range: marker still reported" "$OUT" "last-applied: 2.1.260"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --range 2.1.259
assert_contains "range: single release" "$OUT" "range: 2.1.259..2.1.259 (1 releases, 4 core items)"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --range 2.1.100..2.1.101
assert_contains "range: empty window reported" "$OUT" "range: not computed (no release between 2.1.100 and 2.1.101 in the changelog)"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$CHANGELOG" --range 2.1.258-2.1.261
assert_eq "range: malformed exits 3" 3 "$RC"
assert_contains "range: malformed names the form" "$ERR" "--range takes A..B or X"

# --- Case 8: --no-fetch without a changelog ------------------------------------------
run_in "$EMPTY" --ledger "$LEDGER" --no-fetch
assert_eq "no-fetch: exit 0" 0 "$RC"
assert_contains "no-fetch: marker still read" "$OUT" "last-applied: 2.1.260"
assert_contains "no-fetch: latest unknown" "$OUT" "latest: unknown"
assert_contains "no-fetch: range not computed with the reason" "$OUT" "range: not computed (no changelog source: --no-fetch and no --changelog)"
run_in "$REPO_BODY" --no-fetch
assert_contains "no-fetch: no marker still recommends the recheck" "$OUT" "recommend: no read marker. Run a docs-conformance recheck"

# --- Case 9: wrong page identity is refused ------------------------------------------
printf '# Extend Claude with skills\n\n<Update label="9.9.9" description="x">\n  * item\n</Update>\n' >"$TMP/other-page.md"
run_in "$EMPTY" --ledger "$LEDGER" --changelog "$TMP/other-page.md"
assert_eq "identity: exit 0" 0 "$RC"
assert_contains "identity: refused with the heading" "$OUT" "range: not computed (body is not the changelog page (first heading: # Extend Claude with skills))"
assert_not_contains "identity: no count from the wrong page" "$OUT" "9.9.9"

# --- Case 10: env override and --ledger precedence ------------------------------------
REPO_ENV="$TMP/repo-env"
make_repo "$REPO_ENV"
mkdir -p "$REPO_ENV/notes"
sed 's/2\.1\.260/2.1.259/' "$LEDGER" >"$REPO_ENV/notes/cc.md"
OUT="$(cd "$REPO_ENV" && CLAUDE_OPS_CHANGELOG_LEDGER="$REPO_ENV/notes/cc.md" bash "$SCRIPT" --changelog "$CHANGELOG" 2>/dev/null)"
assert_contains "env: override path read" "$OUT" "last-applied: 2.1.259"
assert_contains "env: source names the override" "$OUT" "source: ledger:$REPO_ENV/notes/cc.md"
OUT="$(cd "$REPO_ENV" && CLAUDE_OPS_CHANGELOG_LEDGER="$REPO_ENV/notes/cc.md" bash "$SCRIPT" --ledger "$LEDGER" --changelog "$CHANGELOG" 2>/dev/null)"
assert_contains "env: --ledger wins over the env" "$OUT" "last-applied: 2.1.260"

# --- Case 11: default ledger path under the repo root ---------------------------------
mkdir -p "$REPO_ENV/docs/upstream"
cp "$LEDGER" "$REPO_ENV/docs/upstream/claude-code.md"
mkdir -p "$REPO_ENV/sub/dir"
run_in "$REPO_ENV/sub/dir" --changelog "$CHANGELOG"
assert_contains "default: found from a subdirectory via the repo root" "$OUT" "source: ledger:$REPO_ENV/docs/upstream/claude-code.md"

# --- Case 12: installed older than latest -> warn --------------------------------------
OUT="$(cd "$EMPTY" && CLAUDE_STUB_VERSION=2.1.259 bash "$SCRIPT" --ledger "$LEDGER" --changelog "$CHANGELOG" 2>/dev/null)"
assert_contains "warn: installed read from claude --version" "$OUT" "installed: 2.1.259"
assert_contains "warn: older installed warns" "$OUT" "warn: installed 2.1.259 is older than the newest published release 2.1.263"
OUT="$(cd "$EMPTY" && CLAUDE_STUB_VERSION=2.1.270 bash "$SCRIPT" --ledger "$LEDGER" --changelog "$CHANGELOG" 2>/dev/null)"
assert_not_contains "warn: newer installed does not warn" "$OUT" "warn:"

# --- Case 13: argument errors ------------------------------------------------------------
run_in "$EMPTY" --bogus
assert_eq "args: unknown argument exits 3" 3 "$RC"
assert_contains "args: unknown argument named" "$ERR" "unknown argument: --bogus"
run_in "$EMPTY" --changelog "$TMP/does-not-exist.md"
assert_eq "args: unreadable changelog exits 3" 3 "$RC"
run_in "$EMPTY" --cap-items ten --changelog "$CHANGELOG"
assert_eq "args: non-integer cap exits 3" 3 "$RC"
run_in "$EMPTY" --help
assert_eq "args: --help exits 0" 0 "$RC"
assert_contains "args: --help prints the usage" "$OUT" "Usage:"

# --- Summary ---------------------------------------------------------------------------
if ((FAILED > 0)); then
  printf '\n%d of %d assertions failed\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf '\nAll %d assertions passed\n' "$CASE_NUM"
