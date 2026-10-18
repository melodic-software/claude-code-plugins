#!/usr/bin/env bash
# Regression tests for reap-project-plugin-records.sh. Black-box: a stubbed
# `claude` on PATH reproduces the measured CLI contract — `plugin list --json`
# reports every project-scope record regardless of cwd, while
# `plugin uninstall <id> -s project` acts ONLY on a record whose projectPath is
# the current directory and otherwise fails with the text that suggests
# `--scope user`. Every case here pins a safety property the reap rests on:
# the cwd-equality refusal, the never-`-s user` / never-`--prune` rule, the
# always-`--keep-data` rule, the other-path records left untouched, and the
# visible degrade.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAP="$SCRIPT_DIR/reap-project-plugin-records.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Resolved once; the platform cannot change mid-suite, and three of the cases
# below branch on it.
UNAME_S="$(uname -s 2>/dev/null || true)"

STUB_DIR="$TEST_TMPDIR/stub"
mkdir -p "$STUB_DIR"

STATE="$TEST_TMPDIR/state.json"
LOG="$TEST_TMPDIR/calls.log"

# The stub reproduces the measured contract, not a convenience fiction.
cat >"$STUB_DIR/claude" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"

stub_native_pwd() {
  local p
  p="$(pwd -W 2>/dev/null)" || p=""
  [[ -n "$p" ]] || p="$(pwd -P 2>/dev/null)" || p="$PWD"
  printf '%s' "$p"
}
stub_key() {
  local p="${1//\\//}"
  while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%/}"; done
  printf '%s' "$p" | tr '[:upper:]' '[:lower:]'
}

if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  [[ "${STUB_LIST_FAIL:-0}" == 1 ]] && exit 1
  if [[ "${STUB_LIST_SHAPE:-object}" == "array" ]]; then
    jq -c '.' "$STUB_STATE"
  else
    jq -c '{installed: .}' "$STUB_STATE"
  fi
  exit 0
fi

