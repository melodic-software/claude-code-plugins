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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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

rc=0
OUT=$(bash "$SCRIPT" --root "$NOLINE" --confirm --installed-plugins "$TMP/installed-current.json" \
  --claude-bin "$TMP/bin/claude-met" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "a directory with no distinctive line exits 1" 1 "$rc"
assert_contains "and says so" "$OUT" "no line distinctive enough to canary"
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
# than printing "restored" over a failure.
HALF="$TMP/halfrestore"
build_ready_repo "$HALF"
rc=0
OUT=$(RESTORE_BLOCKER="$HALF/svc" bash -c '
  mkdir -p "$1/svc-blocked"
  "$2" --root "$1" --confirm --installed-plugins "$3" --claude-bin "$4" "${@:5}"
' _ "$HALF" "$SCRIPT" "$TMP/installed-current.json" "$TMP/bin/claude-unmet" "${CHECK_ARGS[@]}") || rc=$?
assert_eq "the restore path still exits non-zero after a miss" 1 "$rc"
assert_contains "and every shim it removed is back" "$OUT" "restored svc/CLAUDE.md"
assert_eq "the restored root shim is byte-exact" "@AGENTS.md" "$(cat "$HALF/CLAUDE.md")"

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

echo
if ((FAILED == 0)); then
  echo "All $CASE_NUM checks passed"
  exit 0
fi
echo "$FAILED/$CASE_NUM checks failed"
exit 1
