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
#   - pre-write body gate: an `@path` body (file AND stdin), an under-floor body,
#     and an empty body each exit 3 having made NO API call
#   - post-write read-back: a good body verifies; a body that came back `@`-led,
#     sentinel-only, or without the sentinel exits 6; a failed GET is retried
#     once then exits 6 reporting the cycle UNCONFIRMED; a response with no id
#     exits 6; --dry-run reads nothing back
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
# $STUB_COMMENTS_FILE, the post-write read-back GET of a single comment, and logs
# PATCH/POST mutations (echoing a synthetic response so the script can extract
# .id / .html_url).
#
# Read-back knobs (all default to a body that verifies):
#   STUB_READBACK_BODY  exact body the read-back GET returns (emitted CRLF)
#   STUB_READBACK_FAIL  non-empty: the read-back GET fails with a 403 rate limit
#   STUB_READBACK_404   non-empty: the read-back GET fails with a 404
#   STUB_NO_ID          non-empty: mutations answer with no `id` field
#   STUB_NO_ID_PATCH    non-empty: only PATCH answers with no `id` field
#   STUB_NO_HTML_URL    non-empty: mutations answer with an `id` but no `html_url`
#   STUB_BAD_ID         non-empty: mutations answer with a non-numeric traversal `id`
cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
args=("$@")
method=""; url=""; jq_query=""; seen_api=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --method) method="${args[$((i + 1))]}" ;;
    --jq) jq_query="${args[$((i + 1))]}" ;;
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
  if [[ -n "${STUB_NO_ID:-}" ]]; then
    printf '{"html_url":"https://github.com/o/r/issues/1#c0"}\n'
  elif [[ -n "${STUB_NO_ID_PATCH:-}" && "$method" == "PATCH" ]]; then
    printf '{"html_url":"https://github.com/o/r/issues/1#c222"}\n'
  elif [[ -n "${STUB_BAD_ID:-}" ]]; then
    printf '{"id":"../../../org2/target/issues/comments/1","html_url":"https://github.com/o/r/issues/1#c0"}\n'
  elif [[ -n "${STUB_NO_HTML_URL:-}" ]]; then
    printf '{"id":999}\n'
  elif [[ "$method" == "PATCH" ]]; then
    id="${url##*/}"
    printf '{"id":%s,"html_url":"https://github.com/o/r/issues/1#c%s"}\n' "$id" "$id"
  else
    printf '{"id":999,"html_url":"https://github.com/o/r/issues/1#c999"}\n'
  fi
  exit 0
fi
# Read-back (GET one comment by id). Only `--jq .body` yields the raw body text
# — real `gh` without it emits the whole comment JSON, so a regression that drops
# the projection must not keep passing here.
if [[ "$url" == */issues/comments/* ]]; then
  printf 'CALL method=GET url=%s\n' "$url" >>"$STUB_LOG"
  # Failure knobs write to STDERR the way real gh does, so the script's capture
  # of that text (and the 404-vs-rate-limit verdict it derives) is exercised.
  if [[ -n "${STUB_READBACK_404:-}" ]]; then
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
  if [[ -n "${STUB_READBACK_FAIL:-}" ]]; then
    printf 'gh: You have exceeded a secondary rate limit (HTTP 403)\n' >&2
    exit 1
  fi
  if [[ "$jq_query" != ".body" ]]; then
    printf '{"id":999,"body":"a JSON object, not the raw body"}\n'
    exit 0
  fi
  # GitHub stores comment bodies with CRLF line endings, so the stub emits them:
  # without the script's `tr -d '\r'` the `@`-prefix assertion below the sentinel
  # silently stops matching, and the guard would go inert against the real API
  # while a LF-only stub kept the suite green.
  #
  # Emitted in pure bash rather than `sed 's/$/\r/'`: `\r` in a sed REPLACEMENT is
  # a GNU extension that BSD/macOS sed renders as a literal `r`, which would make
  # this stub emit the wrong bytes on the one platform the repo's portability
  # check does not cover (its token list scans patterns, not replacements).
  emit_crlf() {
    local line
    while IFS= read -r line; do printf '%s\r\n' "$line"; done
  }
  if [[ -n "${STUB_READBACK_BODY+set}" ]]; then
    printf '%s\n' "$STUB_READBACK_BODY" | emit_crlf
  else
    printf '%s\nlane: triage\nlast-cycle: 2026-07-21T06:00:00Z\nflags: none\n' "${STUB_SENTINEL:-}" | emit_crlf
  fi
  exit 0
fi
# List comments (GET, --paginate): serve the fixture verbatim. Logged like every
# other call so a pre-write rejection can assert an EMPTY log — proving zero API
# calls, not merely zero mutations.
if [[ "$url" == */comments ]]; then
  printf 'CALL method=GET url=%s\n' "$url" >>"$STUB_LOG"
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
export STUB_SENTINEL="$SENT"

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
rc=$?
log="$(cat "$LOG")"
assert_eq "update exits 0" 0 "$rc"
assert_contains "update reports updated" "$out" "updated comment 222"
assert_contains "update PATCHes the sentinel comment" "$log" "method=PATCH url=repos/$REPO/issues/comments/222"
assert_not_contains "update does not POST a second comment" "$log" "method=POST"
# The read-back must GET the comment that was actually written, not a fixed id:
# reading back the wrong comment would verify somebody else's body as ours.
assert_contains "update reads back the comment it PATCHed" "$log" "method=GET url=repos/$REPO/issues/comments/222"

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
# The body length is load-bearing: `lane: from-stdin` is exactly MIN_BODY_BYTES
# once the trailing newline is stripped, so it doubles as the floor's inclusive
# boundary. Shortening it turns this into a pre-write rejection.
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
# PRE-WRITE BODY GATE (#952) — the #943 fail-open is a comment whose timestamp
# moves while its body carries no telemetry. The gate catches it BEFORE the
# write, so nothing degraded is ever published: every case below must exit 3
# having made no API call at all (an EMPTY stub log, not merely no mutation).
# ============================================================================

