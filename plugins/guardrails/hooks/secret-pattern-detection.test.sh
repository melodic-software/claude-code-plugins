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
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "AWS Access Key → exit 2" 2 "$RC"
assert_contains "AWS → message" "$OUT" "AWS Access Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "GitHub PAT → exit 2" 2 "$RC"
assert_contains "GH PAT → message" "$OUT" "GitHub PAT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "SLACK='$SLACK_TOKEN'")" 2>&1)
RC=$?
assert_exit "Slack Bot Token → exit 2" 2 "$RC"
assert_contains "Slack → message" "$OUT" "Slack Bot Token"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "STRIPE_KEY='$STRIPE_TOKEN'")" 2>&1)
RC=$?
assert_exit "Stripe Key → exit 2" 2 "$RC"
assert_contains "Stripe → message" "$OUT" "Stripe Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "OPENAI_KEY='$OPENAI_BARE_KEY'")" 2>&1)
RC=$?
assert_exit "OpenAI bare sk- key → exit 2" 2 "$RC"
assert_contains "OpenAI bare sk- → message" "$OUT" "OpenAI API Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "$PEM_HEADER")" 2>&1)
RC=$?
assert_exit "PEM private key → exit 2" 2 "$RC"
assert_contains "PEM → message" "$OUT" "Private Key (PEM)"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "old to '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "secret = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

# A content string may legitimately encode a NUL, and the payload fields are read
# NUL-separated. hook::jq_fields strips NUL jq-side so the delimiter cannot
# collide with content; without that the field count came back wrong, this hook's
# `|| exit 0` skipped detection entirely, and a credential placed AFTER the NUL
# passed unblocked. Built with jq (`[0] | implode`) so no literal escape sequence
# for the byte appears in this file's source.
NUL_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$FIXTURE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:("harmless first line" + ([0] | implode) + "config = " + $tok)}}')
OUT=$(bash "$HOOK" <<<"$NUL_PAYLOAD" 2>&1)
RC=$?
assert_exit "secret AFTER a NUL byte in content → exit 2" 2 "$RC"
assert_contains "secret after NUL → NUL refusal message" "$OUT" "NUL byte"

