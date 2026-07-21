#!/usr/bin/env bash
# Regression tests for telemetry-upsert.sh.
#
# Coverage:
#   - create when the issue has no matching comment (POST)
#   - update-in-place when the sentinel is present (PATCH to that comment id)
#   - fallback: no sentinel but MY comment carries the raw marker -> adopt it (PATCH)
#   - fallback never edits ANOTHER user's marker comment -> create instead
#   - pagination: a sentinel comment on a second page is found (no duplicate POST)
#   - argument validation: bad marker (incl. `>` injection), non-numeric issue,
#     missing body-file
#   - --dry-run resolves the action but performs no write
#   - `-` reads the body from stdin
#   - missing jq BINARY (not just the in-script wrapper function) exits 4
#
# PATH-stubs `gh`; the stub logs every mutating call and serves a fixture
# comment list, so no network or real issue is touched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/telemetry-upsert.sh"
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

STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
LOG="$TMP/gh.log"

# gh stub: serves `repo view`, `api user`, a paginated comment list from
# $STUB_COMMENTS_FILE, and logs PATCH/POST mutations (echoing a synthetic
# response so the script can extract .id / .html_url).
cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
args=("$@")
method=""; url=""; seen_api=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --method) method="${args[$((i + 1))]}" ;;
    api) seen_api=1 ;;
    repos/*|user) ((seen_api)) && [[ -z "$url" ]] && url="${args[$i]}" ;;
  esac
done

if [[ "${args[0]}" == "repo" && "${args[1]}" == "view" ]]; then
  echo "melodic-software/claude-code-plugins"
  exit 0
fi
if [[ "$url" == "user" ]]; then
  echo "${STUB_ME:-octocat}"
  exit 0
fi
if [[ -n "$method" ]]; then
  # Mutation: log it, echo a synthetic response.
  printf 'CALL method=%s url=%s\n' "$method" "$url" >>"$STUB_LOG"
  if [[ "$method" == "PATCH" ]]; then
    id="${url##*/}"
    printf '{"id":%s,"html_url":"https://github.com/o/r/issues/1#c%s"}\n' "$id" "$id"
  else
    printf '{"id":999,"html_url":"https://github.com/o/r/issues/1#c999"}\n'
  fi
  exit 0
fi
# List comments (GET, --paginate): serve the fixture verbatim.
if [[ "$url" == */comments ]]; then
  cat "${STUB_COMMENTS_FILE:-/dev/null}"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB_BIN/gh"
export PATH="$STUB_BIN:$PATH"
export STUB_LOG="$LOG"

# The safe body dir the containment check keys off; BODY lives under it.
SAFE_DIR="$TMP/safe"
mkdir -p "$SAFE_DIR"
BODY="$SAFE_DIR/body.txt"
printf 'lane: triage\nlast-cycle: 2026-07-21T06:00:00Z\nflags: none\n' >"$BODY"

