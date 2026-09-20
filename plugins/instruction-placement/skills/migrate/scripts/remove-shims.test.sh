#!/usr/bin/env bash
# Regression tests for remove-shims.sh (self-contained — ships with the plugin).
#
# Every case runs against a fixture repository in a temporary directory, with a
# fixture installed-plugin manifest, fixture cutover-check inputs and a fake
# `claude`. No case touches a real repository and no case spends a real turn.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/remove-shims.sh"
REAL_SOURCES="$SCRIPT_DIR/../reference/sources.md"

CASE_NUM=0
FAILED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}

# A helper this suite never defined used to print "command not found" to stderr
# and move on, so the run reported every other check passing while silently
# skipping that one. An unknown command is a failed check.
#
# The count goes through a FILE, not the FAILED variable: bash runs this
# handler wherever the unknown command was, which is often a subshell, and a
# subshell's increment dies with it. The summary adds the file's lines back in.
UNKNOWN_COMMANDS="$(mktemp)"
# shellcheck disable=SC2329 # bash invokes this by name when a command is not found
command_not_found_handle() {
  printf '%s\n' "$1" >>"$UNKNOWN_COMMANDS"
  printf 'FAIL: unknown command in the suite: %s\n' "$1"
  printf '      a helper is missing or misspelled; the check it belonged to did not run\n'
  return 127
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rm -f "${UNKNOWN_COMMANDS:-}"' EXIT
cd "$TMP" || exit 1

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "t@example.com" &&
    git config user.name "t" && git config core.autocrlf false &&
    git commit -q --allow-empty -m init)
}

commit_all() { (cd "$1" && git add -A && git commit -q -m "${2:-fixture}"); }

# --- fixtures -------------------------------------------------------------

# The cutover check's own inputs, so a remove-shims run can reach its later
# gates. Its parser is covered by cutover-check.test.sh; here it is a
# precondition, not the subject.
{
  printf 'noise\001'
  printf 'Cs(ne,{isOnByDefault:()=>W});var W=!0;var B=()=>Gl("tengu_agents_md_mod",W);'
} >"$TMP/bundle-true"
cat >"$TMP/env-vars.md" <<'EOF'
# Environment variables

## Features that need feature-flag fetching

- Have Claude Code [read `AGENTS.md` files](/docs/en/memory#agents-md) as project instructions.
EOF

mkdir -p "$TMP/bin"
# A load looks like the directory's own AGENTS.md coming back.
printf '#!/usr/bin/env bash\ncat AGENTS.md\n' >"$TMP/bin/claude-met"
printf '#!/usr/bin/env bash\necho NONE\n' >"$TMP/bin/claude-unmet"
chmod +x "$TMP/bin/claude-met" "$TMP/bin/claude-unmet"

cat >"$TMP/installed-current.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "instruction-placement@melodic-software": [{ "scope": "user", "version": "0.15.0" }],
    "claude-memory@melodic-software": [{ "scope": "user", "version": "0.12.9" }]
  }
}
EOF

cat >"$TMP/installed-stale.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "instruction-placement@melodic-software": [{ "scope": "user", "version": "0.15.0" }],
    "claude-memory@melodic-software": [{ "scope": "user", "version": "0.12.8" }]
  }
}
EOF

# A newer copy in one scope beside an older copy in another. The older one is
# what answers in the repository being de-shimmed, so the lowest wins.
cat >"$TMP/installed-mixed.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "instruction-placement@melodic-software": [
      { "scope": "user", "version": "0.15.0" },
      { "scope": "project", "version": "0.13.11" }
    ],
    "claude-memory@melodic-software": [{ "scope": "user", "version": "0.12.9" }]
  }
}
EOF

# 0.14.0 is below the instruction-placement floor: the old doctrine still lived
# in two of its own files at that release.
cat >"$TMP/installed-0140.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "instruction-placement@melodic-software": [{ "scope": "user", "version": "0.14.0" }],
    "claude-memory@melodic-software": [{ "scope": "user", "version": "0.12.9" }]
  }
}
EOF

CHECK_ARGS=(
  --check-arg --sources --check-arg "$REAL_SOURCES"
  --check-arg --bundle --check-arg "$TMP/bundle-true"
  --check-arg --env-vars-file --check-arg "$TMP/env-vars.md"
  --check-arg --canary-home-root --check-arg "$TMP/canary-home"
  --check-arg --canary-alt-root --check-arg "$TMP/canary-alt"
  --check-arg --claude-bin --check-arg "$TMP/bin/claude-met"
)

