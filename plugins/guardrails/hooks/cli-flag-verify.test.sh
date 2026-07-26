#!/usr/bin/env bash
# Contract test for cli-flag-verify.sh (guardrails plugin).
#
# A PATH-stubbed `faketool` with controlled `--help` output exercises the
# subcommand-aware, code-span-scoped extraction deterministically — no
# dependence on any real CLI being installed. Self-contained.
#
# shellcheck disable=SC2016  # backticks / $ inside fixture strings are literal data

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/cli-flag-verify.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Extract the hook's additionalContext JSON and assert a substring is present.
ctx_contains() {
  local ctx
  ctx=$(printf '%s' "$2" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  assert_contains "$1" "$ctx" "$3"
}

# Fake CLI double: `--help` (always the verifier's last arg) prints top-level
# flags; when `sub` appears in the chain it also exposes the subcommand flag.
FAKE_BIN_DIR="$TEST_TMPDIR/fakebin"
mkdir -p "$FAKE_BIN_DIR"
cat >"$FAKE_BIN_DIR/faketool" <<'FAKE'
#!/usr/bin/env bash
last=""
for a in "$@"; do last="$a"; done
if [[ "$last" == "--help" ]]; then
  echo "Usage: faketool [subcmd] [options]"
  echo "  --toplevel    a real top-level flag"
  for a in "$@"; do
    [[ "$a" == "sub" ]] && echo "  --real        a real subcommand flag"
  done
  exit 0
fi
exit 0
FAKE
chmod +x "$FAKE_BIN_DIR/faketool"

# run_fake: invoke the hook with faketool as the only scanned bin and an
# isolated per-case verifier cache so a stale 24h --help cache never leaks.
# Models a Write: the content goes into the payload's `content` (what the hook
# now scans) AND to disk (so the file existence + extension checks pass). Keeping
# disk == payload means the pre-fix hook — which read the file — scans the same
# bytes, so this conversion is behavior-preserving and every existing case stays
# green across the diff-scope fix.
run_fake() {
  local content="$1" ext="${2:-sh}"
  local case_dir="$TEST_TMPDIR/fake-$((PASS + FAIL + 1))"
  mkdir -p "$case_dir/cache"
  local target="$case_dir/target.$ext"
  printf '%s\n' "$content" >"$target"
  PATH="$FAKE_BIN_DIR:$PATH" \
    CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
    LOCALAPPDATA="$case_dir/cache" \
    XDG_CACHE_HOME="$case_dir/cache" \
    bash "$HOOK" <<<"$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$target" --arg c "$content" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')" 2>&1
}

# run_edit <disk-body> <new-hunk> [ext]: models an Edit — the file on disk
# carries <disk-body> (pre-existing lines), the payload's new_string is the
# changed hunk. The hook must scan ONLY the hunk, never the disk body. Isolates
# the diff-scope contract: disk and payload deliberately differ.
run_edit() {
  local disk="$1" hunk="$2" ext="${3:-sh}"
  local case_dir="$TEST_TMPDIR/edit-$((PASS + FAIL + 1))"
  mkdir -p "$case_dir/cache"
  local target="$case_dir/target.$ext"
  printf '%s\n' "$disk" >"$target"
  PATH="$FAKE_BIN_DIR:$PATH" \
    CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
    LOCALAPPDATA="$case_dir/cache" \
    XDG_CACHE_HOME="$case_dir/cache" \
    bash "$HOOK" <<<"$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$target" --arg s "$hunk" '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s}}')" 2>&1
}

OUT=$(run_fake 'faketool sub --real'); RC=$?
assert_exit "subcmd real flag → exit 0" 0 "$RC"
assert_silent "subcmd real flag → no output" "$OUT"

OUT=$(run_fake 'faketool sub --fake'); RC=$?
assert_exit "subcmd fake flag → exit 0" 0 "$RC"
ctx_contains "subcmd fake flag → UNKNOWN_FLAG w/ chain" "$OUT" "UNKNOWN_FLAG: faketool sub --fake"

OUT=$(run_fake 'faketool --toplevel'); RC=$?
assert_exit "top-level real flag → exit 0" 0 "$RC"

OUT=$(run_fake 'faketool --bogus'); RC=$?
assert_exit "top-level fake flag → exit 0" 0 "$RC"
ctx_contains "top-level fake flag → UNKNOWN_FLAG no chain" "$OUT" "UNKNOWN_FLAG: faketool --bogus"

OUT=$(run_fake 'echo hi && faketool sub --real | cat'); RC=$?
assert_exit "subcmd flag after && / before | → exit 0" 0 "$RC"

OUT=$(run_fake 'faketool -x sub --real'); RC=$?
assert_exit "short opt before subcmd → chain preserved → exit 0" 0 "$RC"

OUT=$(run_fake 'FOO=bar faketool sub --real'); RC=$?
assert_exit "env-assignment prefix stripped → exit 0" 0 "$RC"

OUT=$(run_fake 'faketool sub --real img faketool other --bogusflag'); RC=$?
assert_exit "nested second-bin flag not paired → exit 0" 0 "$RC"
assert_absent "nested second-bin flag → no inner FP" "$OUT" "bogusflag"