REPO="melodic-software/claude-code-plugins"
run() { STUB_COMMENTS_FILE="$1" bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$BODY" --body-dir "$SAFE_DIR" "${@:2}"; }

SENT='<!-- claude-ops:lane-telemetry marker=lane:triage -->'

# ============================================================================
# create — no matching comment
# ============================================================================
echo '[]' >"$TMP/empty.json"
: >"$LOG"
out="$(run "$TMP/empty.json" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "create exits 0" 0 "$rc"
assert_contains "create reports created" "$out" "created comment 999"
assert_contains "create POSTs to the issue comments endpoint" "$log" "method=POST url=repos/$REPO/issues/502/comments"
assert_not_contains "create does not PATCH" "$log" "method=PATCH"

# ============================================================================
# update — sentinel already present
# ============================================================================
cat >"$TMP/has-sentinel.json" <<JSON
[
  { "id": 111, "created_at": "2026-07-20T00:00:00Z", "user": {"login": "octocat"},
    "body": "unrelated comment" },
  { "id": 222, "created_at": "2026-07-21T00:00:00Z", "user": {"login": "octocat"},
    "body": "$SENT\nlane: triage\nlast-cycle: old" }
]
JSON
: >"$LOG"
out="$(run "$TMP/has-sentinel.json" 2>&1)"
log="$(cat "$LOG")"
assert_contains "update reports updated" "$out" "updated comment 222"
assert_contains "update PATCHes the sentinel comment" "$log" "method=PATCH url=repos/$REPO/issues/comments/222"
assert_not_contains "update does not POST a second comment" "$log" "method=POST"

# ============================================================================
# fallback — no sentinel, my comment carries the raw marker -> adopt (PATCH)
# ============================================================================
cat >"$TMP/marker-only.json" <<'JSON'
[
  { "id": 333, "created_at": "2026-07-19T00:00:00Z", "user": {"login": "octocat"},
    "body": "telemetry for lane:triage\nlast-cycle: hand-authored, no sentinel yet" }
]
JSON
: >"$LOG"
out="$(run "$TMP/marker-only.json" --dry-run 2>&1)"
assert_contains "fallback matches my marker comment" "$out" "would update comment 333"
assert_contains "fallback labels the detection path" "$out" "matched via marker-fallback"

# ============================================================================
# fallback never edits another user's marker comment -> create instead
# ============================================================================
cat >"$TMP/other-user-marker.json" <<'JSON'
[
  { "id": 444, "created_at": "2026-07-19T00:00:00Z", "user": {"login": "someone-else"},
    "body": "telemetry for lane:triage\nlast-cycle: not mine" }
]
JSON
: >"$LOG"
out="$(STUB_ME="octocat" run "$TMP/other-user-marker.json" 2>&1)"
log="$(cat "$LOG")"
assert_contains "does not adopt another user's comment — creates" "$out" "created comment 999"
assert_contains "creates via POST" "$log" "method=POST"
assert_not_contains "never PATCHes another user's comment" "$log" "method=PATCH"

# ============================================================================
# fallback never adopts a comment whose marker is a longer superstring of mine
# -> `lane:triage` must not PATCH a `lane:triage-old` comment (prefix collision);
# it creates its own instead.
# ============================================================================
cat >"$TMP/prefix-collision.json" <<'JSON'
[
  { "id": 555, "created_at": "2026-07-19T00:00:00Z", "user": {"login": "octocat"},
    "body": "<!-- claude-ops:lane-telemetry marker=lane:triage-old -->\nother lane" }
]
JSON
: >"$LOG"
out="$(STUB_ME="octocat" run "$TMP/prefix-collision.json" 2>&1)"
log="$(cat "$LOG")"
assert_contains "prefix-collision marker does not adopt the longer lane — creates" "$out" "created comment 999"
assert_not_contains "never PATCHes the longer lane's comment" "$log" "method=PATCH url=repos/$REPO/issues/comments/555"

# ============================================================================
# pagination — sentinel comment on a SECOND page is still found (no duplicate)
# --paginate concatenates one array per page; the script slurps them.
# ============================================================================
cat >"$TMP/paged.json" <<JSON
[
  { "id": 501, "created_at": "2026-07-18T00:00:00Z", "user": {"login": "octocat"},
    "body": "page one, no marker" }
]
[
  { "id": 777, "created_at": "2026-07-21T00:00:00Z", "user": {"login": "octocat"},
    "body": "$SENT\nlane: triage" }
]
JSON
: >"$LOG"
out="$(run "$TMP/paged.json" 2>&1)"
log="$(cat "$LOG")"
assert_contains "second-page sentinel is found" "$out" "updated comment 777"
assert_not_contains "paginated find does not create a duplicate" "$log" "method=POST"

# ============================================================================
# argument validation
# ============================================================================
out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker 'lane>evil' --body-file "$BODY" 2>&1)"
rc=$?
assert_eq "marker with > (comment-injection) rejected exit 3" 3 "$rc"
assert_contains "bad marker message" "$out" "--marker must match"

out="$(bash "$SCRIPT" --repo "$REPO" --issue not-a-number --marker "lane:x" --body-file "$BODY" 2>&1)"
rc=$?
assert_eq "non-numeric issue rejected exit 3" 3 "$rc"

out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:x" --body-file "$TMP/missing.txt" 2>&1)"
rc=$?
assert_eq "missing body-file rejected exit 3" 3 "$rc"
assert_contains "missing body-file message" "$out" "body file not found"

# A space-form option given as the FINAL argument (no value) must exit 3, not
# spin the parse loop forever — `shift 2` on a lone arg does not consume it.
# Guarded with `timeout` where available so a regression fails the case instead
# of hanging CI.
if command -v timeout >/dev/null 2>&1; then
  out="$(timeout 10 bash "$SCRIPT" --repo "$REPO" --marker "lane:x" --body-file "$BODY" --issue 2>&1)"
  rc=$?
else
  out="$(bash "$SCRIPT" --repo "$REPO" --marker "lane:x" --body-file "$BODY" --issue 2>&1)"
  rc=$?
fi
assert_eq "trailing value-option with no value rejected exit 3 (no hang)" 3 "$rc"
assert_contains "missing option-value message" "$out" "--issue requires a value"