AGENTS_LINE='Every change in this repository is reviewed before it is merged anywhere.'
NESTED_LINE='The service in this directory owns its own deployment and its own rollback.'

# A repository at the target shape: a root shim and a nested shim, both beside
# a non-empty AGENTS.md, and no path detection to acknowledge.
build_ready_repo() { # <path>
  local r="$1"
  make_repo "$r"
  mkdir -p "$r/svc"
  printf '# Conventions\n\n%s\n' "$AGENTS_LINE" >"$r/AGENTS.md"
  printf '@AGENTS.md\n' >"$r/CLAUDE.md"
  printf 'A repository fixture.\n' >"$r/README.md"
  printf '# Service\n\n%s\n' "$NESTED_LINE" >"$r/svc/AGENTS.md"
  printf '@AGENTS.md\n' >"$r/svc/CLAUDE.md"
  printf 'print("svc")\n' >"$r/svc/main.py"
  commit_all "$r"
}

# --- Case 1: --help and usage errors --------------------------------------

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
assert_contains "--help says root and nested come out together" "$OUT" "together or not at all"

rc=0
bash "$SCRIPT" --confirm >/dev/null 2>&1 || rc=$?
assert_eq "no --root exits 2" 2 "$rc"

rc=0
bash "$SCRIPT" --root "$TMP" --confirm >/dev/null 2>&1 || rc=$?
assert_eq "outside a git repository exits 2" 2 "$rc"

rc=0
bash "$SCRIPT" --root "$TMP" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "an unknown argument exits 2" 2 "$rc"

# --- Case 2: without --confirm it prints the price and removes nothing ----

READY="$TMP/ready"
build_ready_repo "$READY"

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "no --confirm exits 1" 1 "$rc"
assert_contains "and prints what removal costs" "$OUT" "InstructionsLoaded"
assert_contains "and says it is not confirmed" "$OUT" "Not confirmed"
assert_eq "and the repository is untouched" "" "$(cd "$READY" && git status --porcelain)"

# --- Case 3: a stale installed plugin refuses before anything is removed --

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/installed-stale.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a stale plugin version exits 1" 1 "$rc"
assert_contains "and names the plugin and the floor" "$OUT" "installed claude-memory is 0.12.8 (the lowest copy across every scope), below"
assert_eq "and removes nothing" "" "$(cd "$READY" && git status --porcelain)"

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/nope.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an unreadable manifest exits 1" 1 "$rc"
assert_contains "and says an unread version is not a version" "$OUT" "An unread version is not"

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/installed-mixed.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a stale copy in another scope is not hidden by a newer one" 1 "$rc"
assert_contains "and the lowest installed version is the one reported" "$OUT" \
  "installed instruction-placement is 0.13.11 (the lowest copy across every scope)"
assert_eq "and removes nothing" "" "$(cd "$READY" && git status --porcelain)"

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/installed-0140.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "instruction-placement 0.14.0 is below the floor" 1 "$rc"
assert_contains "and the floor is named" "$OUT" "below the corrected-doctrine release 0.15.0"

# --- Case 4: an unmet cutover condition removes nothing -------------------

BLOCKED="$TMP/blocked"
build_ready_repo "$BLOCKED"
mkdir -p "$BLOCKED/tools"
# shellcheck disable=SC2016 # the fixture line is literal text; $root must not expand here
printf 'if [[ -f "$root/CLAUDE.md" ]]; then echo found; fi\n' >"$BLOCKED/tools/find-root.sh"
commit_all "$BLOCKED" "an unacknowledged path detector"

