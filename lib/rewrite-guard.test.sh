#!/usr/bin/env bash
# Unit tests for the content-mutation disclosure guard. Tests source the
# canonical lib/rewrite-guard.sh directly and drive its contract in isolation;
# each plugin's own <plugin>.test.sh keeps the black-box hook contract tests.
# Because CI enforces that every plugin copy is byte-identical to the source,
# passing here covers the copies too.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# Every case runs against an isolated TMPDIR so "the scratch area is empty"
# is a real assertion about THIS guard's snapshots, not ambient temp noise.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-guard-test-XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

scratch_count() {
  find "$TMPDIR" -type f 2>/dev/null | wc -l | tr -d '[:space:]'
}

# --- Source the libs under test ----------------------------------------------
# shellcheck source=hook-utils.sh
source "$LIB_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$LIB_DIR/rewrite-guard.sh"

target="$WORK/target.txt"

# --- begin snapshots into TMPDIR (non-vacuity probe for every count below) ---
printf 'one\n' >"$target"
hook::rewrite_guard_begin "$target"
if [[ "$(scratch_count)" == "1" ]]; then
  ok "begin creates exactly one snapshot in TMPDIR"
else
  fail "begin: expected 1 snapshot in TMPDIR, found $(scratch_count)"
fi

# --- unchanged file: empty message, snapshot released ------------------------
hook::rewrite_take_disclosure "$target" "msg-unchanged"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "take on unchanged file yields empty message"
else
  fail "take on unchanged file yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "take releases the snapshot (unchanged path)"
else
  fail "take left $(scratch_count) file(s) behind (unchanged path)"
fi
if [[ "$HOOK_REWRITE_CHANGED" == "false" ]]; then
  ok "take on unchanged file sets the changed verdict to false"
else
  fail "take on unchanged file set HOOK_REWRITE_CHANGED='$HOOK_REWRITE_CHANGED'"
fi

# --- changed file: message set, snapshot released ----------------------------
hook::rewrite_guard_begin "$target"
if [[ -z "$HOOK_REWRITE_CHANGED" ]]; then
  ok "begin resets the changed verdict to unknown"
else
  fail "begin left HOOK_REWRITE_CHANGED='$HOOK_REWRITE_CHANGED'"
fi
printf 'two\n' >"$target"
hook::rewrite_take_disclosure "$target" "msg-changed"
if [[ "$HOOK_REWRITE_MESSAGE" == "msg-changed" ]]; then
  ok "take on changed file yields the message"
else
  fail "take on changed file yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ "$HOOK_REWRITE_CHANGED" == "true" ]]; then
  ok "take on changed file sets the changed verdict to true"
else
  fail "take on changed file set HOOK_REWRITE_CHANGED='$HOOK_REWRITE_CHANGED'"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "take releases the snapshot (changed path)"
else
  fail "take left $(scratch_count) file(s) behind (changed path)"
fi

# --- destructive read: a second take resets the message ----------------------
hook::rewrite_take_disclosure "$target" "msg-again"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "second take resets the message (destructive read)"
else
  fail "second take yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ "$HOOK_REWRITE_CHANGED" == "true" ]]; then
  ok "second take keeps the first take's changed verdict"
else
  fail "second take reset HOOK_REWRITE_CHANGED to '$HOOK_REWRITE_CHANGED'"
fi

# --- take with no begin at all: nothing was attempted, so not changed --------
HOOK_REWRITE_CHANGED=""
hook::rewrite_take_disclosure "$target" "msg-never-armed"
if [[ -z "$HOOK_REWRITE_MESSAGE" && "$HOOK_REWRITE_CHANGED" == "false" ]]; then
  ok "take without begin yields empty message and a false verdict"
else
  fail "take without begin yielded message='$HOOK_REWRITE_MESSAGE' changed='$HOOK_REWRITE_CHANGED'"
fi

# --- exit without take: the EXIT trap releases the snapshot ------------------
# The #3401/#3405 leak class: an arm that exits without releasing. Run in a
# child bash so the exit is real.
printf 'three\n' >"$target"
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  hook::rewrite_guard_begin "$2"
  exit 0
' _ "$LIB_DIR" "$target"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "exit without take leaks no snapshot (EXIT trap)"
else
  fail "exit without take left $(scratch_count) file(s) behind"
fi

# ...including an arm that exits non-zero mid-flight.
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  hook::rewrite_guard_begin "$2"
  exit 4
' _ "$LIB_DIR" "$target"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "non-zero exit without take leaks no snapshot"
else
  fail "non-zero exit left $(scratch_count) file(s) behind"
fi

# --- caller's EXIT trap is chained, not replaced -----------------------------
# The Codex P2 on #3452: begin's trap must not clobber a caller-armed EXIT
# handler. The child arms its own cleanup marker BEFORE begin; both the
# marker (caller's handler ran) and an empty scratch (guard's release ran)
# must hold after exit.
printf 'chain\n' >"$target"
marker="$WORK/prev-trap-ran"
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  trap "touch \"$3\"" EXIT
  hook::rewrite_guard_begin "$2"
  exit 0
