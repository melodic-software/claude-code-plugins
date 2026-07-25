#!/usr/bin/env bash
# Contract test for asserted-path-verify.sh (guardrails plugin).
#
# Black-box subprocess invocation. Each case builds a real git working tree so
# hook::repo_root resolves, then feeds a PostToolUse Write|Edit payload on stdin.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/asserted-path-verify.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Neutralize ambient CLAUDE_PROJECT_DIR; cases that need scoping set it.
unset CLAUDE_PROJECT_DIR

# A working tree with docs/ and plugins/ present and one real file in each, so
# the first-segment gate has both a hit and a miss to distinguish.
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/docs" "$REPO/plugins/guardrails"
git -C "$REPO" init -q
: >"$REPO/docs/real.md"
: >"$REPO/plugins/guardrails/README.md"
TARGET="$REPO/notes.md"
: >"$TARGET"

RC=0

# run <content> -> hook stdout+stderr; sets RC.
run() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}
# run_edit <new_string> -> same, as an Edit payload.
run_edit() {
  local out
  out=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$TARGET" "$1")" 2>&1)
  RC=$?
  printf '%s' "$out"
}

# ============================ MUST FIRE =====================================

OUT=$(run 'Read `docs/nope.md` before starting.')
assert_exit "missing path in code span → exit 0 (advisory)" 0 "$RC"
assert_contains "missing path → named" "$OUT" "MISSING_PATH: docs/nope.md"

OUT=$(run 'See [the guide](docs/gone.md) for details.')
assert_contains "missing path in markdown link target → named" "$OUT" "MISSING_PATH: docs/gone.md"

OUT=$(run 'Both `docs/nope.md` and `plugins/guardrails/absent.sh` are wrong.')
assert_contains "two missing paths → count" "$OUT" "2 asserted path(s) do not exist"
assert_contains "two missing paths → second named" "$OUT" "MISSING_PATH: plugins/guardrails/absent.sh"

OUT=$(run 'Deep miss at `plugins/guardrails/hooks/nope.sh`.')
assert_contains "nested missing path under a real first segment → named" "$OUT" \
  "MISSING_PATH: plugins/guardrails/hooks/nope.sh"

OUT=$(run_edit 'Now cites `docs/vanished.md` instead.')
assert_contains "Edit hunk scanned via new_string" "$OUT" "MISSING_PATH: docs/vanished.md"

# A line-citation suffix on a MISSING file still fires — the suffix is stripped
# for resolution, so the finding names the path without it.
OUT=$(run 'Per `docs/nope.md:120-125` the rule applies.')
assert_contains "line-range suffix on a missing path → still fires" "$OUT" \
  "MISSING_PATH: docs/nope.md"

# ============================ MUST STAY QUIET ===============================

OUT=$(run 'Read `docs/real.md` before starting.')
assert_exit "existing path → exit 0" 0 "$RC"
assert_silent "existing path → silent" "$OUT"

# Line and range citations are this repo's dominant citation form; stripping the
# suffix is what keeps them quiet.
OUT=$(run 'Per `docs/real.md:42` and `docs/real.md:576-580` the rule applies.')
assert_silent "line and range citation suffixes stripped → silent" "$OUT"

OUT=$(run 'An anchor cite: `docs/real.md#section-two`.')
assert_silent "anchor fragment stripped → silent" "$OUT"

# FIRST-SEGMENT GATE: the leading directory is not in this repo, so the token is
# not this repo's to adjudicate.
OUT=$(run 'Upstream lives at `some-other-project/src/main.rs`.')
assert_silent "first segment absent → not adjudicated" "$OUT"

OUT=$(run 'Glob it with `plugins/*/SKILL.md` or `docs/**/*.md`.')
assert_silent "glob patterns → silent" "$OUT"

OUT=$(run 'Placeholders like `plugins/<name>/plugin.json` and `docs/${topic}/PLAN.md`.')
assert_silent "placeholder metacharacters → silent" "$OUT"

OUT=$(run 'Truncated as `docs/.../PLAN.md`.')
assert_silent "ellipsis stand-in → silent" "$OUT"

OUT=$(run 'Fetch <https://example.com/docs/nope.md> and [x](https://a.test/docs/gone.md).')
assert_silent "URLs → silent" "$OUT"

OUT=$(run 'Absolute paths `/etc/hosts` and `C:/Windows/system32/x.dll`.')
assert_silent "absolute paths → silent (hardcoded-path-check owns those)" "$OUT"

OUT=$(run 'User config at `~/.claude/settings.json`.')
assert_silent "home-relative → silent" "$OUT"

OUT=$(run 'Parent escape `../docs/nope.md` and `docs/../plugins/nope.sh`.')
assert_silent "parent-escaping paths → silent" "$OUT"

