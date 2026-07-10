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
OUT=$(HOOK_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "x='$AWS_TOKEN'")" 2>&1); RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"

# --- jq fail-open visibility (finding P4) -----------------------------------
# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils (their DLLs / PATH) across Git Bash and Linux.
# Assert the fail-open guard (visible notice, no silent disable) is present in
# the hook source; the runtime path itself is a trivial `command -v jq` short.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: command -v jq check present" "$HOOK_SRC" 'command -v jq'
assert_contains "jq guard: visible stderr notice" "$HOOK_SRC" 'jq not found on PATH'
assert_contains "jq guard: fail-open exit 0" "$HOOK_SRC" 'guard disabled'

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
TEL="$(mktemp -p "$TEST_TMPDIR")"
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
TELR="$(mktemp -p "$TEST_TMPDIR")"
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

report