# In-project secret still blocks when CLAUDE_PROJECT_DIR is set (file under root).
OUT=$(CLAUDE_PROJECT_DIR="/repo" bash "$HOOK" <<<"$(write_json "/repo/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "in-project secret with PROJECT_DIR set → exit 2" 2 "$RC"
assert_contains "in-project secret → message" "$OUT" "AWS Access Key"

# Trailing slash on CLAUDE_PROJECT_DIR must not skip in-project scans.
OUT=$(CLAUDE_PROJECT_DIR="/repo/" bash "$HOOK" <<<"$(write_json "/repo/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "trailing-slash PROJECT_DIR still scans in-project file → exit 2" 2 "$RC"

# ============================ ALLOW (exit 0) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'just some normal code here')" 2>&1)
RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'api_key=mySecretValue123')" 2>&1)
RC=$?
assert_exit "low-confidence generic pattern → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1)
RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.env.example" "API_KEY='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".env.example allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/tests/fixtures/secrets.txt" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "tests/fixtures/ allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.claude/hooks/foo.sh" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/settings.local.json" "{\"k\":\"$AWS_TOKEN\"}")" 2>&1)
RC=$?
assert_exit "settings.local.json allowlist → exit 0" 0 "$RC"

# CLAUDE.local.md allowlist must match case-sensitively even under the Windows
# path fold (regression: the fold lower-cases the membership path only).
OUT=$(run_hook_windows "$(write_json "C:/repo/CLAUDE.local.md" "token='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "CLAUDE.local.md allowlist (case-sensitive) → exit 0" 0 "$RC"

# Secret in a file OUTSIDE the project root → exit 0, silent.
OUT=$(CLAUDE_PROJECT_DIR="/repo" bash "$HOOK" <<<"$(write_json "/other-repo/fixtures/bad/leak.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "file outside project root → exit 0" 0 "$RC"
assert_silent "outside project root → no stderr" "$OUT"

# Kill switch — disabled path is a clean no-op even on a real-shape token.
OUT=$(CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
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
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/src/node_modules/pkg/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "node_modules real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/evil_node_modules/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "evil_node_modules substring → exit 2 (scanned)" 2 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv/lib/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".venv real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv-backup/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
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

# --- Telemetry path: the hoisted helper, not a hand-rolled prefix strip ------
# This hook kept its own copy of the repo-relative computation after the helper
# was hoisted into hook-utils.sh, and the copy's redaction knew only two of the
# three absolute spellings. Pin the helper so a third copy cannot reappear.
assert_contains "path helper: uses hook::repo_relative_path" "$HOOK_SRC" 'hook::repo_relative_path'
assert_absent "path helper: no hand-rolled prefix strip" "$HOOK_SRC" '_fwd#'

# Telemetry path helper fixtures. A file_path is read as a string, but the
# no-project-dir cases resolve a root from the file's own checkout, so these
# need to exist on disk. Anchor on the toplevel git reports rather than on
# mktemp's answer: on macOS mktemp hands back /var/... where git reports
# /private/var/..., and the prefix strip would fail for the wrong reason.
PATHREPO="$TEST_TMPDIR/pathrepo"
mkdir -p "$PATHREPO/src"
git -C "$PATHREPO" init -q
PATHREPO_TL="$(git -C "$PATHREPO" rev-parse --show-toplevel)"

# telemetry_file <file_path> -> data.file from the envelope this hook emits.
# CLAUDE_PROJECT_DIR stays unset (the file scope guard above falls through
# rather than skipping when there is no project, so the hook still scans).
telemetry_file() {
  local tel sink
  tel="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
  sink="$(make_sink "cat >\"$tel\"")"
  env HOOK_TELEMETRY_SINK="$sink" bash "$HOOK" \
    <<<"$(write_json "$1" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
  if wait_for_sink "$tel"; then jq -r '.data.file' "$tel"; else printf '<no-envelope>'; fi
}

# --- UNC file_path with no project dir: the leak --------------------------
# A Windows UNC path is neither POSIX-absolute nor drive-lettered, so a
# redaction that tests only those two spellings passes the WHOLE share path
# through — server name and all — into the envelope. The share host is exactly
# the kind of internal name telemetry must not carry.
UNC_HOST='srv'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
UNC_FILE="${BS}${BS}${UNC_HOST}${BS}share${BS}secrets.env"
# Equality, not containment: the leaked path ENDS in the basename, so a
# containment check passes against the pre-fix hook for the wrong reason.
df=$(telemetry_file "$UNC_FILE")
assert_eq "UNC/no-project: data.file is exactly the basename" "secrets.env" "$df"
assert_absent "UNC/no-project: data.file keeps no backslash" "$df" "$BS"
assert_absent "UNC/no-project: data.file drops the share host" "$df" "$UNC_HOST"

# --- Ordinary in-repo file with no project dir ------------------------------
# With no project dir the hand-rolled copy resolved no root at all, so every
# in-repo path degraded to a bare basename and the envelope lost the location
# the schema asks for. The helper is paired with hook::repo_root, which answers
# from the file's own checkout.
df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "in-repo/no-project: data.file is repo-relative" "$df" "src/config.env"
assert_absent "in-repo/no-project: data.file is not absolute" "$df" "$PATHREPO_TL"

# --- Root-level file_path with no project dir --------------------------------
# The file's directory comes from parameter expansion. For `/secrets.env` the
# shortest `/*` suffix is the whole string, so a bare `${FILE%/*}` is EMPTY, and
# hook::repo_root's `${1:-.}` would then anchor on the process CWD instead of
# `/` as `dirname` did. The anchor is proven through a `git` shim ahead of the
# real one on PATH that records every `-C` argument: the hook must ask git
# about `/`, and the envelope must still redact to the basename.
GIT_SHIM_DIR="$TEST_TMPDIR/git-shim"
mkdir -p "$GIT_SHIM_DIR"
GIT_C_LOG="$TEST_TMPDIR/git-c-args"
REAL_GIT="$(command -v git)"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # the shim's own expansions are literal source text
  printf 'if [[ "${1:-}" == "-C" ]]; then printf "%%s\\n" "${2:-}" >>"%s"; fi\n' "$GIT_C_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_GIT"
} >"$GIT_SHIM_DIR/git"
chmod +x "$GIT_SHIM_DIR/git"
: >"$GIT_C_LOG"
ROOT_TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
ROOT_SINK="$(make_sink "cat >\"$ROOT_TEL\"")"
env PATH="$GIT_SHIM_DIR:$PATH" HOOK_TELEMETRY_SINK="$ROOT_SINK" bash "$HOOK" \
  <<<"$(write_json "/secrets.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1
assert_exit "root-level/no-project: still blocks" 2 "$?"
if wait_for_sink "$ROOT_TEL"; then
  assert_eq "root-level/no-project: data.file is exactly the basename" \
    "secrets.env" "$(jq -r '.data.file' "$ROOT_TEL")"
else
  bad "root-level/no-project: no envelope written"
fi
# Exactly one `git -C` and its argument is `/`: neither `.` nor the empty
# string the bare expansion produced.
assert_eq "root-level/no-project: repo root is anchored on / (dirname semantics)" \
  "/" "$(cat "$GIT_C_LOG")"

# --- Symlinked checkout ------------------------------------------------------
# A real repo plus a symlink to it. Reached through the symlink, `git rev-parse
# --show-toplevel` answers with the PHYSICAL path, so a file_path arriving in
# the symlink spelling cannot be prefix-stripped by the root the helper is
# handed. Both spellings are pinned: the physical one must still come back
# repo-relative, and the symlink one must degrade to a basename rather than
# leak the resolved physical path the fallback just computed.
LINKREPO="$TEST_TMPDIR/linkrepo"
ln -s "$PATHREPO_TL" "$LINKREPO"
df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "symlinked repo, physical spelling: repo-relative" "$df" "src/config.env"
df=$(telemetry_file "$LINKREPO/src/config.env")
assert_contains "symlinked repo, symlink spelling: basename" "$df" "config.env"
assert_absent "symlinked repo, symlink spelling: no path separator" "$df" "/"

# --- Trailing-slash project dir ---------------------------------------------
# The helper strips "$root/", so a root already ending in a separator makes the
# prefix "/repo//" and matches nothing: every in-project file would collapse to
# its basename and the envelope would lose the location. A trailing slash is a
# supported spelling of CLAUDE_PROJECT_DIR (the scope test above uses one), and
# the hand-rolled copy this replaced trimmed it, so the trim has to survive the
# move to the helper.
TELTS="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKTS="$(make_sink "cat >\"$TELTS\"")"
env HOOK_TELEMETRY_SINK="$SINKTS" CLAUDE_PROJECT_DIR="$PATHREPO_TL/" bash "$HOOK" \
  <<<"$(write_json "$PATHREPO_TL/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELTS"; then
  assert_eq "trailing-slash project dir: data.file stays repo-relative" \
    "src/config.env" "$(jq -r '.data.file' "$TELTS")"
else
  bad "trailing-slash project dir: no envelope written"
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

# ==================== GitHub MCP write lane (#3719) ==========================
# A Write|Edit matcher does not see a write issued through an MCP tool, so this
# guard could be cleared on a session that pushed the same secret to GitHub by
# another route. One case per PAYLOAD SHAPE, because the two tools carry content
# differently and a scanner that only understood one would silently pass the
# other.
#
#   mcp__github__create_or_update_file — .tool_input.path + .tool_input.content
#   mcp__github__push_files            — .tool_input.files[] of {path, content}
#   mcp__github__delete_file           — NO content field at all
mcp_single_json() {
  jq -n --arg p "$1" --arg c "$2" \
    '{tool_name:"mcp__github__create_or_update_file",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",path:$p,content:$c}}'
}
# mcp_push_json <path> <content> [<path> <content> ...]
mcp_push_json() {
  local args=() n=0
  while (($#)); do
    args+=(--arg "p$n" "$1" --arg "c$n" "$2")
    shift 2
    n=$((n + 1))
  done
  # One --arg pair per file, and an index-built object list, so the payload's
  # shape is the tool schema's rather than a string-interpolated approximation.
  local filter='{tool_name:"mcp__github__push_files",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",files:['
  local i
  for ((i = 0; i < n; i++)); do
    ((i)) && filter+=','
    filter+='{path:$p'"$i"',content:$c'"$i"'}'
  done
  filter+=']}}'
  jq -n "${args[@]}" "$filter"
}

# --- create_or_update_file: the single-file shape
RC=0
bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "import os")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP create_or_update_file: clean content → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "MCP create_or_update_file: secret → exit 2" 2 "$RC"
assert_contains "MCP create_or_update_file: names the pattern" "$OUT" "GitHub PAT"
assert_contains "MCP create_or_update_file: names the repo path" "$OUT" "src/app.py"
assert_contains "MCP create_or_update_file: says there is no local file to fix" "$OUT" "goes straight to a repository"

# --- push_files: the multi-file shape, and the LAST file must be reached
RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "y = 2")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: all clean → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "k = '$AWS_TOKEN'" "b.py" "y = 2")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the FIRST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: first-file block names its path" "$OUT" "a.py"