# ============================================================================
# SECURITY — a traversal --repo is rejected before any URL interpolation
# ============================================================================
out="$(bash "$SCRIPT" --repo 'foo/bar/../../org2/target' --issue 502 --marker "lane:triage" --body-file "$BODY" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
assert_eq "traversal --repo rejected exit 3" 3 "$rc"
assert_contains "traversal --repo message" "$out" "--repo must be owner/repo"

# ============================================================================
# SECURITY — a --body-file OUTSIDE the safe dir is refused (no arbitrary read):
# a prompt-injected secret path must never be cat'd into a public comment.
# ============================================================================
mkdir -p "$TMP/outside"
SECRET="$TMP/outside/secret.txt"
printf 'PRIVATE-KEY-MATERIAL\n' >"$SECRET"
out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$SECRET" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
assert_eq "body-file outside the safe dir rejected exit 3" 3 "$rc"
assert_contains "containment message names the safe dir" "$out" "must resolve under the safe dir"
assert_not_contains "the secret's content is never read or echoed" "$out" "PRIVATE-KEY-MATERIAL"

# A traversal body-file that escapes the safe dir via `..` is refused too
# (canonicalization resolves the `..` before the prefix check).
out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$SAFE_DIR/../outside/secret.txt" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
assert_eq "traversal body-file escaping the safe dir rejected exit 3" 3 "$rc"

# A SYMLINK leaf under the safe dir pointing at a secret is refused by the -L
# guard — containment (parent-dir canonicalization) alone would pass it. Skipped
# where the platform can't create symlinks (Windows without privilege); CI is
# Linux and exercises it.
LINK="$SAFE_DIR/link-to-secret.txt"
# MSYS `ln -s` silently makes a COPY, not a symlink, and returns 0 — so gate on
# the result actually being a symlink, not on ln's exit status.
if ln -s "$SECRET" "$LINK" 2>/dev/null && [[ -L "$LINK" ]]; then
  out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$LINK" --body-dir "$SAFE_DIR" 2>&1)"
  rc=$?
  assert_eq "symlinked body-file leaf rejected exit 3" 3 "$rc"
  assert_contains "symlink rejection message" "$out" "must not be a symlink"
  assert_not_contains "symlinked secret content never read" "$out" "PRIVATE-KEY-MATERIAL"
else
  pass "symlink leaf test skipped (platform cannot create symlinks)"
fi
rm -f "$LINK" 2>/dev/null

# No safe dir configured (no --body-dir, no CLAUDE_PLUGIN_DATA) fails closed.
out="$(env -u CLAUDE_PLUGIN_DATA bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$BODY" 2>&1)"
rc=$?
assert_eq "no safe body dir configured exits 4" 4 "$rc"
assert_contains "no safe body dir message" "$out" "no safe body dir"

# ============================================================================
# SECURITY (defense in depth) — an oversized body is refused
# ============================================================================
BIG="$SAFE_DIR/big.txt"
head -c 70000 /dev/zero | tr '\0' 'x' >"$BIG"
out="$(bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$BIG" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
assert_eq "oversized body rejected exit 3" 3 "$rc"
assert_contains "oversized body message" "$out" "over the"

# ============================================================================
# `-` reads body from stdin
# ============================================================================
: >"$LOG"
out="$(printf 'lane: from-stdin\n' | STUB_COMMENTS_FILE="$TMP/empty.json" bash "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file - 2>&1)"
rc=$?
assert_eq "stdin body exits 0" 0 "$rc"
assert_contains "stdin body creates a comment" "$out" "created comment 999"

# ============================================================================
# jq binary missing exits 4 — regression guard for the jq() wrapper (defined
# before this prereq check) shadowing `command -v jq` and fail-opening the
# guard. A PATH with no jq binary (only the gh stub) must still be caught by
# `type -P jq`, which looks at PATH executables only and ignores the wrapper.
# ============================================================================
# Resolve bash's own absolute path first so invoking it below needs no PATH
# lookup; then restrict the child's PATH to just STUB_BIN (the gh stub),
# which never contains jq — reaching the prereq check without an external jq
# binary anywhere in PATH, on any platform.
BASH_BIN="$(command -v bash)"
out="$(PATH="$STUB_BIN" "$BASH_BIN" "$SCRIPT" --repo "$REPO" --issue 502 --marker "lane:triage" --body-file "$BODY" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
assert_eq "missing jq binary exits 4" 4 "$rc"
assert_contains "missing jq binary message" "$out" "jq not found"

# ============================================================================
echo
if ((FAILED)); then
  printf 'telemetry-upsert.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'telemetry-upsert.test: PASS — %d cases\n' "$CASE_NUM"