rc=0
OUT=$(bash "$SCRIPT" --root "$BLOCKED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an unmet condition exits 1" 1 "$rc"
assert_contains "and says the check refused it" "$OUT" "cutover-check reported a condition that is not [MET]"
assert_contains "and the check's own evidence is shown" "$OUT" "UNACKNOWLEDGED tools/find-root.sh"
assert_eq "and the repository still has its shims" "" "$(cd "$BLOCKED" && git status --porcelain)"

# --- Case 5: a repository not at the target shape -------------------------

UNFINISHED="$TMP/unfinished"
build_ready_repo "$UNFINISHED"
printf '@AGENTS.md\n\nPlus Claude-only extensions.\n' >"$UNFINISHED/CLAUDE.md"
commit_all "$UNFINISHED" "content still in CLAUDE.md"

rc=0
OUT=$(bash "$SCRIPT" --root "$UNFINISHED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an unfinished migration exits 1" 1 "$rc"
assert_contains "and names the state it found" "$OUT" "both-with-content"
assert_eq "and removes nothing" "" "$(cd "$UNFINISHED" && git status --porcelain)"

ZERO="$TMP/zerobyte"
build_ready_repo "$ZERO"
printf '' >"$ZERO/AGENTS.md"
commit_all "$ZERO" "a zero-byte root AGENTS.md"

rc=0
OUT=$(bash "$SCRIPT" --root "$ZERO" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a zero-byte AGENTS.md exits 1" 1 "$rc"
assert_contains "and says it cannot be canaried" "$OUT" "cannot be canaried"
assert_eq "and removes nothing" "" "$(cd "$ZERO" && git status --porcelain)"

# --- Case 6: a surface that cannot be verified is never de-shimmed --------

NOLINE="$TMP/noline"
build_ready_repo "$NOLINE"
printf '# Service\n\n- a bullet\n- another bullet\n' >"$NOLINE/svc/AGENTS.md"
commit_all "$NOLINE" "a nested AGENTS.md with no canaryable line"

# A nested session loads its ancestors too, so a line the nested file shares
# with the root file is answered by the root file and proves nothing about the
# nested surface. Such a file has no usable line, and the refusal comes BEFORE
# any removal.
SHARED="$TMP/sharedline"
build_ready_repo "$SHARED"
printf '# Service\n\n%s\n' "$AGENTS_LINE" >"$SHARED/svc/AGENTS.md"
commit_all "$SHARED" "the nested AGENTS.md repeats the root's only long line"

rc=0
OUT=$(bash "$SCRIPT" --root "$SHARED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a line an ancestor also carries is refused" 1 "$rc"
assert_contains "and says why the ancestor would answer for it" "$OUT" \
  "answered by the ancestor"
assert_eq "and nothing was removed first" "" "$(cd "$SHARED" && git status --porcelain)"

rc=0
OUT=$(bash "$SCRIPT" --root "$NOLINE" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a directory with no distinctive line exits 1" 1 "$rc"
assert_contains "and says so" "$OUT" "no line that is both distinctive and unique"
assert_eq "and removes nothing, including the root shim" "" "$(cd "$NOLINE" && git status --porcelain)"

# --- Case 7: the happy path, root and nested together ---------------------

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a ready repository exits 0" 0 "$rc"
assert_contains "the root shim is removed" "$OUT" "removed CLAUDE.md"
assert_contains "the nested shim is removed in the same run" "$OUT" "removed svc/CLAUDE.md"
assert_contains "the root canary returns the AGENTS.md line" "$OUT" ".: the AGENTS.md line came back"
assert_contains "the nested canary returns its own line" "$OUT" "svc: the AGENTS.md line came back"
assert_eq "and both files are gone from the worktree" "" \
  "$(ls "$READY/CLAUDE.md" "$READY/svc/CLAUDE.md" 2>/dev/null)"
STATUS="$(cd "$READY" && git status --porcelain)"
assert_contains "git sees the root deletion" "$STATUS" " D CLAUDE.md"
assert_contains "git sees the nested deletion" "$STATUS" " D svc/CLAUDE.md"
assert_not_contains "and nothing else changed: no token was written" "$STATUS" "AGENTS.md"
assert_eq "the root AGENTS.md is byte-identical" "$(printf '# Conventions\n\n%s\n' "$AGENTS_LINE")" \
  "$(cat "$READY/AGENTS.md")"
assert_eq "the nested AGENTS.md is byte-identical" "$(printf '# Service\n\n%s\n' "$NESTED_LINE")" \
  "$(cat "$READY/svc/AGENTS.md")"

# --- Case 8: a canary miss restores every shim this run removed -----------

MISSING="$TMP/missing"
build_ready_repo "$MISSING"

rc=0
OUT=$(bash "$SCRIPT" --root "$MISSING" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-unmet" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a canary miss exits 1" 1 "$rc"
assert_contains "and says the AGENTS.md did not load" "$OUT" "clean NONE"
assert_contains "and says it restored the shims" "$OUT" "restored CLAUDE.md"
assert_contains "including the nested one" "$OUT" "restored svc/CLAUDE.md"
assert_eq "and the worktree is back where it started" "" "$(cd "$MISSING" && git status --porcelain)"
assert_eq "the root shim is one line again" "@AGENTS.md" "$(cat "$MISSING/CLAUDE.md")"
assert_eq "and so is the nested one" "@AGENTS.md" "$(cat "$MISSING/svc/CLAUDE.md")"

# A canary that could not measure is not a pass either, and restores the same
# way a clean miss does.
printf '#!/usr/bin/env bash\nexit 7\n' >"$TMP/bin/claude-unreach"
chmod +x "$TMP/bin/claude-unreach"
UNREACHABLE="$TMP/unreachable"
build_ready_repo "$UNREACHABLE"

rc=0
OUT=$(bash "$SCRIPT" --root "$UNREACHABLE" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-unreach" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an unmeasurable canary exits 1" 1 "$rc"
assert_contains "and reports UNREACH with the exit code" "$OUT" "UNREACH, the CLI exited 7"
assert_contains "and restores the shims" "$OUT" "restored CLAUDE.md"
assert_eq "leaving the worktree as it was" "" "$(cd "$UNREACHABLE" && git status --porcelain)"

# A restore that did not land says so and takes the exit code with it, rather
# than printing "restored" over a failure. The fake CLI deletes the nested
# directory during the root canary, so the nested shim has nowhere to go back
# to while the root one restores normally.
HALF="$TMP/halfrestore"
build_ready_repo "$HALF"
# shellcheck disable=SC2016 # the fixture script's own text; it must expand when IT runs, not here
printf '#!/usr/bin/env bash\nrm -rf "$(git rev-parse --show-toplevel)/svc"\necho NONE\n' \
  >"$TMP/bin/claude-eats-svc"
chmod +x "$TMP/bin/claude-eats-svc"

rc=0
OUT=$(bash "$SCRIPT" --root "$HALF" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-eats-svc" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a restore that did not land still exits non-zero" 1 "$rc"
assert_contains "and names the file it could not put back" "$OUT" "COULD NOT RESTORE svc/CLAUDE.md"
assert_not_contains "and does not claim that one was restored" "$OUT" "  restored svc/CLAUDE.md"
assert_contains "and says so in the refusal" "$OUT" "shim(s) could NOT be put back"
assert_contains "while the shim it could restore is back" "$OUT" "restored CLAUDE.md"
assert_eq "and that one is byte-exact" "@AGENTS.md" "$(cat "$HALF/CLAUDE.md")"

# A line that an ancestor also carries must be rejected even when it holds
# backslashes or regex metacharacters: passing it to awk through -v would make
# awk interpret `\t` and `\n`, so the comparison would look at a different
# string and score the line unique while the ancestor answers its probe.
ESCAPED="$TMP/escaped"
build_ready_repo "$ESCAPED"
TRICKY='Install to C:\tools\new\bin and run .*+?[x] before the first deploy of the day.' # portability-ok: a Windows path inside fixture text, not a GNU grep word boundary
printf '# Conventions\n\n%s\n' "$TRICKY" >"$ESCAPED/AGENTS.md"
printf '# Service\n\n%s\n' "$TRICKY" >"$ESCAPED/svc/AGENTS.md"
commit_all "$ESCAPED" "root and nested share a line full of escapes"

rc=0
OUT=$(bash "$SCRIPT" --root "$ESCAPED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a shared line carrying backslashes is still rejected" 1 "$rc"
assert_contains "and says the ancestor would answer for it" "$OUT" "answered by the ancestor"
assert_eq "and nothing was removed" "" "$(cd "$ESCAPED" && git status --porcelain)"

# Claude Code loads by filesystem, not by tracking status. An UNTRACKED
# intermediate AGENTS.md is in no plan row, so an index built from the plan
# missed it and the nested line below it scored unique while that file would
# answer its probe in a real session.
UNTRACKED="$TMP/untracked"
build_ready_repo "$UNTRACKED"
mkdir -p "$UNTRACKED/mid/svc"
SHARED_LINE='The middle tier owns its own migrations and its own rollback windows.'
printf '# Mid\n\n%s\n' "$SHARED_LINE" >"$UNTRACKED/mid/AGENTS.md"
printf '# Mid service\n\n%s\n' "$SHARED_LINE" >"$UNTRACKED/mid/svc/AGENTS.md"
printf '@AGENTS.md\n' >"$UNTRACKED/mid/svc/CLAUDE.md"
printf 'mid/AGENTS.md\n' >"$UNTRACKED/.gitignore"
(cd "$UNTRACKED" && git add -A && git commit -q -m "an untracked intermediate AGENTS.md")

rc=0
OUT=$(bash "$SCRIPT" --root "$UNTRACKED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an untracked ancestor still blocks a shared line" 1 "$rc"
assert_contains "and says the ancestor would answer for it" "$OUT" "answered by the ancestor"
assert_eq "and nothing was removed" "" "$(cd "$UNTRACKED" && git status --porcelain --untracked-files=no)"

# A SYMLINKED AGENTS.md is a file a session loads, so the index has to see it.
# `-type f` alone skipped it while the above-root walk's `-f` test follows
# symlinks, so the two halves of the index disagreed. Windows Git Bash needs a
# privilege for `ln -s`, so the case is guarded the way the sibling suites
# guard theirs and runs on Linux CI.
SYMLINKED="$TMP/symlinked"
build_ready_repo "$SYMLINKED"
mkdir -p "$SYMLINKED/mid"
SYM_LINE='The middle tier owns its own migrations and its own rollback windows.'
printf '# Mid\n\n%s\n' "$SYM_LINE" >"$SYMLINKED/mid/real-agents.md"
printf '# Service\n\n%s\n' "$SYM_LINE" >"$SYMLINKED/svc/AGENTS.md"
if ln -s real-agents.md "$SYMLINKED/mid/AGENTS.md" 2>/dev/null && [[ -f "$SYMLINKED/mid/AGENTS.md" ]]; then
  commit_all "$SYMLINKED" "a symlinked AGENTS.md shares the nested line"
  rc=0
  OUT=$(bash "$SCRIPT" --root "$SYMLINKED" --confirm --installed-plugins "$TMP/installed-current.json" \
    --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
  assert_eq "a symlinked AGENTS.md still blocks a shared line" 1 "$rc"
  assert_contains "and says the ancestor would answer for it" "$OUT" "answered by the ancestor"
else
  printf 'SKIP: symlink creation unavailable on this host (the case runs on Linux CI)\n'
fi

# A walk that failed and a repository with one AGENTS.md are the same empty
# output, and on the empty reading every line scores unique.
FAKEBIN="$TMP/fakefind"
mkdir -p "$FAKEBIN"
printf '#!/usr/bin/env bash\nexit 2\n' >"$FAKEBIN/find"
chmod +x "$FAKEBIN/find"
FINDFAIL="$TMP/findfail"
build_ready_repo "$FINDFAIL"
rc=0
OUT=$(PATH="$FAKEBIN:$PATH" bash "$SCRIPT" --root "$FINDFAIL" --confirm \
  --installed-plugins "$TMP/installed-current.json" --claude-bin "$TMP/bin/claude-met" \
  "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a failed walk is a refusal" 1 "$rc"
assert_contains "and says the walk failed" "$OUT" "the AGENTS.md walk failed"
assert_eq "and nothing was removed" "" "$(cd "$FINDFAIL" && git status --porcelain)"

# A walk that exits 0 having seen nothing is the same hazard wearing a clean
# exit code: the directory being judged is not in the index built to judge it.
printf '#!/usr/bin/env bash\nexit 0\n' >"$FAKEBIN/find"
chmod +x "$FAKEBIN/find"
EMPTYIDX="$TMP/emptyindex"
build_ready_repo "$EMPTYIDX"
rc=0
OUT=$(PATH="$FAKEBIN:$PATH" bash "$SCRIPT" --root "$EMPTYIDX" --confirm \
  --installed-plugins "$TMP/installed-current.json" --claude-bin "$TMP/bin/claude-met" \
  "${CHECK_ARGS[@]}") || rc=$?
assert_eq "an empty index is a refusal, not a clean sweep" 1 "$rc"
assert_contains "and names the file the index never saw" "$OUT" "is not in the canary index"
assert_eq "and nothing was removed either" "" "$(cd "$EMPTYIDX" && git status --porcelain)"
rm -rf "$FAKEBIN"

# A plan with no DIR row at all is discovery that did not run, not a repository
# with nothing in it.
NODIR="$TMP/nodir"
build_ready_repo "$NODIR"
NODIR_STUB="$TMP/nodir-stub"
mkdir -p "$NODIR_STUB/scripts" "$NODIR_STUB/reference"
cp "$SCRIPT" "$NODIR_STUB/scripts/remove-shims.sh"
cp "$SCRIPT_DIR/cutover-check.sh" "$NODIR_STUB/scripts/cutover-check.sh"
cp "$REAL_SOURCES" "$NODIR_STUB/reference/sources.md"
printf '#!/usr/bin/env bash\nprintf "PATHDET\\tNONE\\nACTION\\tNONE\\n"\n' \
  >"$NODIR_STUB/scripts/plan-migration.sh"
chmod +x "$NODIR_STUB/scripts/plan-migration.sh"
rc=0
OUT=$(bash "$NODIR_STUB/scripts/remove-shims.sh" --root "$NODIR" --confirm \
  --installed-plugins "$TMP/installed-current.json" --claude-bin "$TMP/bin/claude-met" \
  "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a plan with no DIR row is a refusal, not success" 1 "$rc"
assert_contains "and says discovery did not report" "$OUT" "carries no DIR row"

# The ordering that D1 fixes (a directory is listed BEFORE its file is
# touched, so a signal landing inside `rm` cannot leave it unlisted) has no
# portable test: provoking an `rm -f` failure means making the path a
# directory, which changes the plan's state for it to `agents-only` and skips
# the removal entirely. What IS testable is that every listed directory comes
# back, including the last one processed, which the canary-miss and
# canary-unreachable cases above both assert.

# A death that is not a clean exit must not strand a de-shimmed, unverified
# repository. A closed pipe is the case that needs no `kill` to provoke and the
# one a named INT/TERM trap misses: `remove-shims | head` was enough to strand
# a repository before the restore moved onto the EXIT trap.
# The reader has to survive until AFTER the first removal, or the run dies in
# a window where there is nothing to restore and the case proves nothing. `grep
# -q` exits on its first match, so closing on a "removed" line puts the death
# exactly inside the window the ignore protects. A canary that then misses
# means the restore has real work to do either way.
PIPED="$TMP/piped"
build_ready_repo "$PIPED"
bash "$SCRIPT" --root "$PIPED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-unmet" "${CHECK_ARGS[@]}" 2>/dev/null |
  grep -q 'removed svc/CLAUDE.md'
assert_eq "a reader that closes after a removal still leaves the shims in place" "" \
  "$(cd "$PIPED" && git status --porcelain)"
assert_eq "and the root shim is the import line again" "@AGENTS.md" "$(cat "$PIPED/CLAUDE.md")"
assert_eq "and so is the nested one" "@AGENTS.md" "$(cat "$PIPED/svc/CLAUDE.md")"

# A staged edit to a shim does not become the restored content: the restore
# writes the one line the target shape guarantees, not the index copy.
STAGED="$TMP/staged"
build_ready_repo "$STAGED"
printf '@AGENTS.md\n\nsomething staged\n' >"$STAGED/CLAUDE.md"
(cd "$STAGED" && git add CLAUDE.md)
rc=0
OUT=$(bash "$SCRIPT" --root "$STAGED" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-unmet" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a repository whose shim carries staged content is refused" 1 "$rc"
assert_contains "and named as not the target shape" "$OUT" "both-with-content"

# --- Case 9: a repository with no shims left ------------------------------

rc=0
OUT=$(bash "$SCRIPT" --root "$READY" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a de-shimmed repository exits 0" 0 "$rc"
assert_contains "and says there is nothing to remove" "$OUT" "Nothing to remove"

[[ -s "$UNKNOWN_COMMANDS" ]] && FAILED=$((FAILED + $(wc -l <"$UNKNOWN_COMMANDS")))

echo
if ((FAILED == 0)); then
  echo "All $CASE_NUM checks passed"
  exit 0
fi
echo "$FAILED/$CASE_NUM checks failed"
exit 1