if [[ "${1:-}" == "plugin" && "${2:-}" == "uninstall" ]]; then
  id="${3:-}"
  scope=""
  shift 3
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -s | --scope)
      scope="${2:-}"
      shift 2
      ;;
    *) shift ;;
    esac
  done
  here="$(stub_key "$(stub_native_pwd)")"
  hit="$(jq -r --arg id "$id" --arg here "$here" --arg scope "$scope" '
    map(select(.id == $id and .scope == $scope
      and ((.projectPath // "") | gsub("\\\\"; "/") | ascii_downcase | sub("/$"; "")) == $here))
    | length' "$STUB_STATE")"
  if [[ ( "$scope" == "project" || "$scope" == "local" ) && "$hit" -gt 0 ]]; then
    tmp="$(mktemp)"
    jq --arg id "$id" --arg here "$here" --arg scope "$scope" '
      map(select((.id == $id and .scope == $scope
        and ((.projectPath // "") | gsub("\\\\"; "/") | ascii_downcase | sub("/$"; "")) == $here) | not))
    ' "$STUB_STATE" >"$tmp" && mv "$tmp" "$STUB_STATE"
    # The reported side effect: a project-scope uninstall also rewrites the
    # cwd's .claude/settings.json, dropping entries and unrelated settings.
    if [[ "${STUB_REWRITE_SETTINGS:-0}" == 1 ]]; then
      mkdir -p .claude
      printf '{\n  "enabledPlugins": {}\n}\n' >.claude/settings.json
    fi
    printf 'Successfully uninstalled plugin: %s (scope: %s)\n' "$id" "$scope"
    exit 0
  fi
  printf 'Failed to uninstall plugin "%s": Plugin "%s" is installed in user scope, not project. Use --scope user to uninstall.\n' "$id" "$id" >&2
  exit 1
fi

printf 'stub: unhandled: %s\n' "$*" >&2
exit 64
STUB
chmod +x "$STUB_DIR/claude"

native_of() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }

# run <cwd> [args...] — one reap invocation with the stub on PATH.
RC=0
OUT=""
run() {
  local cwd="$1"
  shift
  OUT="$(cd "$cwd" && PATH="${EXTRA_PATH:+$EXTRA_PATH:}$STUB_DIR:$PATH" STUB_STATE="$STATE" \
    STUB_CALL_LOG="$LOG" STUB_LIST_COUNT="$TEST_TMPDIR/listcount" \
    STUB_REWRITE_SETTINGS="${STUB_REWRITE_SETTINGS:-0}" GIT_CALL_LOG="$TEST_TMPDIR/git-calls.log" \
    bash "$REAP" "$@" 2>&1)"
  RC=$?
}

seed_state() { printf '%s\n' "$1" >"$STATE"; }
reset_log() { : >"$LOG"; }

WT="$TEST_TMPDIR/wt"
OTHER="$TEST_TMPDIR/other"
mkdir -p "$WT" "$OTHER"
WT_NATIVE="$(native_of "$WT")"
OTHER_NATIVE="$(native_of "$OTHER")"

# --- CLI contract ---------------------------------------------------------------

help_out="$(bash "$REAP" --help 2>&1)"
help_rc=$?
assert_exit "--help exits 0" 0 "$help_rc"
assert_contains "--help documents the usage line" "$help_out" "--worktree-path"
# usage() derives the header block (shebang to first non-comment line) rather
# than extracting a hardcoded line range, so a header edit cannot silently
# truncate the help. The usage line sits early; the exit-code taxonomy and the
# last header line sit at the end, exactly where a hardcoded range would
# truncate first.
assert_contains "--help includes the exit-code taxonomy near the header's end" \
  "$help_out" "prerequisite missing (claude CLI, jq)"
assert_contains "--help reaches the end of the header, not a truncated range" \
  "$help_out" "must never read as a clean one"

run "$WT"
assert_exit "missing --worktree-path is a usage error" 2 "$RC"

run "$WT" --bogus
assert_exit "unknown argument is a usage error" 2 "$RC"

run "$WT" --worktree-path "$TEST_TMPDIR/does-not-exist"
assert_exit "unresolvable --worktree-path is a usage error" 2 "$RC"

# --- the cwd-equality boundary --------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
reset_log
run "$OTHER" --worktree-path "$WT"
assert_exit "refuses when --worktree-path is not the current directory" 2 "$RC"
assert_contains "the refusal names both paths" "$OUT" "current directory is"
remaining="$(jq 'length' "$STATE")"
assert_eq "a refused run removes nothing" "1" "$remaining"
assert_not_contains "a refused run never calls the CLI" "$(cat "$LOG")" "plugin"

# --- nothing to reap ------------------------------------------------------------

seed_state "$(jq -n --arg o "$OTHER_NATIVE" '[{id:"a@m",scope:"project",projectPath:$o}]')"
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "no records for this directory exits 0" 0 "$RC"
assert_contains "the zero case is reported, not silent" "$OUT" "nothing to reap"
assert_not_contains "no uninstall is attempted" "$(cat "$LOG")" "uninstall"

# --- the reap itself ------------------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" --arg o "$OTHER_NATIVE" '[
  {id:"a@m",scope:"project",projectPath:$wt},
  {id:"b@m",scope:"project",projectPath:$wt},
  {id:"c@m",scope:"project",projectPath:$o},
  {id:"d@m",scope:"user"}
]')"
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "a clean reap exits 0" 0 "$RC"
assert_contains "each reaped id is named" "$OUT" "reaped a@m"
assert_contains "each reaped id is named (2)" "$OUT" "reaped b@m"
left="$(jq -r 'map(.id) | sort | join(",")' "$STATE")"
assert_eq "only this directory's project records are removed" "c@m,d@m" "$left"
assert_not_contains "never escalates to user scope" "$(cat "$LOG")" "-s user"
assert_not_contains "never passes --prune" "$(cat "$LOG")" "--prune"
assert_contains "always passes --keep-data" "$(cat "$LOG")" "--keep-data"

# --- local-scope records are reaped with their own scope -------------------------
# A dead path can hold a project and a local record side by side, and a user
# record for the same plugin must survive.

seed_state "$(jq -n --arg wt "$WT_NATIVE" --arg o "$OTHER_NATIVE" '[
  {id:"a@m",scope:"project",projectPath:$wt},
  {id:"a@m",scope:"local",projectPath:$wt},
  {id:"a@m",scope:"local",projectPath:$o},
  {id:"a@m",scope:"user"}
]')"
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "a mixed project and local reap exits 0" 0 "$RC"
assert_contains "the project record is uninstalled with -s project" "$(cat "$LOG")" "plugin uninstall a@m -s project --keep-data"
assert_contains "the local record is uninstalled with -s local" "$(cat "$LOG")" "plugin uninstall a@m -s local --keep-data"
left="$(jq -r 'map(.scope + ":" + (.projectPath // "")) | sort | join(",")' "$STATE")"
assert_eq "the user record and the other path's local record are untouched" \
  "local:$OTHER_NATIVE,user:" "$left"
assert_not_contains "never escalates to user scope" "$(cat "$LOG")" "-s user"

# --- the tracked settings file is left as it was found ------------------------
# The uninstall CLI also rewrites the cwd's .claude/settings.json. Left dirty, a
# tracked file makes the plain `git worktree remove` that follows the reap
# refuse, and silently drops tracked settings. The stub above reproduces the
# rewrite when STUB_REWRITE_SETTINGS=1. A logging git shim records every git
# call the helper makes.

if command -v git >/dev/null 2>&1; then
  REAL_GIT="$(command -v git)"
  GIT_SHIM="$TEST_TMPDIR/gitshim"
  mkdir -p "$GIT_SHIM"
  cat >"$GIT_SHIM/git" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"\$GIT_CALL_LOG"
exec "$REAL_GIT" "\$@"
SHIM
  chmod +x "$GIT_SHIM/git"
  GIT_LOG="$TEST_TMPDIR/git-calls.log"

  ORIGINAL_SETTINGS='{
  "autoMemoryEnabled": false,
  "enabledPlugins": {
    "a@m": true
  }
}'
  # new_repo <dir> — a git work tree with .claude/settings.json committed.
  new_repo() {
    mkdir -p "$1/.claude"
    git -C "$1" init -q
    printf '%s\n' "$ORIGINAL_SETTINGS" >"$1/.claude/settings.json"
    git -C "$1" add .claude/settings.json
    git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m init
  }

  # Tracked and clean before the pass: restored byte-for-byte, tree clean.
  GWT="$TEST_TMPDIR/gwt-clean"
  new_repo "$GWT"
  cp "$GWT/.claude/settings.json" "$TEST_TMPDIR/settings.orig"
  seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
  reset_log
  : >"$GIT_LOG"
  STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT"
  assert_exit "a reap that rewrote a clean tracked settings file still exits 0" 0 "$RC"
  if cmp -s "$TEST_TMPDIR/settings.orig" "$GWT/.claude/settings.json"; then same=yes; else same=no; fi
  assert_eq "the tracked settings file is restored byte-for-byte" "yes" "$same"
  assert_eq "the worktree is clean after the pass" "" "$(git -C "$GWT" status --porcelain)"
  assert_contains "the restore is named in an info: line" "$OUT" "info: restored .claude/settings.json"
  assert_contains "the restore does not change the survivor result" "$OUT" "surviving 0"
  assert_eq "the restore brings no install record back" "0" "$(jq 'length' "$STATE")"

  # Tracked but already modified before the pass: left alone, warned about.
  GWT="$TEST_TMPDIR/gwt-modified"
  new_repo "$GWT"
  printf '{"edited": true}\n' >"$GWT/.claude/settings.json"
  seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
  reset_log
  : >"$GIT_LOG"
  STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT"
  assert_exit "a pre-modified settings file does not change the exit code" 0 "$RC"
  assert_contains "a pre-modified settings file is named in a warn: line" "$OUT" "warn: the uninstall CLI changed .claude/settings.json"
  assert_not_contains "a pre-modified settings file is not restored" "$OUT" "info: restored"
  assert_not_contains "no git restore runs over a pre-existing edit" "$(cat "$GIT_LOG")" "restore"
  assert_contains "the file is left exactly as the CLI wrote it" "$(cat "$GWT/.claude/settings.json")" '"enabledPlugins": {}'

  # A staged-only change (index differs from HEAD, worktree matches HEAD) is a
  # pre-existing edit too: classifying it clean would let the restore's
  # --staged drop it.
  GWT="$TEST_TMPDIR/gwt-staged"
  new_repo "$GWT"
  printf '{"staged": true}\n' >"$GWT/.claude/settings.json"
  git -C "$GWT" add .claude/settings.json
  printf '%s\n' "$ORIGINAL_SETTINGS" >"$GWT/.claude/settings.json"
  seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
  reset_log
  : >"$GIT_LOG"
  STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT"
  assert_exit "a staged-only change does not change the exit code" 0 "$RC"
  assert_contains "the staged change survives the pass" \
    "$(git -C "$GWT" show :.claude/settings.json 2>/dev/null)" '"staged": true'
  assert_not_contains "a staged-only change is not restored over" "$OUT" "info: restored"
  assert_contains "a staged-only change is warned about" "$OUT" "uncommitted changes before the pass"

  # assume-unchanged or skip-worktree hides a local edit from both diffs, so the
  # file would read clean and the restore would discard the hidden edit.
  for flag in assume-unchanged skip-worktree; do
    GWT="$TEST_TMPDIR/gwt-$flag"
    new_repo "$GWT"
    git -C "$GWT" update-index "--$flag" .claude/settings.json
    printf '{"hidden": true}\n' >"$GWT/.claude/settings.json"
    seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
    reset_log
    : >"$GIT_LOG"
    STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT"
    assert_exit "a $flag settings file does not change the exit code" 0 "$RC"
    assert_not_contains "a $flag settings file is not restored" "$OUT" "info: restored"
    assert_not_contains "no git restore runs over a $flag file" "$(cat "$GIT_LOG")" "restore"
    assert_contains "a $flag settings file is warned about" "$OUT" "assume-unchanged or skip-worktree is set"
  done

  # Untracked: left alone, warned about.
  GWT="$TEST_TMPDIR/gwt-untracked"
  mkdir -p "$GWT/.claude"
  git -C "$GWT" init -q
  printf '%s\n' "$ORIGINAL_SETTINGS" >"$GWT/.claude/settings.json"
  seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
  reset_log
  : >"$GIT_LOG"
  STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT"
  assert_exit "an untracked settings file does not change the exit code" 0 "$RC"
  assert_contains "an untracked settings file is warned about" "$OUT" "git does not track it here"
  assert_not_contains "no git restore runs on an untracked file" "$(cat "$GIT_LOG")" "restore"

  # Outside any git work tree (the orphaned-directory case): nothing restored,
  # no error. The only git call allowed is the work-tree probe itself.
  NOGIT="$TEST_TMPDIR/nogit"
  mkdir -p "$NOGIT/.claude"
  printf '%s\n' "$ORIGINAL_SETTINGS" >"$NOGIT/.claude/settings.json"
  if (cd "$NOGIT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    skip_case "the test temp dir sits inside a git work tree — the no-git case is unpinned here"
  else
    seed_state "$(jq -n --arg wt "$(native_of "$NOGIT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
    reset_log
    : >"$GIT_LOG"
    STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$NOGIT" --worktree-path "$NOGIT"
    assert_exit "outside a git work tree the reap still exits 0" 0 "$RC"
    assert_not_contains "outside a git work tree no error is printed" "$OUT" "error:"
    assert_contains "outside a git work tree a changed file is warned about" "$OUT" "not inside a git work tree"
    assert_eq "outside a git work tree only the work-tree probe calls git" \
      "rev-parse --is-inside-work-tree" "$(cat "$GIT_LOG")"
  fi

  # --dry-run: no uninstall, so no git call and no restore at all.
  GWT="$TEST_TMPDIR/gwt-dry"
  new_repo "$GWT"
  seed_state "$(jq -n --arg wt "$(native_of "$GWT")" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
  reset_log
  : >"$GIT_LOG"
  STUB_REWRITE_SETTINGS=1 EXTRA_PATH="$GIT_SHIM" run "$GWT" --worktree-path "$GWT" --dry-run
  assert_exit "--dry-run with a tracked settings file exits 0" 0 "$RC"
  assert_not_contains "--dry-run restores nothing" "$OUT" "restored"
  assert_eq "--dry-run makes no git call" "" "$(cat "$GIT_LOG")"
else
  skip_case "git not available — the settings-restore cases are unpinned here"
fi

# --- path normalization ---------------------------------------------------------
# The record is written by Claude Code in native form; a case- or
# separator-variant of the same directory must still match.
if [[ "$UNAME_S" == MINGW* || "$UNAME_S" == MSYS* || "$UNAME_S" == CYGWIN* ]]; then
  variant="$(printf '%s' "$WT_NATIVE" | tr '/' "\134" | tr '[:lower:]' '[:upper:]')"
  seed_state "$(jq -n --arg v "$variant" '[{id:"a@m",scope:"project",projectPath:$v}]')"
  reset_log
  run "$WT" --worktree-path "$WT"
  assert_exit "a case/separator variant of the same path still reaps" 0 "$RC"
  # Asserting the exit code alone would pass on the "nothing to reap" path too,
  # which is exactly how a backslash-blind matcher hides.
  assert_contains "the backslash-spelled record was matched, not skipped" "$OUT" "reaped a@m"
  assert_eq "the variant record is gone" "0" "$(jq 'length' "$STATE")"
else
  variant="${WT_NATIVE}/"
  seed_state "$(jq -n --arg v "$variant" '[{id:"a@m",scope:"project",projectPath:$v}]')"
  reset_log
  run "$WT" --worktree-path "$WT"
  assert_exit "a trailing-slash variant of the same path still reaps" 0 "$RC"
  assert_eq "the variant record is gone" "0" "$(jq 'length' "$STATE")"
fi

# --- dry run --------------------------------------------------------------------

seed_state "$(jq -n --arg wt "$WT_NATIVE" '[{id:"a@m",scope:"project",projectPath:$wt}]')"
reset_log
run "$WT" --worktree-path "$WT" --dry-run
assert_exit "--dry-run exits 0" 0 "$RC"
assert_contains "--dry-run names what it would remove" "$OUT" "would reap a@m"
assert_eq "--dry-run removes nothing" "1" "$(jq 'length' "$STATE")"
assert_not_contains "--dry-run issues no uninstall" "$(cat "$LOG")" "uninstall"

# --- a CLI no-op is reported, never escalated -----------------------------------
# `enumerated but not removable` is the shape a stale enumeration produces. The
# script must report it and must not follow the CLI's own `--scope user` hint.

seed_state '[]'
reset_log
# Enumeration is stubbed to report a record the uninstall path will not honor.
cat >"$STUB_DIR/claude" <<'STUB2'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  p="$(pwd -W 2>/dev/null || pwd -P)"
  jq -n --arg p "$p" '{installed: [{id:"z@m",scope:"project",projectPath:$p}]}'
  exit 0
fi
printf 'Failed to uninstall plugin "z@m": Plugin "z@m" is installed in user scope, not project. Use --scope user to uninstall.\n' >&2
exit 1
STUB2
chmod +x "$STUB_DIR/claude"
run "$WT" --worktree-path "$WT"
assert_exit "a record that survives the pass exits 1" 1 "$RC"
assert_contains "the no-op is reported" "$OUT" "no-op for z@m"
assert_contains "the report forbids the user-scope escalation" "$OUT" "do NOT retry it with"
assert_contains "survivors are surfaced" "$OUT" "survived the pass"
assert_not_contains "never escalates to user scope" "$(cat "$LOG")" "-s user"
assert_contains "a no-op uninstall still passes --keep-data" "$(cat "$LOG")" "--keep-data"

# --- visible degrade ------------------------------------------------------------

cat >"$STUB_DIR/claude" <<'STUB3'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_CALL_LOG"
exit 1
STUB3
chmod +x "$STUB_DIR/claude"
seed_state '[]'
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "an enumeration failure degrades with exit 3" 3 "$RC"
assert_contains "the degrade is visible, not silent" "$OUT" "warn:"

# --- a POST-reap enumeration failure is UNVERIFIED, never success ---------------
# The pre-reap enumeration failure already degrades (exit 3). The post-reap one
# is the pass's only proof that anything was actually removed, so absorbing it
# into "zero survivors" would report a confirmed clean reap having confirmed
# nothing — and the caller acts on that by deleting the directory.

cat >"$STUB_DIR/claude" <<'STUB4'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_CALL_LOG"
if [[ "${1:-}" == "plugin" && "${2:-}" == "list" ]]; then
  n=0
  [[ -s "$STUB_LIST_COUNT" ]] && n="$(cat "$STUB_LIST_COUNT")"
  n=$((n + 1))
  printf '%s' "$n" >"$STUB_LIST_COUNT"
  # Call 1 is the pre-reap enumeration and succeeds; call 2 is the post-reap
  # verification and fails — the transient this case exists to pin.
  [[ "$n" -ge 2 ]] && exit 1
  p="$(pwd -W 2>/dev/null || pwd -P)"
  jq -n --arg p "$p" '{installed: [{id:"v@m",scope:"project",projectPath:$p}]}'
  exit 0
fi
printf 'Successfully uninstalled plugin: v@m (scope: project)\n'
exit 0
STUB4
chmod +x "$STUB_DIR/claude"
: >"$TEST_TMPDIR/listcount"
seed_state '[]'
reset_log
run "$WT" --worktree-path "$WT"
assert_exit "a failed post-reap enumeration degrades with exit 3, not 0" 3 "$RC"
assert_contains "the pass is called unverified" "$OUT" "UNVERIFIED"
assert_contains "the survivor count is reported as unknown, not zero" "$OUT" "surviving UNKNOWN"
# The needle is the success SENTENCE, not the phrase — the degrade text itself
# legitimately contains "gone" while denying it ("nothing confirmed any record is gone").
assert_not_contains "never emits the clean-reap line" "$OUT" "ok: every project- and local-scope"
assert_contains "the uninstall that did run is still reported" "$OUT" "reaped 1"

# --- the documented trailing-separator normalization ----------------------------
# `cleanup.md` Step 4a disqualifies a symlinked orphaned-directory candidate with
# `test -L`. A trailing separator makes POSIX resolve THROUGH the link, so the
# test answers about the target and the disqualifier silently passes — while
# `find` does not descend a symlinked start point, so the link also reads empty.
# That pairing is what turns a live directory into an "orphaned husk". The rule
# lives in prose an agent executes, so this fixture is what keeps it true.

LINKDIR="$TEST_TMPDIR/linkcase"
mkdir -p "$LINKDIR/target"
: >"$LINKDIR/target/busy.txt"
MSYS=winsymlinks:nativestrict ln -s "$LINKDIR/target" "$LINKDIR/link" 2>/dev/null || true
if [[ -L "$LINKDIR/link" ]]; then
  raw="$LINKDIR/link/"
  if [[ -L "$raw" ]]; then detected=yes; else detected=no; fi
  assert_eq "a trailing separator defeats the raw symlink test" "no" "$detected"

  normalized="${raw%/}"
  if [[ -L "$normalized" ]]; then detected=yes; else detected=no; fi
  assert_eq "stripping the trailing separator restores the symlink test" "yes" "$detected"

  assert_eq "find does not descend a symlinked start point, so the link reads empty" \
    "" "$(find "$LINKDIR/link" -mindepth 1 2>/dev/null | head -1)"
else
  skip_case "no real symlink on this platform — the trailing-separator rule is unpinned here"
fi

# The documented normalization must strip EVERY trailing separator the
# platform recognizes — and nothing more. `${path%/}` alone strips one forward
# slash, leaving a doubled separator (or, on Windows shells, a pasted trailing
# backslash) in place, and either survivor re-opens the symlink bypass above.
# Off Windows, `\` is a legal filename byte (the same gated rule
# worktree-create.sh applies to its root normalization), so a candidate
# literally named `link\` must survive untouched — stripping it would point
# every qualifying test and the reap at a different sibling path. Pure string
# manipulation, so it is pinned even where the symlink fixture must skip.
normalize_candidate() {
  local path="$1"
  case "$UNAME_S" in
  MINGW* | MSYS* | CYGWIN*) while [[ "$path" == */ || "$path" == *\\ ]]; do path="${path%?}"; done ;;
  *) while [[ "$path" == */ ]]; do path="${path%?}"; done ;;
  esac
  printf '%s' "$path"
}
assert_eq "normalization strips every trailing forward slash" "x/link" "$(normalize_candidate "x/link//")"
if [[ "$UNAME_S" == MINGW* || "$UNAME_S" == MSYS* || "$UNAME_S" == CYGWIN* ]]; then
  assert_eq "windows shell: a trailing backslash is a separator and strips" "x/link" "$(normalize_candidate "x/link\\")"
  assert_eq "windows shell: mixed trailing separators all strip" "x/link" "$(normalize_candidate "x/link/\\")"
else
  assert_eq "posix: a trailing backslash is a filename byte and survives" "x/link\\" "$(normalize_candidate "x/link\\")"
  assert_eq "posix: only the forward slash strips from a mixed tail" "x/link\\" "$(normalize_candidate "x/link\\/")"
fi

[[ $FAILED -eq 0 ]] || exit 1
printf '\nAll %d cases passed.\n' "$CASE_NUM"