# The #943 defect itself: a caller composed `@path` as its body content, meaning
# the file. Posting that verbatim is the fail-open — refuse before writing.
ATPATH="$SAFE_DIR/atpath.txt"
printf '@C:/Users/KYLESE~1/AppData/Local/Temp/telemetry_combined.txt\n' >"$ATPATH"
: >"$LOG"
out="$(STUB_COMMENTS_FILE="$TMP/empty.json" bash "$SCRIPT" --repo "$REPO" --issue 502 \
  --marker "lane:triage" --body-file "$ATPATH" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "@path body rejected pre-write exit 3" 3 "$rc"
assert_contains "@path rejection names the literal @" "$out" "starts with a literal '@'"
assert_contains "@path rejection points at the fix" "$out" "use --body-file PATH"
assert_contains "@path rejection says nothing was written" "$out" "nothing was written"
assert_eq "@path body reaches no API call at all" "" "$log"

# Same gate on the stdin path — a lane piping an interpolated `@path` string is
# the realistic vector, since `-` is the recommended body input.
: >"$LOG"
out="$(printf '@/tmp/telemetry.txt\n' | STUB_COMMENTS_FILE="$TMP/empty.json" bash "$SCRIPT" \
  --repo "$REPO" --issue 502 --marker "lane:triage" --body-file - 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "@path stdin body rejected pre-write exit 3" 3 "$rc"
assert_eq "@path stdin body reaches no API call at all" "" "$log"

# Degenerate sibling: a body too short to be telemetry would leave a comment
# that still looks fresh.
TINY="$SAFE_DIR/tiny.txt"
printf 'ok\n' >"$TINY"
: >"$LOG"
out="$(STUB_COMMENTS_FILE="$TMP/empty.json" bash "$SCRIPT" --repo "$REPO" --issue 502 \
  --marker "lane:triage" --body-file "$TINY" --body-dir "$SAFE_DIR" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "under-floor body rejected pre-write exit 3" 3 "$rc"
assert_contains "under-floor rejection names the floor" "$out" "under the 16-byte floor"
assert_eq "under-floor body reaches no API call at all" "" "$log"

# An empty body is the same rejection, not a special case.
: >"$LOG"
out="$(printf '' | STUB_COMMENTS_FILE="$TMP/empty.json" bash "$SCRIPT" --repo "$REPO" \
  --issue 502 --marker "lane:triage" --body-file - 2>&1)"
rc=$?
assert_eq "empty stdin body rejected pre-write exit 3" 3 "$rc"

# ============================================================================
# POST-WRITE READ-BACK (#952) — secondary confirmation. The body's content was
# already cleared pre-write, so these cases stand in for damage between the
# write and what a reader of the issue finds.
# ============================================================================

# A verified write re-reads the comment it just wrote (guard is not inert).
: >"$LOG"
out="$(run "$TMP/empty.json" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "verified write exits 0" 0 "$rc"
assert_contains "verified write re-reads the written comment" "$log" "method=GET url=repos/$REPO/issues/comments/999"

# What landed starts with `@` although what was sent did not. The sentinel is
# line one, so the check must look BELOW it.
: >"$LOG"
out="$(STUB_READBACK_BODY="$SENT"$'\n@C:/Users/KYLESE~1/AppData/Local/Temp/telemetry_combined.txt' \
  run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "@path read-back body exits 6" 6 "$rc"
assert_contains "@path read-back names the literal @" "$out" "starts with a literal '@'"
assert_contains "@path read-back blames the store, not the caller's body" "$out" "the stored comment diverged from what was written"
assert_contains "@path read-back names the comment url" "$out" "https://github.com/o/r/issues/1#c999"

