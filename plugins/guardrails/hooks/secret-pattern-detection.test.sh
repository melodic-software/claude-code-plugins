#!/usr/bin/env bash
# Contract test for secret-pattern-detection.sh (guardrails plugin).
#
# Black-box subprocess invocation. The hook reads file_path as a string only —
# fixtures need not exist on disk.
#
# Token construction discipline: every real-shape token is assembled at runtime
# from concatenated parts, so the literal joined string never appears in this
# file's source bytes — no secret scanner (gitleaks etc.) sees a committed key.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/secret-pattern-detection.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Neutralize any ambient CLAUDE_PROJECT_DIR (a CC-wrapped run sets it) so the
# default cases exercise the fail-closed scan path deterministically.
unset CLAUDE_PROJECT_DIR

# Runtime-constructed obviously-fake tokens (never a literal joined string).
AWS_PREFIX='AKIA'
AWS_TOKEN="${AWS_PREFIX}IOSFODNN7EXAMPLE"
GH_PREFIX='ghp_'
GH_PAT="${GH_PREFIX}$(printf 'a%.0s' {1..36})"
SLACK_PREFIX='xoxb-'
SLACK_TOKEN="${SLACK_PREFIX}1234567890123-9876543210987"
STRIPE_PREFIX='sk_live_'
STRIPE_TOKEN="${STRIPE_PREFIX}abcdefghij1234567890"
OPENAI_PREFIX='sk-'
OPENAI_BARE_KEY="${OPENAI_PREFIX}$(printf 'A%.0s' {1..25})"
PEM_HEADER='-----BEGIN '"PRIVATE KEY-----"

# Force the Windows case-fold path even on Linux CI: OSTYPE must be set BEFORE
# the hook is sourced (bash resets it to the build value at startup).
run_hook_windows() {
  bash -c 'OSTYPE=msys; source "$1"' _ "$HOOK" <<<"$1"
}

FIXTURE="$TEST_TMPDIR/fixture.txt"

# ============================ DETECT (exit 2) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "config = '$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "AWS Access Key → exit 2" 2 "$RC"
assert_contains "AWS → message" "$OUT" "AWS Access Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_PAT'")" 2>&1); RC=$?
assert_exit "GitHub PAT → exit 2" 2 "$RC"
assert_contains "GH PAT → message" "$OUT" "GitHub PAT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "SLACK='$SLACK_TOKEN'")" 2>&1); RC=$?
assert_exit "Slack Bot Token → exit 2" 2 "$RC"
assert_contains "Slack → message" "$OUT" "Slack Bot Token"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "STRIPE_KEY='$STRIPE_TOKEN'")" 2>&1); RC=$?
assert_exit "Stripe Key → exit 2" 2 "$RC"
assert_contains "Stripe → message" "$OUT" "Stripe Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "OPENAI_KEY='$OPENAI_BARE_KEY'")" 2>&1); RC=$?
assert_exit "OpenAI bare sk- key → exit 2" 2 "$RC"
assert_contains "OpenAI bare sk- → message" "$OUT" "OpenAI API Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "$PEM_HEADER")" 2>&1); RC=$?
assert_exit "PEM private key → exit 2" 2 "$RC"
assert_contains "PEM → message" "$OUT" "Private Key (PEM)"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "old to '$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "secret = '$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

# A content string may legitimately encode a NUL, and the payload fields are read
# NUL-separated. hook::jq_fields strips NUL jq-side so the delimiter cannot
# collide with content; without that the field count came back wrong, this hook's
# `|| exit 0` skipped detection entirely, and a credential placed AFTER the NUL
# passed unblocked. Built with jq (`[0] | implode`) so no literal escape sequence
# for the byte appears in this file's source.
NUL_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$FIXTURE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:("harmless first line" + ([0] | implode) + "config = " + $tok)}}')
OUT=$(bash "$HOOK" <<<"$NUL_PAYLOAD" 2>&1); RC=$?
assert_exit "secret AFTER a NUL byte in content → exit 2" 2 "$RC"
assert_contains "secret after NUL → NUL refusal message" "$OUT" "NUL byte"