OUT=$(run 'Bare directory refs `plugins/guardrails` and `a/b` carry no extension.')
assert_silent "extensionless non-slash-terminated refs → silent (ambiguous)" "$OUT"

OUT=$(run 'Trailing slash marks a directory: `docs/` and `plugins/guardrails/`.')
assert_silent "existing directories with trailing slash → silent" "$OUT"

OUT=$(run 'Vendor trees `node_modules/pkg/index.js` and `.git/config` prove nothing.')
assert_silent "vendor and git trees → silent" "$OUT"

OUT=$(run 'Prose mentioning docs/nope.md outside any code span or link.')
assert_silent "unquoted prose path → not scanned" "$OUT"

OUT=$(run 'A whole command: `cp docs/nope.md docs/other.md`.')
assert_silent "multi-token code span → not a path candidate" "$OUT"

# Non-markdown files are out of scope: a path literal in a script resolves
# against the runtime CWD, not the repo root.
SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$SCRIPT" 'cat docs/nope.md')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"

# A tool other than Write|Edit carries nothing this call wrote.
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(notebook_json "$TARGET" 'docs/nope.md')" 2>&1)
RC=$?
assert_exit "NotebookEdit payload → exit 0" 0 "$RC"
assert_silent "NotebookEdit payload → silent" "$OUT"

# A file outside CLAUDE_PROJECT_DIR is not policed.
OUTSIDE="$TEST_TMPDIR/outside.md"
: >"$OUTSIDE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "file outside project dir → exit 0" 0 "$RC"
assert_silent "file outside project dir → silent" "$OUT"

# Non-git directory: hook::repo_root cannot resolve a working-tree top and falls
# back to the hint (the written file's own directory). The first-segment gate is
# then evaluated against that directory, so a repo-shaped citation with no
# matching child stays quiet rather than being adjudicated against a root that is
# not one. Pins the fallback so a future repo_root change cannot silently turn
# this into a false-positive source.
NOGIT="$TEST_TMPDIR/nogit"
mkdir -p "$NOGIT"
NOGIT_TARGET="$NOGIT/notes.md"
: >"$NOGIT_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$NOGIT" bash "$HOOK" <<<"$(write_json "$NOGIT_TARGET" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "non-git directory → exit 0" 0 "$RC"
assert_silent "non-git directory → silent (first-segment gate closes)" "$OUT"

# Same non-git directory, but the cited first segment DOES exist there. The gate
# opens and the guard adjudicates against the fallback root — documenting that the
# fallback is a real adjudication path, not a dead branch.
mkdir -p "$NOGIT/docs"
OUT=$(CLAUDE_PROJECT_DIR="$NOGIT" bash "$HOOK" <<<"$(write_json "$NOGIT_TARGET" 'Read `docs/nope.md`.')" 2>&1)
assert_contains "non-git fallback root with a matching first segment → adjudicates" "$OUT" \
  "MISSING_PATH: docs/nope.md"

# ============================ KILL SWITCH ===================================

OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_ASSERTED_PATH_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"

# ============================ EMPTY STDIN ===================================

# hook::buffer_stdin returns 1 (no payload) → this advisory hook skips silently.
# A here-string cannot reproduce the Win32 late-EOF pipe stall, and rc-2
# (timeout) collapses to the same silent exit 0 for an advisory hook, so this
# asserts the skip contract, not the stall.
OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

# ============================ MISSING PREREQUISITE ==========================

# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils (their DLLs / PATH) across Git Bash and Linux, the
# same constraint secret-pattern-detection.test.sh and
# require-jq-notice-isolation.test.sh both document. Assert the fail-open guard is
# present via the shared helper, which composes the once-per-session notice_once
# gate with the dual-channel (systemMessage + additionalContext) notice;
# require_jq's own behavior is covered by lib/hook-utils.test.sh, and this hook's
# notice key is proven unique plugin-wide by require-jq-notice-isolation.test.sh,
# which discovers call sites by glob.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'
assert_contains "jq guard: hook-specific notice key" "$HOOK_SRC" 'guardrails-asserted-path-verify'

# The repo root is resolved from the written file, never from the process CWD, so
# the hook is correct in a linked worktree and in a bare-hub clone.
assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root "$(dirname "$FILE")"'

# ============================ TELEMETRY =====================================

TEL="$(mktemp -p "$TEST_TMPDIR")"
SINK="$(make_sink "cat >\"$TEL\"")"
CLAUDE_PROJECT_DIR="$REPO" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Read `docs/nope.md`.')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "asserted-path-verify"
  assert_contains "telemetry: status ok" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the path" "$(jq -r '.data.findings[]' "$TEL")" "docs/nope.md"
  assert_absent "telemetry: file path is repo-relative, never absolute" \
    "$(jq -r '.data.file' "$TEL")" "$TEST_TMPDIR"
else
  bad "telemetry: no envelope written"
fi

report