OUT=$(run_fake 'Run `faketool sub --real` then note the `--orphanflag` elsewhere.' md); RC=$?
assert_exit "cross-span flag not paired → exit 0" 0 "$RC"
assert_absent "cross-span flag → no orphan FP" "$OUT" "orphanflag"

OUT=$(run_fake 'The faketool --bogus flag is discussed only in prose here.' md); RC=$?
assert_exit "prose flag (no code span) → exit 0" 0 "$RC"

OUT=$(run_fake "$(printf '%s\n%s\n%s\n' '```bash' 'faketool sub --fake' '```')" md); RC=$?
assert_exit "fenced block fake flag → exit 0" 0 "$RC"
ctx_contains "fenced block fake flag → reported" "$OUT" "UNKNOWN_FLAG: faketool sub --fake"

OUT=$(run_fake "$(printf '%s\n%s\n%s\n' '```bash' '# faketool sub --fake' '```')" md); RC=$?
assert_exit "fenced comment line → exit 0" 0 "$RC"

OUT=$(run_fake '| faketool sub --fake | hallucinated |' md); RC=$?
assert_exit "table cell no-backtick → exit 0" 0 "$RC"

OUT=$(run_fake '| `faketool sub --fake` | hallucinated |' md); RC=$?
assert_exit "table cell w/ backticks fake flag → exit 0" 0 "$RC"
ctx_contains "table cell w/ backticks → reported" "$OUT" "UNKNOWN_FLAG: faketool sub --fake"

OUT=$(run_fake 'the `faketool` directory holds --bogus notes' md); RC=$?
assert_exit "bin as non-command word → exit 0" 0 "$RC"

OUT=$(run_fake "$(printf '%s\n%s\n' '# example: faketool sub --fake' 'faketool sub --real')"); RC=$?
assert_exit "shell comment line skipped → exit 0" 0 "$RC"

OUT=$(run_fake 'faketool sub --help'); RC=$?
assert_exit "--help universally skipped → exit 0" 0 "$RC"
OUT=$(run_fake 'faketool --version'); RC=$?
assert_exit "--version universally skipped → exit 0" 0 "$RC"

OUT=$(run_fake 'faketool sub --fake' cs); RC=$?
assert_exit "non-target ext (.cs) → exit 0" 0 "$RC"

# ======================= DIFF-SCOPE (edit hunk only) =======================
# An Edit must verify only its changed hunk, never the whole file on disk. Repro
# shape: a file already carrying an unknown flag, edited elsewhere with a clean
# hunk, must stay quiet — the pre-fix whole-file scan re-flagged the untouched
# line on every unrelated edit.
OUT=$(run_edit 'faketool sub --fake' 'faketool sub --real'); RC=$?
assert_exit "diff-scope: unknown flag on disk, clean hunk → exit 0" 0 "$RC"
assert_silent "diff-scope: pre-existing flag outside the hunk not re-flagged" "$OUT"

# Counterpart MUST-fire: an unknown flag introduced BY the edit's hunk fires.
OUT=$(run_edit 'faketool sub --real' 'faketool sub --fake'); RC=$?
assert_exit "diff-scope: unknown flag in the hunk → exit 0" 0 "$RC"
ctx_contains "diff-scope: hunk flag reported" "$OUT" "UNKNOWN_FLAG: faketool sub --fake"

# --------------- PARTIAL-REPLACEMENT (bare-flag hunk reconstruction) ---------
# An Edit whose new_string is ONLY the swapped-in flag carries no binary or
# subcommand, so the hunk yields no command candidate and a genuinely-introduced
# unknown flag would be missed. The disk lines model POST-edit state (PostToolUse
# runs after the edit applies), so the flag token is already on disk. Bounded
# context reconstruction pulls the on-disk line carrying the hunk's flag token
# and scans it. MUST-FIRE: fails against the pre-fix hook, passes after.
OUT=$(run_edit 'faketool sub --fake' '--fake'); RC=$?
assert_exit "partial-edit: bare-flag hunk reconstructs context → exit 0" 0 "$RC"
ctx_contains "partial-edit: reconstructed hunk flag reported" "$OUT" "UNKNOWN_FLAG: faketool sub --fake"

# MUST-STAY-QUIET: the same bare-flag shape where the disk line ALSO carries a
# different pre-existing unknown flag NOT in new_string. Reconstruction keeps
# only candidates whose flag appears in the hunk, so the unrelated --otherbogus
# never re-fires — the diff-scope contract holds through reconstruction.
OUT=$(run_edit 'faketool sub --real --otherbogus' '--real'); RC=$?
assert_exit "partial-edit: unrelated pre-existing flag not re-fired → exit 0" 0 "$RC"
assert_silent "partial-edit: only hunk-flag verified, --otherbogus stays quiet" "$OUT"