# In-project secret still blocks when CLAUDE_PROJECT_DIR is set (file under root).
OUT=$(CLAUDE_PROJECT_DIR="/repo" bash "$HOOK" <<<"$(write_json "/repo/src/config.env" "config = '$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "in-project secret with PROJECT_DIR set → exit 2" 2 "$RC"
assert_contains "in-project secret → message" "$OUT" "AWS Access Key"

# Trailing slash on CLAUDE_PROJECT_DIR must not skip in-project scans.
OUT=$(CLAUDE_PROJECT_DIR="/repo/" bash "$HOOK" <<<"$(write_json "/repo/src/config.env" "config = '$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "trailing-slash PROJECT_DIR still scans in-project file → exit 2" 2 "$RC"

# ============================ ALLOW (exit 0) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'just some normal code here')" 2>&1); RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'api_key=mySecretValue123')" 2>&1); RC=$?
assert_exit "low-confidence generic pattern → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1); RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.env.example" "API_KEY='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit ".env.example allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/tests/fixtures/secrets.txt" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "tests/fixtures/ allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.claude/hooks/foo.sh" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/settings.local.json" "{\"k\":\"$AWS_TOKEN\"}")" 2>&1); RC=$?
assert_exit "settings.local.json allowlist → exit 0" 0 "$RC"

# CLAUDE.local.md allowlist must match case-sensitively even under the Windows
# path fold (regression: the fold lower-cases the membership path only).
OUT=$(run_hook_windows "$(write_json "C:/repo/CLAUDE.local.md" "token='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "CLAUDE.local.md allowlist (case-sensitive) → exit 0" 0 "$RC"

# Secret in a file OUTSIDE the project root → exit 0, silent.
OUT=$(CLAUDE_PROJECT_DIR="/repo" bash "$HOOK" <<<"$(write_json "/other-repo/fixtures/bad/leak.env" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "file outside project root → exit 0" 0 "$RC"
assert_silent "outside project root → no stderr" "$OUT"

# Kill switch — disabled path is a clean no-op even on a real-shape token.
OUT=$(CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"

# --- jq fail-open visibility (finding P4) -----------------------------------
# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils (their DLLs / PATH) across Git Bash and Linux.
# Assert the fail-open guard is present in the hook source via the shared
# hook::require_jq helper (docs/conventions/hook-observability/) — it composes
# the once-per-session notice_once gate with the dual-channel (systemMessage +
# additionalContext) visibility notice; require_jq's own behavior is covered
# by lib/hook-utils.test.sh, not re-asserted here.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'

# --- Allowlist path-segment anchoring (finding P5) --------------------------
# A real dependency-cache SEGMENT is exempt; a directory that merely CONTAINS the
# name as a substring is scanned (and blocked on a real token).
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/src/node_modules/pkg/creds.env" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "node_modules real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/evil_node_modules/creds.env" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "evil_node_modules substring → exit 2 (scanned)" 2 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv/lib/creds.env" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit ".venv real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv-backup/creds.env" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit ".venv-backup impostor → exit 2 (scanned)" 2 "$RC"

# ============================ TELEMETRY ====================================
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="/repo" \
  bash "$HOOK" <<<"$(write_json "/repo/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "secret-pattern-detection"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: violation label" "$(jq -r '.data.violations[]' "$TEL")" "AWS Access Key"
  assert_absent "telemetry: no raw token in envelope" "$(cat "$TEL")" "$AWS_TOKEN"
else
  bad "telemetry: no envelope written on block"
fi

# --- Telemetry path redaction (finding P4): absolute path (no project dir) →
# --- basename only, so no username-bearing path lands in the envelope --------
H="ho""me"
ABS_FILE="/${H}/alice/secretproj/config.env"
TELR="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKR="$(make_sink "cat >\"$TELR\"")"
env HOOK_TELEMETRY_SINK="$SINKR" bash "$HOOK" \
  <<<"$(write_json "$ABS_FILE" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELR"; then
  df=$(jq -r '.data.file' "$TELR")
  assert_contains "redaction: data.file is the basename" "$df" "config.env"
  assert_absent "redaction: data.file has no path separator" "$df" "/"
  assert_absent "redaction: envelope drops the username dir" "$(cat "$TELR")" "alice"
else
  bad "redaction: no envelope written"
fi

# ===================== PAYLOAD-SIZE BOUNDARY (regression) ====================
# Guards the here-string deadlock. Bash delivers `<<<` through a pipe it fills
# ITSELF before the reader is exec'd, and it appends a newline — so a payload of
# 65536-65663 bytes puts the write 1-128 bytes past the 65536-byte pipe capacity
# and bash blocks FOREVER. At >=129 bytes over, bash spills to a temp file, so
# the window is closed on BOTH sides: 65535 and 65664 always worked and only the
# band between them hung. That shape is why no ordinary size ever caught it.
#
# Measured against the pre-fix hook on Git Bash: a 65536-byte payload carrying a
# live-shape AWS access-key id returned NO verdict at a 200s bound, where the
# same token in a small payload exits 2 immediately. The hook is registered at
# `timeout: 60`, so in production the harness cancels the guard and the secret
# verdict is lost outright. Sibling fix for the same class in hook-utils.sh's
# JSON path: #1587.
#
# The payload is PIPED here, never `bash "$HOOK" <<<"$json"` — a here-string
# would hang THIS FILE at exactly these sizes and read as the bug under test.

# Content of EXACTLY $1 bytes, ending in " $2" when $2 is given. jq reads the
# content on STDIN (`-Rs`): a 65KB `--arg` blows the Win32 32767-byte argv limit
# and jq would never run. The separating space matters for the sibling
# hardcoded-path suite, whose patterns require a left boundary; keeping one
# builder shape across both suites keeps them comparable.
size_filler() { head -c "$1" /dev/zero | tr '\0' b; }
sized_write_json() {
  local n="$1" tail="${2:-}"
  [[ -n "$tail" ]] && tail=" $tail"
  printf '%s%s' "$(size_filler $((n - ${#tail})))" "$tail" |
    MSYS_NO_PATHCONV=1 jq -Rs --arg fp "$FIXTURE" \
      '{tool_name:"Write",tool_input:{file_path:$fp,content:.}}'
}

# Bound every case so a regression FAILS LOUDLY instead of hanging CI. 150s is
# generous on purpose: the legitimate large-payload itemization measured 41-67s
# on Git Bash under Defender, while a deadlock never returns at any bound — so
# 150 separates the two without making the case flaky on a slow host.
run_bounded() {
  local rc=0
  printf '%s' "$1" | timeout 150 bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# Asserts the EXACT code, and names 124 as its own failure. A "non-zero means
# blocked" assertion would have ACCEPTED the hang and would not have caught this
# defect — the whole point is that no verdict is not a blocking verdict.
assert_bounded_exit() {
  if [[ "$3" == "124" ]]; then
    bad "$1: HUNG (exit 124 at the 150s bound) — here-string deadlock regression"
  elif [[ "$3" == "$2" ]]; then
    ok "$1 (exit $3)"
  else
    bad "$1: expected exit $2, got $3"
  fi
}

# Clean payloads across the window and both shoulders — exercises the combined
# fast-reject gate, which is the site that scans EVERY write.
for SZ in 65535 65536 65600 65663 65664; do
  assert_bounded_exit "boundary: clean ${SZ}-byte payload → exit 0" \
    0 "$(run_bounded "$(sized_write_json "$SZ")")"
done

# The security case: a REAL detectable secret sitting inside the hang window
# must still BLOCK. Pre-fix this exact payload produced no verdict at all.
# Two sizes: the exact pipe capacity, and mid-window. These also reach the
# per-pattern itemization (the second patched call site), which a clean payload
# never touches because the fast-reject returns first.
for SZ in 65536 65600; do
  assert_bounded_exit "boundary: AWS key in ${SZ}-byte payload → exit 2" \
    2 "$(run_bounded "$(sized_write_json "$SZ" "$AWS_TOKEN")")"
done

# Process substitution must not leak writer noise onto stderr. `grep -q`
# early-exits and SIGPIPEs the `printf` feeding it; stderr is this hook's
# user-facing channel, so a stray "write error: Broken pipe" would corrupt the
# blocked message.
BOUND_ERR=$(printf '%s' "$(sized_write_json 65600 "$AWS_TOKEN")" | timeout 150 bash "$HOOK" 2>&1 >/dev/null)
assert_contains "boundary: in-window block still reports the label" "$BOUND_ERR" "AWS Access Key"
assert_absent "boundary: no SIGPIPE noise on stderr" "$BOUND_ERR" "Broken pipe"

# Empty content. `<<<""` delivered ONE EMPTY LINE; `printf '%s' ""` delivers
# zero bytes. No pattern matches an empty line either way and the hook's own
# `[[ -n "$CONTENT" ]]` guard exits first — pinned so the substitution cannot
# quietly become a behavior change.
RC=0
printf '%s' "$(sized_write_json 0)" | timeout 30 bash "$HOOK" >/dev/null 2>&1 || RC=$?
assert_exit "boundary: empty content → exit 0" 0 "$RC"

report