# Degenerate sibling: an empty body leaves a sentinel-only comment that still
# looks fresh.
out="$(STUB_READBACK_BODY="$SENT" run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "sentinel-only read-back body exits 6" 6 "$rc"
assert_contains "sentinel-only failure names the floor" "$out" "under the 16-byte floor"

# A body that lost the sentinel is not this marker's comment any more.
out="$(STUB_READBACK_BODY="lane: triage, but no sentinel at all" run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "read-back without the sentinel exits 6" 6 "$rc"
assert_contains "missing-sentinel message" "$out" "does not carry the marker sentinel"

# Cannot verify == not verified: a failed read-back is never treated as success,
# but it is retried first — the write already landed, so a transient read failure
# must not report a good cycle as a bad one.
: >"$LOG"
out="$(STUB_READBACK_FAIL=1 run "$TMP/empty.json" 2>&1)"
rc=$?
gets="$(grep -c "url=repos/$REPO/issues/comments/" "$LOG")"
assert_eq "failed read-back GET exits 6" 6 "$rc"
assert_contains "failed read-back message" "$out" "could not re-read comment"
assert_eq "failed read-back is retried once before failing" 2 "$gets"
# A read-back that could not RUN is reported differently from one that disagreed:
# the body already cleared the pre-write gate, so the comment is unconfirmed
# rather than known-bad, and the operator is told so.
assert_contains "unreachable read-back is reported as unconfirmed" "$out" "UNCONFIRMED"
# gh's own error text must reach the operator — it is the only thing separating a
# rate limit (the comment is there, just unread) from a 404 (it is gone).
assert_contains "rate-limited read-back surfaces gh's error text" "$out" "secondary rate limit"

# A 404 contradicts the default "probably intact" reading, so the verdict branches.
out="$(STUB_READBACK_404=1 run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "404 read-back exits 6" 6 "$rc"
assert_contains "404 read-back surfaces gh's error text" "$out" "HTTP 404"
assert_contains "404 read-back says the comment is not retrievable" "$out" "NOT RETRIEVABLE"
assert_not_contains "404 read-back does not assert the comment is intact" "$out" "so the comment is probably intact"

# The stderr capture is a DIAGNOSTIC: an unwritable TMPDIR must not turn an
# otherwise good write into a verification failure.
out="$(TMPDIR="$TMP/nonexistent-dir" run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "unwritable TMPDIR does not fail a good write" 0 "$rc"
assert_contains "unwritable TMPDIR still reports the upsert" "$out" "created comment 999"

# Same rule when the write response carries no id to read back.
out="$(STUB_NO_ID=1 run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "write response with no comment id exits 6" 6 "$rc"
assert_contains "no-id message" "$out" "carried no comment id"

# A non-numeric comment id never reaches a gh api URL path — the same rule the
# --repo validation enforces, applied to the one other interpolated value. A
# traversal id would otherwise redirect the read-back GET to another repo.
: >"$LOG"
out="$(STUB_BAD_ID=1 run "$TMP/empty.json" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "non-numeric comment id exits 6" 6 "$rc"
assert_contains "non-numeric id message" "$out" "non-numeric comment id"
assert_not_contains "traversal id never reaches a read-back GET" "$log" "org2/target"

# A PATCH response with no `id` is still verifiable: the update path already
# resolved the target id, so it falls back to that rather than declaring a
# successful write unverifiable over a missing response field.
: >"$LOG"
out="$(STUB_NO_ID_PATCH=1 run "$TMP/has-sentinel.json" 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "PATCH response with no id still exits 0" 0 "$rc"
assert_contains "id-less PATCH reads back the resolved target id" "$log" "method=GET url=repos/$REPO/issues/comments/222"

# A response carrying an id but NO html_url still exits 0. The trailing
# `[[ -n "$html_url" ]] && printf` used to be the script's last command, so its
# false branch became the exit status and a verified upsert reported failure.
out="$(STUB_NO_HTML_URL=1 run "$TMP/empty.json" 2>&1)"
rc=$?
assert_eq "verified write with no html_url still exits 0" 0 "$rc"
assert_contains "no-html_url write still reports the upsert" "$out" "created comment 999"

# --dry-run writes nothing, so it reads nothing back.
: >"$LOG"
out="$(run "$TMP/has-sentinel.json" --dry-run 2>&1)"
rc=$?
log="$(cat "$LOG")"
assert_eq "dry-run exits 0" 0 "$rc"
assert_not_contains "dry-run performs no read-back" "$log" "url=repos/$REPO/issues/comments/"

# ============================================================================
echo
if ((FAILED)); then
  printf 'telemetry-upsert.test: FAIL — %d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'telemetry-upsert.test: PASS — %d cases\n' "$CASE_NUM"