' _ "$LIB_DIR" "$target" "$marker"
if [[ -f "$marker" ]]; then
  ok "caller's prior EXIT trap still runs after begin (chained)"
else
  fail "caller's prior EXIT trap was clobbered by begin"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "chained exit still releases the snapshot"
else
  fail "chained exit left $(scratch_count) file(s) behind"
fi
rm -f "$marker"

# ...and a second begin does not chain the guard's handler to itself.
bash -c '
  source "$1/hook-utils.sh"
  source "$1/rewrite-guard.sh"
  trap "touch \"$3\"" EXIT
  hook::rewrite_guard_begin "$2"
  hook::rewrite_take_disclosure "$2" "m"
  hook::rewrite_guard_begin "$2"
  exit 0
' _ "$LIB_DIR" "$target" "$marker"
if [[ -f "$marker" && "$(scratch_count)" == "0" ]]; then
  ok "second begin keeps the chain intact (caller trap ran, nothing leaked)"
else
  fail "second begin broke the chain (marker=$([[ -f "$marker" ]] && echo yes || echo no), left $(scratch_count))"
fi
rm -f "$marker"

# --- snapshot failure: no orphan, guard inert --------------------------------
# The hand-rolled copies emptied their variable when cp failed but left the
# mktemp file behind; the guard removes it.
hook::rewrite_guard_begin "$WORK/does-not-exist"
if [[ "$(scratch_count)" == "0" ]]; then
  ok "failed snapshot leaves no orphan mktemp file"
else
  fail "failed snapshot left $(scratch_count) file(s) behind"
fi
printf 'four\n' >"$target"
hook::rewrite_take_disclosure "$target" "msg-inert"
if [[ -z "$HOOK_REWRITE_MESSAGE" ]]; then
  ok "take after failed snapshot yields empty message (inert guard)"
else
  fail "take after failed snapshot yielded '$HOOK_REWRITE_MESSAGE'"
fi
if [[ -z "$HOOK_REWRITE_CHANGED" ]]; then
  ok "take after failed snapshot leaves the changed verdict unknown"
else
  fail "take after failed snapshot set HOOK_REWRITE_CHANGED='$HOOK_REWRITE_CHANGED'"
fi