# The loop must not stop at the first clean file: a guard that checked only
# files[0] would pass this and read as covered.
OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "k = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: last-file block names its path" "$OUT" "b.py"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","files":[]}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: empty files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: absent files array → exit 0" 0 "$RC"

# --- delete_file carries no content, so there is nothing to scan
RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__delete_file","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","path":"src/app.py"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP delete_file: no content to scan → exit 0" 0 "$RC"

# --- the allowlist is the SAME list, asked of a repo-relative path
RC=0
bash "$HOOK" <<<"$(mcp_single_json "docs/.env.example" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted .env.example is exempt" 0 "$RC"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "tests/fixtures/keys.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted test fixture is exempt" 0 "$RC"
# A directory that merely CONTAINS an allowlisted name is not allowlisted.
RC=0
bash "$HOOK" <<<"$(mcp_push_json "evil_node_modules/x.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a name-prefix sibling of an allowlisted dir still blocks" 2 "$RC"

# --- the local-project scope guard must NOT be applied to a remote write
# A repo-relative path is never under CLAUDE_PROJECT_DIR, so reusing the local
# scope test here would skip every MCP write. Pinned with the variable SET,
# which is the state that would trigger it.
RC=0
CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a set CLAUDE_PROJECT_DIR does not skip the remote write" 2 "$RC"

# --- the kill switch still governs the whole guard, MCP lane included
RC=0
CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: disabled guard allows the write" 0 "$RC"

report