# Kill switch — disabled path is a clean no-op despite a hallucinated flag.
dis_dir="$TEST_TMPDIR/fake-disabled"
mkdir -p "$dis_dir/cache"
printf 'faketool sub --fake\n' >"$dis_dir/target.sh"
dis_input=$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$dis_dir/target.sh" --arg c 'faketool sub --fake' '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')
OUT=$(PATH="$FAKE_BIN_DIR:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
  LOCALAPPDATA="$dis_dir/cache" XDG_CACHE_HOME="$dis_dir/cache" \
  CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_ENABLED=false bash "$HOOK" <<<"$dis_input" 2>&1); RC=$?
assert_exit "disabled via env → exit 0" 0 "$RC"
assert_silent "disabled via env → no output" "$OUT"

OUT=$(PATH="$FAKE_BIN_DIR:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
  LOCALAPPDATA="$dis_dir/cache" XDG_CACHE_HOME="$dis_dir/cache" \
  CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS=faketool bash "$HOOK" <<<"$dis_input" 2>&1); RC=$?
assert_exit "per-binary skip → exit 0" 0 "$RC"

# Empty stdin: hook::buffer_stdin returns 1 (no payload) → this advisory hook
# skips silently. Guards the skip contract through the migrated buffered-read
# path. NOTE: a here-string / /dev/null cannot reproduce the Win32
# late-EOF pipe stall the fix targets, and rc-2 (timeout) collapses to the same
# silent exit 0 as rc-1 for an advisory hook — so this asserts the skip contract,
# not the stall itself.
OUT=$(PATH="$FAKE_BIN_DIR:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
  bash "$HOOK" </dev/null 2>&1); RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

# Bundled verifier missing (docs/conventions/hook-observability/): a fake
# CLAUDE_PLUGIN_ROOT with no lib/verification/verify-cli-flag.sh reproduces
# install corruption. CLAUDE_PLUGIN_DATA isolated to a fresh dir per case
# (hook::notice_once persists a marker there; an unisolated real machine path
# would make this pass only on the first-ever run).
noverif_root="$TEST_TMPDIR/no-verifier-root"
mkdir -p "$noverif_root/hooks"
cp "$HOOK" "$noverif_root/hooks/cli-flag-verify.sh"
cp "$HOOK_DIR/hook-utils.sh" "$noverif_root/hooks/hook-utils.sh"
noverif_data="$TEST_TMPDIR/no-verifier-data"; mkdir -p "$noverif_data"
noverif_input=$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$dis_dir/target.sh" --arg c 'faketool sub --fake' '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')
OUT=$(PATH="$FAKE_BIN_DIR:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
  CLAUDE_PLUGIN_ROOT="$noverif_root" CLAUDE_PLUGIN_DATA="$noverif_data" \
  bash "$noverif_root/hooks/cli-flag-verify.sh" <<<"$noverif_input" 2>&1); RC=$?
assert_exit "bundled verifier missing → exit 0 (fail open)" 0 "$RC"
assert_contains "bundled verifier missing → visible advisory (additionalContext)" "$OUT" \
  "bundled verifier missing"
assert_contains "bundled verifier missing → visible advisory (systemMessage)" \
  "$(jq -r '.systemMessage // empty' <<<"$OUT" 2>/dev/null)" \
  "bundled verifier missing"

# ============================ TELEMETRY ====================================
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
tel_dir="$TEST_TMPDIR/fake-tel"
mkdir -p "$tel_dir/cache"
printf 'faketool sub --fake\n' >"$tel_dir/target.sh"
tel_input=$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$tel_dir/target.sh" --arg c 'faketool sub --fake' '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}')
PATH="$FAKE_BIN_DIR:$PATH" CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS=faketool \
  LOCALAPPDATA="$tel_dir/cache" XDG_CACHE_HOME="$tel_dir/cache" \
  HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" <<<"$tel_input" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "cli-flag-verify"
  assert_contains "telemetry: status ok" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the flag" "$(jq -r '.data.findings[]' "$TEL")" "faketool sub --fake"
else
  bad "telemetry: no envelope written"
fi

# ================= VERIFIER OPTION PARSING (positional guard) ===============
# Verifier options are recognized only before <bin>; a TARGET flag spelled
# --quiet/--verbose must be verified as a positional, not consumed (the old
# whole-argv scan returned rc 3 and the hook silently skipped those flags).
VERIFIER="$HOOK_DIR/../lib/verification/verify-cli-flag.sh"
opt_dir="$TEST_TMPDIR/verifier-opts"
mkdir -p "$opt_dir/cache"
run_verifier() {
  PATH="$FAKE_BIN_DIR:$PATH" LOCALAPPDATA="$opt_dir/cache" \
    XDG_CACHE_HOME="$opt_dir/cache" bash "$VERIFIER" "$@" >/dev/null 2>&1
}
run_verifier --quiet faketool --toplevel
assert_exit "verifier: leading --quiet still parsed as option" 0 $?
run_verifier --quiet faketool --verbose
assert_exit "verifier: target --verbose verified, not consumed (absent -> 1)" 1 $?
run_verifier --quiet faketool --quiet
assert_exit "verifier: target --quiet verified, not consumed (absent -> 1)" 1 $?

report