# --- disclose emits one systemMessage-only document on change ----------------
hook::rewrite_guard_begin "$target"
printf 'five\n' >"$target"
out=$(hook::rewrite_disclose PostToolUse "$target" "disclose-msg")
if command -v jq >/dev/null 2>&1; then
  if [[ "$(printf '%s' "$out" | jq -s 'length')" == "1" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.systemMessage')" == "disclose-msg" ]] &&
    [[ "$(printf '%s' "$out" | jq 'has("hookSpecificOutput")')" == "false" ]]; then
    ok "disclose emits one systemMessage-only document"
  else
    fail "disclose output malformed: $out"
  fi
else
  if [[ "$out" == *disclose-msg* ]]; then
    ok "disclose emits the message (jq absent; string check)"
  else
    fail "disclose emitted nothing"
  fi
fi

# --- disclose emits nothing when unchanged -----------------------------------
hook::rewrite_guard_begin "$target"
out=$(hook::rewrite_disclose PostToolUse "$target" "should-not-appear")
if [[ -z "$out" ]]; then
  ok "disclose emits nothing on an unchanged file"
else
  fail "disclose emitted on an unchanged file: $out"
fi

# --- an empty <file> takes against the file begin was given ------------------
# The spelling hook::finish uses. The two halves of one guard cannot disagree
# about which file was snapshotted, which is what a hook that formats a
# normalized path spelling and takes on the original did.
hook::rewrite_guard_begin "$target"
printf 'remembered\n' >"$target"
hook::rewrite_take_disclosure "" "msg-remembered"
if [[ "$HOOK_REWRITE_MESSAGE" == "msg-remembered" && "$HOOK_REWRITE_CHANGED" == "true" ]]; then
  ok "an empty file argument compares against the file begin was given"
else
  fail "empty file argument yielded message='$HOOK_REWRITE_MESSAGE' changed='$HOOK_REWRITE_CHANGED'"
fi
if [[ "$(scratch_count)" == "0" ]]; then
  ok "take releases the snapshot (remembered-file path)"
else
  fail "take left $(scratch_count) file(s) behind (remembered-file path)"
fi
hook::rewrite_guard_begin "$target"
hook::rewrite_take_disclosure "" "msg-remembered-unchanged"
if [[ -z "$HOOK_REWRITE_MESSAGE" && "$HOOK_REWRITE_CHANGED" == "false" ]]; then
  ok "an empty file argument on an unchanged file yields no message"
else
  fail "empty file argument, unchanged: message='$HOOK_REWRITE_MESSAGE' changed='$HOOK_REWRITE_CHANGED'"
fi

# --- take composes with emit_channels as ONE document ------------------------
# The #3406 class: rewrite disclosure plus findings context must be one JSON
# document carrying both channels.
hook::rewrite_guard_begin "$target"
printf 'six\n' >"$target"
hook::rewrite_take_disclosure "$target" "compose-msg"
out=$(hook::emit_channels PostToolUse "some findings" "$HOOK_REWRITE_MESSAGE")
if command -v jq >/dev/null 2>&1; then
  if [[ "$(printf '%s' "$out" | jq -s 'length')" == "1" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.systemMessage')" == "compose-msg" ]] &&
    [[ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" == "some findings" ]]; then
    ok "take + emit_channels compose both channels into one document"
  else
    fail "composed output malformed: $out"
  fi
else
  ok "compose check skipped (jq absent)"
fi

# --- gitignore scope gate (#4671) ---------------------------------------------
# A fixture repository with an ignored scratch tier, a tracked file matching an
# ignore pattern, and an ordinary file. Global excludes are neutralized so a
# developer's own ignore rules cannot decide what the suite sees.
if command -v git >/dev/null 2>&1; then
  GREPO="$WORK/grepo"
  mkdir -p "$GREPO/.work" "$GREPO/src"
  git -C "$GREPO" init -q
  git -C "$GREPO" config core.excludesFile /dev/null
  git -C "$GREPO" config user.email t@t.t
  git -C "$GREPO" config user.name t
  printf '.work/\n*.gen.sh\n' >"$GREPO/.gitignore"
  printf 'x\n' >"$GREPO/.work/scratch.sh"
  printf 'x\n' >"$GREPO/src/plain.sh"
  printf 'x\n' >"$GREPO/src/tracked.gen.sh"
  git -C "$GREPO" add -f src/tracked.gen.sh
  git -C "$GREPO" commit -q -m init

  if hook::file_is_gitignored "$GREPO/.work/scratch.sh"; then
    ok "gitignored: an ignored untracked file reads as ignored"
  else
    fail "gitignored: .work/scratch.sh did not read as ignored"
  fi
  if ! hook::file_is_gitignored "$GREPO/src/tracked.gen.sh"; then
    ok "gitignored: a tracked file matching an ignore pattern reads as not ignored"
  else
    fail "gitignored: a tracked file read as ignored"
  fi
  if ! hook::file_is_gitignored "$GREPO/src/plain.sh"; then
    ok "gitignored: an ordinary file reads as not ignored"
  else
    fail "gitignored: src/plain.sh read as ignored"
  fi

  NOREPO="$WORK/norepo"
  mkdir -p "$NOREPO"
  printf 'x\n' >"$NOREPO/loose.sh"
  if ! hook::file_is_gitignored "$NOREPO/loose.sh"; then
    ok "gitignored: a file in no repository reads as not ignored"
  else
    fail "gitignored: a file in no repository read as ignored"
  fi
  if ! hook::file_is_gitignored "$WORK/missing-dir/gone.sh"; then
    ok "gitignored: a vanished directory fails toward acting (not ignored)"
  else
    fail "gitignored: a vanished directory read as ignored"
  fi

  # An inherited GIT_DIR naming ANOTHER repository must not answer: the
  # other repository ignores nothing, so honoring it would lint the file.
  OTHER="$WORK/other"
  mkdir -p "$OTHER"
  git -C "$OTHER" init -q
  if (GIT_DIR="$OTHER/.git" GIT_WORK_TREE="$OTHER" hook::file_is_gitignored "$GREPO/.work/scratch.sh"); then
    ok "gitignored: an inherited GIT_DIR/GIT_WORK_TREE is cleared (still ignored)"
  else
    fail "gitignored: an inherited GIT_DIR/GIT_WORK_TREE decided the answer"
  fi

  if hook::gitignored_out_of_scope "false" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: ignored file with the opt-in off is out of scope"
  else
    fail "out_of_scope: ignored file with the opt-in off stayed in scope"
  fi
  if ! hook::gitignored_out_of_scope "true" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: the opt-in 'true' keeps an ignored file in scope"
  else
    fail "out_of_scope: the opt-in 'true' did not keep the file in scope"
  fi
  if hook::gitignored_out_of_scope "yes; rm -rf /" "$GREPO/.work/scratch.sh"; then
    ok "out_of_scope: a garbage opt-in value reads as the default (off)"
  else
    fail "out_of_scope: a garbage opt-in value opened the gate"
  fi
  if ! hook::gitignored_out_of_scope "false" "$GREPO/src/plain.sh"; then
    ok "out_of_scope: an ordinary file stays in scope with the opt-in off"
  else
    fail "out_of_scope: an ordinary file was put out of scope"
  fi
else
  ok "gitignore scope checks skipped (git absent)"
fi

echo
echo "rewrite-guard tests: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
