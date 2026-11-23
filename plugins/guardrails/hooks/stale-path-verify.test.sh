#!/usr/bin/env bash

# shellcheck disable=SC2016
# Every fixture below is markdown fed to the hook as literal data. Backticks are
# the code-span delimiters the hook scans for and `$`/`{}` appear inside
# placeholder fixtures on purpose — single quotes are required so none of it
# expands. Disabled file-wide rather than on individual lines.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/stale-path-verify.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

unset CLAUDE_PROJECT_DIR

export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/plugin-data"

export CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30

git_c() { git -C "$1" -c user.email=t@t.test -c user.name=t -c commit.gpgsign=false "${@:2}"; }

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
mkdir -p "$REPO/docs" "$REPO/.claude" "$REPO/lib" "$REPO/tools" "$REPO/scratch" \
  "$REPO/plugins/re-anchor/context" "$REPO/plugins/discipline/context"
echo keep >"$REPO/scratch/keep.md"
echo real >"$REPO/docs/real.md"
echo gone >"$REPO/docs/gone.md"
echo settings >"$REPO/.claude/settings.json"
echo keep >"$REPO/lib/keep.js"
echo emit >"$REPO/tools/legacy-emit.sh"
echo anchor >"$REPO/plugins/re-anchor/context/re-anchor-audit-correct.md"
git_c "$REPO" add -A >/dev/null 2>&1
git_c "$REPO" commit -qm seed >/dev/null 2>&1

git_c "$REPO" rm -q "docs/gone.md" >/dev/null 2>&1
git_c "$REPO" mv "plugins/re-anchor/context/re-anchor-audit-correct.md" \
  "plugins/discipline/context/re-anchor-audit-correct.md" >/dev/null 2>&1
git_c "$REPO" commit -qm "move and delete" >/dev/null 2>&1

git_c "$REPO" mv "tools/legacy-emit.sh" "tools/current-emit.sh" >/dev/null 2>&1
git_c "$REPO" commit -qm rename >/dev/null 2>&1

BRANCH_BASE=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
git -C "$REPO" checkout -q -b abandoned
mkdir -p "$REPO/scratch"
echo x >"$REPO/scratch/branch-only.md"
git_c "$REPO" add scratch/branch-only.md >/dev/null 2>&1
git_c "$REPO" commit -qm "branch add" >/dev/null 2>&1
git_c "$REPO" rm -q scratch/branch-only.md >/dev/null 2>&1
git_c "$REPO" commit -qm "branch delete" >/dev/null 2>&1
git -C "$REPO" checkout -q "$BRANCH_BASE"

TARGET="$REPO/notes.md"
: >"$TARGET"

GUARD_UNDER_TEST="$HOOK"


assert_run_helpers_propagate_exit


run 'The shared spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md` today.'
assert_exit "deleted path in code span → exit 0 (advisory)" 0 "$?"
assert_contains "deleted path → named" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"
assert_contains "deleted path → count" "$OUT" "cited path(s) in"

assert_contains "unique surviving basename → moved-file hint" "$OUT" \
  "plugins/discipline/context/re-anchor-audit-correct.md"

assert_absent "advisory carries no verdict trailer" "$OUT" "Detect-then-judge"
assert_contains "advisory exempts a deliberate deletion record" "$OUT" \
  "A path cited as a deletion record is correct as written."

run_edit 'Now cites `plugins/re-anchor/context/re-anchor-audit-correct.md` instead.'
assert_contains "Edit hunk scanned via new_string" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"

PARTIAL="$REPO/partial.md"
printf 'Untouched `tools/legacy-emit.sh` here.\nNow cites `docs/gone.md` today.\n' >"$PARTIAL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL" 'gone')" 2>&1)
RC=$?
assert_exit "bare-substring Edit hunk → exit 0" 0 "$RC"
assert_contains "bare-substring Edit hunk → containing citation recovered" "$OUT" \
  "  docs/gone.md"

assert_absent "reconstruction does NOT report an untouched neighbor" "$OUT" \
  "legacy-emit"

SEGSHARE="$REPO/segshare.md"
printf 'Untouched `docs/gone.md` here.\nThe docs folder was reorganized today.\n' >"$SEGSHARE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SEGSHARE" 'The docs folder was reorganized today.')" 2>&1)
RC=$?
assert_exit "prose hunk sharing a path segment → exit 0" 0 "$RC"
assert_silent "hunk sharing only a path SEGMENT does not drag in an untouched citation" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SEGSHARE" 'docs')" 2>&1)
RC=$?
assert_exit "bare-fragment hunk → exit 0" 0 "$RC"
assert_silent "bare-fragment hunk does not adjudicate an untouched citation" "$OUT"

SHORTFRAG="$REPO/shortfrag.md"
printf 'See `docs/gone.md` here.\n' >"$SHORTFRAG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SHORTFRAG" 'md')" 2>&1)
RC=$?
assert_exit "two-character partial-edit anchor → exit 0" 0 "$RC"
assert_contains "two-character partial-edit anchor → stale citation recovered" "$OUT" \
  "  docs/gone.md"

ONELINE="$REPO/oneline.md"
printf 'The docs folder and the docs tree both hold `docs/gone.md` today.\n' >"$ONELINE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$ONELINE" 'docs')" 2>&1)
RC=$?
assert_exit "anchor occurring twice on one line → exit 0" 0 "$RC"
assert_silent "two occurrences on a single line are ambiguous, not unique" "$OUT"

OVERLAP="$REPO/overlap.md"
printf 'The docs/docs/docs tree still cites `docs/gone.md` today.\n' >"$OVERLAP"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$OVERLAP" 'docs/docs')" 2>&1)
RC=$?
assert_exit "self-overlapping anchor → exit 0" 0 "$RC"
assert_silent "self-overlapping anchor is ambiguous, not unique" "$OUT"

REPLALL="$REPO/replall.md"
printf 'First `docs/gone.md` here.\nSecond `docs/gone.md` there.\n' >"$REPLALL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_json "$REPLALL" 'gone')" 2>&1)
RC=$?
assert_exit "replace_all Edit → exit 0" 0 "$RC"
assert_contains "replace_all → repeated anchor still adjudicated" "$OUT" \
  "  docs/gone.md"

run 'Per `plugins/re-anchor/context/re-anchor-audit-correct.md:12` the rule applies.'
assert_contains "line citation suffix stripped → still fires" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"

run 'Run `tools/legacy-emit.sh` to build.'
assert_contains "renamed-away path fires (--no-renames in effect)" "$OUT" \
  "  tools/legacy-emit.sh"

ROOT_FIRE="$TEST_TMPDIR/root-fire-repo"
mkdir -p "$ROOT_FIRE/docs"
git -C "$ROOT_FIRE" init -q
printf 'contrib\n' >"$ROOT_FIRE/CONTRIBUTING.md"
printf 'readme\n' >"$ROOT_FIRE/docs/readme.md"
git_c "$ROOT_FIRE" add -A >/dev/null 2>&1
git_c "$ROOT_FIRE" commit -qm seed >/dev/null 2>&1
git_c "$ROOT_FIRE" rm -q CONTRIBUTING.md >/dev/null 2>&1
git_c "$ROOT_FIRE" commit -qm "drop root contributing" >/dev/null 2>&1
ROOT_FIRE_TARGET="$ROOT_FIRE/notes.md"
: >"$ROOT_FIRE_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$ROOT_FIRE" bash "$HOOK" \
  <<<"$(write_json "$ROOT_FIRE_TARGET" 'See `CONTRIBUTING.md` for the old process.')" 2>&1)
RC=$?
assert_exit "deleted root-level path → exit 0 (advisory)" 0 "$RC"
assert_contains "deleted root-level path fires" "$OUT" "  CONTRIBUTING.md"

ROOT_QUIET="$TEST_TMPDIR/root-quiet-repo"
mkdir -p "$ROOT_QUIET/docs" "$ROOT_QUIET/plugins/a"
git -C "$ROOT_QUIET" init -q
printf 'root\n' >"$ROOT_QUIET/README.md"
printf 'nested\n' >"$ROOT_QUIET/docs/README.md"
printf 'skill\n' >"$ROOT_QUIET/plugins/a/SKILL.md"
git_c "$ROOT_QUIET" add -A >/dev/null 2>&1
git_c "$ROOT_QUIET" commit -qm seed >/dev/null 2>&1
git_c "$ROOT_QUIET" rm -q README.md >/dev/null 2>&1
git_c "$ROOT_QUIET" commit -qm "drop root readme" >/dev/null 2>&1
ROOT_QUIET_TARGET="$ROOT_QUIET/notes.md"
: >"$ROOT_QUIET_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$ROOT_QUIET" bash "$HOOK" \
  <<<"$(write_json "$ROOT_QUIET_TARGET" 'Every repo has a `README.md`.')" 2>&1)
RC=$?
assert_exit "generic root README.md mention → exit 0" 0 "$RC"
assert_silent "generic root README.md mention stays quiet after root deletion" "$OUT"

ROOT_PKG="$TEST_TMPDIR/root-pkg-repo"
mkdir -p "$ROOT_PKG"
git -C "$ROOT_PKG" init -q
printf '{}\n' >"$ROOT_PKG/package.json"
git_c "$ROOT_PKG" add package.json >/dev/null 2>&1
git_c "$ROOT_PKG" commit -qm seed >/dev/null 2>&1
git_c "$ROOT_PKG" rm -q package.json >/dev/null 2>&1
git_c "$ROOT_PKG" commit -qm "drop package.json" >/dev/null 2>&1
ROOT_PKG_TARGET="$ROOT_PKG/notes.md"
: >"$ROOT_PKG_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$ROOT_PKG" bash "$HOOK" \
  <<<"$(write_json "$ROOT_PKG_TARGET" 'Bump deps in `package.json`.')" 2>&1)
RC=$?
assert_exit "generic root package.json mention → exit 0" 0 "$RC"
assert_silent "generic root package.json mention stays quiet after root deletion" "$OUT"


run 'Consumers put their suite under `.claude/testing/e2e.md`.'
assert_exit "consumer config path → exit 0" 0 "$?"
assert_silent "consumer config path never in this repo → silent" "$OUT"

run 'The generator lives at `lib/emit-slides.js` beside the skill.'
assert_silent "subtree-relative citation → silent" "$OUT"

run 'CREATE: `docs/new-thing.md` in the next step.'
assert_silent "forward-looking path never committed → silent" "$OUT"

run 'For instance `docs/example.md` would do.'
assert_silent "illustrative placeholder → silent" "$OUT"

run 'Write it as `[the guide](docs/gone.md)` in prose.'
assert_silent "link literal inside a code span → silent" "$OUT"

run 'See [the guide](docs/gone.md) for details.'
assert_silent "link destination to a removed file → silent (links out of scope)" "$OUT"

run 'Scratch notes were at `scratch/branch-only.md`.'
assert_silent "path deleted only off HEAD → silent" "$OUT"

run 'Upstream lives at `docs/never-existed.md` and `plugins/other/thing.sh`.'
assert_silent "coincident first segment with no provenance → silent" "$OUT"

run 'Read `docs/real.md` before starting.'
assert_silent "existing path → silent" "$OUT"

run 'Glob it with `plugins/*/SKILL.md` or `docs/**/*.md`.'
assert_silent "glob patterns → silent" "$OUT"

run 'Placeholders like `plugins/<name>/plugin.json` and `docs/${topic}/PLAN.md`.'
assert_silent "placeholder metacharacters → silent" "$OUT"

run 'Fetch <https://example.com/docs/gone.md> and `https://a.test/docs/gone.md`.'
assert_silent "URLs → silent" "$OUT"

run 'Absolute paths `/etc/hosts` and `C:/Windows/system32/x.dll`.'
assert_silent "absolute paths → silent (hardcoded-path-check owns those)" "$OUT"

run 'User config at `~/.claude/settings.json`.'
assert_silent "home-relative → silent" "$OUT"

run 'Parent escape `../docs/gone.md` and `docs/../plugins/x.sh`.'
assert_silent "parent-escaping paths → silent" "$OUT"

run 'Prose mentioning plugins/re-anchor/context/re-anchor-audit-correct.md outside a span.'
assert_silent "unquoted prose path → not scanned" "$OUT"

run 'A whole command: `cp docs/gone.md docs/real.md`.'
assert_silent "multi-token code span → not a path candidate" "$OUT"

CHANGELOG="$REPO/CHANGELOG.md"
: >"$CHANGELOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$CHANGELOG" 'Removed `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
RC=$?
assert_exit "CHANGELOG.md → exit 0" 0 "$RC"
assert_silent "CHANGELOG.md citing a removed path → silent" "$OUT"

SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$SCRIPT" 'cat plugins/re-anchor/context/re-anchor-audit-correct.md')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"


UNBORN="$TEST_TMPDIR/unborn"
mkdir -p "$UNBORN/docs"
git -C "$UNBORN" init -q
UNBORN_TARGET="$UNBORN/notes.md"
: >"$UNBORN_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$UNBORN" bash "$HOOK" \
  <<<"$(write_json "$UNBORN_TARGET" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "unborn HEAD → exit 0" 0 "$RC"
assert_silent "unborn HEAD → silent, no git error leaked" "$OUT"

NOGIT="$TEST_TMPDIR/nogit"
mkdir -p "$NOGIT/docs"
NOGIT_TARGET="$NOGIT/notes.md"
: >"$NOGIT_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$NOGIT" bash "$HOOK" \
  <<<"$(write_json "$NOGIT_TARGET" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "non-git directory → exit 0" 0 "$RC"
assert_silent "non-git directory → silent" "$OUT"


SPARSE="$TEST_TMPDIR/sparse"
mkdir -p "$SPARSE/docs"
git -C "$SPARSE" init -q
echo v1 >"$SPARSE/docs/restored.md"
echo v1 >"$SPARSE/docs/truly-gone.md"
git_c "$SPARSE" add -A >/dev/null 2>&1
git_c "$SPARSE" commit -qm seed >/dev/null 2>&1
git_c "$SPARSE" rm -q docs/restored.md docs/truly-gone.md >/dev/null 2>&1
git_c "$SPARSE" commit -qm delete >/dev/null 2>&1
mkdir -p "$SPARSE/docs"
echo v2 >"$SPARSE/docs/restored.md"
git_c "$SPARSE" add docs/restored.md >/dev/null 2>&1
git_c "$SPARSE" commit -qm restore >/dev/null 2>&1
SPARSE_TARGET="$SPARSE/notes.md"
: >"$SPARSE_TARGET"

git -C "$SPARSE" update-index --skip-worktree docs/restored.md >/dev/null 2>&1
rm -f "$SPARSE/docs/restored.md"
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "unmaterialized sparse path → exit 0" 0 "$RC"
assert_silent "tracked at HEAD but not materialized → silent (index consulted)" "$OUT"

git -C "$SPARSE" update-index --no-skip-worktree docs/restored.md >/dev/null 2>&1
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "unstaged deletion → exit 0" 0 "$RC"
assert_contains "unstaged deletion is not a sparse exemption → fires" "$OUT" \
  "  docs/restored.md"

git -C "$SPARSE" update-index --assume-unchanged docs/restored.md >/dev/null 2>&1
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "assume-unchanged deletion → exit 0" 0 "$RC"
assert_contains "assume-unchanged is not a sparse exemption → fires" "$OUT" \
  "  docs/restored.md"

git -C "$SPARSE" update-index --skip-worktree docs/restored.md >/dev/null 2>&1
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "skip-worktree + assume-unchanged → exit 0" 0 "$RC"
assert_silent "lowercase s still carries the skip-worktree exemption → silent" "$OUT"
git -C "$SPARSE" update-index --no-assume-unchanged docs/restored.md >/dev/null 2>&1

OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/truly-gone.md` first.')" 2>&1)
assert_contains "deleted and never restored → still fires" "$OUT" \
  "  docs/truly-gone.md"

DANGLE="$TEST_TMPDIR/dangle"
mkdir -p "$DANGLE/docs"
git -C "$DANGLE" init -q
echo v1 >"$DANGLE/docs/link.md"
git_c "$DANGLE" add -A >/dev/null 2>&1
git_c "$DANGLE" commit -qm seed >/dev/null 2>&1
git_c "$DANGLE" rm -q docs/link.md >/dev/null 2>&1
git_c "$DANGLE" commit -qm delete >/dev/null 2>&1
DANGLE_TARGET="$DANGLE/notes.md"
: >"$DANGLE_TARGET"
if ln -s "missing-target.md" "$DANGLE/docs/link.md" 2>/dev/null && [[ -L "$DANGLE/docs/link.md" ]]; then
  OUT=$(CLAUDE_PROJECT_DIR="$DANGLE" bash "$HOOK" \
    <<<"$(write_json "$DANGLE_TARGET" 'Read `docs/link.md` first.')" 2>&1)
  RC=$?
  assert_exit "dangling symlink → exit 0" 0 "$RC"
  assert_silent "dangling symlink is a present path → silent" "$OUT"
else
  assert_contains "existence gate accepts the link itself" "$(cat "$HOOK")" \
    '|| -L "$REPO_ROOT/${cand%/}"'
fi


SHALLOW_REPO="$TEST_TMPDIR/shallow"
if git clone -q --no-local --depth 1 "$REPO" "$SHALLOW_REPO" >/dev/null 2>&1 &&
  [[ "$(git -C "$SHALLOW_REPO" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
  SHALLOW_TARGET="$SHALLOW_REPO/notes.md"
  : >"$SHALLOW_TARGET"

  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'Read `docs/real.md` first.')" 2>&1)
  assert_silent "shallow clone with nothing absent → silent" "$OUT"

  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'The spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
  RC=$?
  assert_exit "shallow clone → exit 0" 0 "$RC"
  assert_contains "shallow clone → visible prerequisite notice" "$OUT" "clone is shallow"
  assert_contains "shallow clone → notice names the remedy" "$OUT" "fetch --unshallow"
  assert_absent "shallow clone → the user is told, not the model" "$OUT" "additionalContext"
  assert_absent "shallow clone → no finding claimed" "$OUT" "deleted from this repo"

  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'The spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
  assert_silent "shallow clone → notice is once per session, not per write" "$OUT"

  SHALLOW_TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
  SHALLOW_SINK="$(make_sink "cat >\"$SHALLOW_TEL\"")"
  CLAUDE_PROJECT_DIR="$SHALLOW_REPO" HOOK_TELEMETRY_SINK="$SHALLOW_SINK" \
    bash "$HOOK" <<<"$(write_json "$SHALLOW_TARGET" 'The spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" >/dev/null 2>&1 || true
  if wait_for_sink "$SHALLOW_TEL"; then
    assert_contains "shallow clone → telemetry status skipped, not ok" \
      "$(jq -r '.status' "$SHALLOW_TEL")" "skipped"
  else
    bad "shallow clone: no telemetry envelope written"
  fi
else
  bad "shallow clone: fixture could not be built"
fi


WALK_REPO="$TEST_TMPDIR/walkfail"
mkdir -p "$WALK_REPO/docs"
git -C "$WALK_REPO" init -q >/dev/null 2>&1
echo early >"$WALK_REPO/docs/early.md"
echo late >"$WALK_REPO/docs/late.md"
echo keep >"$WALK_REPO/docs/keep.md"
git_c "$WALK_REPO" add -A >/dev/null 2>&1
git_c "$WALK_REPO" commit -qm seed >/dev/null 2>&1
git_c "$WALK_REPO" rm -q docs/early.md >/dev/null 2>&1
git_c "$WALK_REPO" commit -qm "drop early" >/dev/null 2>&1
git_c "$WALK_REPO" rm -q docs/late.md >/dev/null 2>&1
git_c "$WALK_REPO" commit -qm "drop late" >/dev/null 2>&1

WALK_TREE=$(git -C "$WALK_REPO" rev-parse "HEAD~2^{tree}" 2>/dev/null | tr -d '\r')
[[ -n "$WALK_TREE" ]] &&
  rm -f "$WALK_REPO/.git/objects/${WALK_TREE:0:2}/${WALK_TREE:2}"

WALK_OUT=$(git -C "$WALK_REPO" log HEAD --no-renames --diff-filter=D --name-only \
  --pretty=format: 2>/dev/null)
WALK_RC=$?

if ((WALK_RC != 0)) && [[ "$WALK_OUT" == *docs/late.md* ]] &&
  [[ "$(git -C "$WALK_REPO" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" != "true" ]]; then
  WALK_TARGET="$WALK_REPO/notes.md"
  : >"$WALK_TARGET"

  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'Read `docs/keep.md` first.')" 2>&1)
  assert_silent "incomplete walk with nothing absent → silent" "$OUT"

  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'The spoke is `docs/late.md`.')" 2>&1)
  RC=$?
  assert_exit "incomplete walk → exit 0" 0 "$RC"
  assert_contains "incomplete walk → visible prerequisite notice" "$OUT" "stale-path-verify is off"
  assert_contains "incomplete walk → notice names the diagnostic" "$OUT" "diff-filter=D"
  assert_absent "incomplete walk → the user is told, not the model" "$OUT" "additionalContext"
  assert_absent "incomplete walk → partial set never adjudicated" "$OUT" "deleted from this repo"

  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'The spoke is `docs/late.md`.')" 2>&1)
  assert_silent "incomplete walk → notice is once per session, not per write" "$OUT"
else
  bad "incomplete history walk: fixture could not be built"
fi


OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Cite `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"


OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

UNI_REPO="$TEST_TMPDIR/uni-repo"
mkdir -p "$UNI_REPO/docs"
git -C "$UNI_REPO" init -q
printf 'x\n' >"$UNI_REPO/docs/café.md"
git_c "$UNI_REPO" add docs/café.md >/dev/null 2>&1
git_c "$UNI_REPO" commit -qm add >/dev/null 2>&1
git_c "$UNI_REPO" rm -q docs/café.md >/dev/null 2>&1
git_c "$UNI_REPO" commit -qm del >/dev/null 2>&1
UNI_TARGET="$UNI_REPO/notes.md"
: >"$UNI_TARGET"
out=$(CLAUDE_PROJECT_DIR="$UNI_REPO" bash "$HOOK" <<<"$(write_json "$UNI_TARGET" 'See `docs/café.md`.')" 2>&1)
assert_contains "non-ASCII deleted path fires" "$out" "  docs/café.md"


HOOK_SRC=$(cat "$HOOK")

assert_contains "jq guard: uses hook::require jq" "$HOOK_SRC" 'hook::require jq'

assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root_to REPO_ROOT "$FILE_DIR"'
assert_contains "repo root anchor uses parameter expansion" "$HOOK_SRC" 'FILE_DIR="${FILE%/*}"'
assert_absent "repo root anchor forks no subshell" "$HOOK_SRC" 'hook::repo_root "$(dirname'
assert_file_dir_seam "$HOOK"

assert_contains "tracked-file list is warmed only when a candidate exists" "$HOOK_SRC" \
  '((${#RAW_TOKENS[@]})) && ensure_tracked_files'

assert_contains "history walk passes --no-renames" "$HOOK_SRC" '--no-renames'
assert_contains "history walk uses core.quotePath=false" "$HOOK_SRC" 'core.quotePath=false'
assert_contains "history walk includes merge commits" "$HOOK_SRC" 'log HEAD -m'
assert_contains "history walk is scoped to HEAD, not --all" "$HOOK_SRC" 'log HEAD'
assert_absent "history walk does not read --all" "$HOOK_SRC" 'log --all'
assert_contains "root basename ambiguity discriminator" "$HOOK_SRC" 'root_basename_is_ambiguous'


TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
CLAUDE_PROJECT_DIR="$REPO" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Cite `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "stale-path-verify"
  assert_contains "telemetry: status ok" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the path" "$(jq -r '.data.findings[]' "$TEL")" \
    "plugins/re-anchor/context/re-anchor-audit-correct.md"
  assert_absent "telemetry: file path is repo-relative, never absolute" \
    "$(jq -r '.data.file' "$TEL")" "$TEST_TMPDIR"
else
  bad "telemetry: no envelope written"
fi

parity "dispatched parity: deleted path" 'See `docs/gone.md` here.' 0 \
  "  docs/gone.md"
parity "dispatched parity: surviving path" 'See `docs/real.md` here.' 0 ""
parity "dispatched parity: renamed-away path" 'Run `tools/legacy-emit.sh` to build.' 0 \
  "  tools/legacy-emit.sh"

TWIN_CASES=(
  'See `docs/gone.md` and `a b` here' '``x`' 'a`b`c`d' '`unclosed docs/gone.md' '````' '` `'
  $'line one `x.md`\r\nline two `y.md`\r\n' $'\t`tab.md`\t\n   \n\t\n' $'v\vf\f`z.md`'
  'a- ..ab -x x a.b.c 12 1a -- gone-md gone_md' 'Root `gone.md` and `README.md` x' $'\n\n`a`\n\n`b`\n'
  'a\b `c:\d` "q" (p) [s] {c} $v ~h' "$(printf '%s\n' {1..45} | sed 's/.*/fix `docs\/gone.md` n&/')" # portability-ok: \b is literal text in a single-quoted test string, not a grep word boundary
)
TWIN_OUT=$(
  source "$HOOK_DIR/hook-utils.sh"
  eval "$(sed -n '/^# shellcheck disable=SC2329 # reached through/,/^# emit_tokens. lines into SPV_OUT/p' "$HOOK")"
  SPV_OUT=()
  lines() { ((${#SPV_OUT[@]})) && printf '%s\n' "${SPV_OUT[@]}"; }
  for t in "${TWIN_CASES[@]}"; do
    spv_plain "$t" || {
      printf 'bad %q gate rejected plain text\n' "$t"
      continue
    }
    hook::_c_locale spv__spans "$t"
    # shellcheck disable=SC2016  # backticks are literal ERE data
    # portability-ok: grep -oE is only-matching extended regex, not GNU grep -P
    [[ "$(lines)" == "$(printf '%s' "$t" | grep -oE '`[^`]+`' | sed -E 's/^`+//; s/`+$//')" ]] ||
      printf 'bad %q spans\n' "$t"
    hook::_c_locale spv__residue_tokens "$t"
    # shellcheck disable=SC2016  # backticks are literal ERE data
    [[ "$(lines | LC_ALL=C sort)" == "$(printf '%s' "$t" | sed -E 's/`[^`]*`//g' |
      grep -oE '[A-Za-z0-9][A-Za-z0-9._-]{1,}' | LC_ALL=C sort -u)" ]] || printf 'bad %q residue tokens\n' "$t" # portability-ok: grep -oE is only-matching extended regex, not GNU grep -P
    hook::_c_locale spv__nonblank "$t"
    [[ "$(lines)" == "$(printf '%s' "$t" | grep -vE '^[[:space:]]*$')" ]] || printf 'bad %q nonblank\n' "$t" # portability-ok: grep -vE drops blank lines, not GNU grep -P
    hook::_c_locale spv__nonblank "$t" 40
    [[ "$(lines)" == "$(printf '%s' "$t" | grep -vE '^[[:space:]]*$' | head -40)" ]] || printf 'bad %q nonblank 40\n' "$t" # portability-ok: grep -vE drops blank lines, not GNU grep -P
  done
  for t in 'é `docs/gone.md`' $'esc \x1b[0m `x.md`' $'del \x7f'; do
    spv_plain "$t" && printf 'bad %q gate accepted\n' "$t"
  done
  echo twins-ok
)
if [[ "$TWIN_OUT" == twins-ok ]]; then
  ok "builtin twins match the grep/sed/sort/head pipelines on ${#TWIN_CASES[@]} texts, and the gate sends other bytes to the pipelines" # portability-ok: grep token is prose or grep -E/-o/-v, not GNU grep -P
else
  bad "builtin twins differ from the pipelines: $TWIN_OUT"
fi

# --- The word-anchor split counter answers what the character walk answered --
# spv_word_occurrences replaced a per-character awk walk for word anchors. The
# walk is kept here as the reference and run in the hook's locale; the split
# runs under C. Non-ASCII letters, invalid UTF-8 and CR beside the anchor,
# underscores, a digit start and a long line are the cases where they could part.
# spellchecker:off
OCC_WALK='BEGIN { n = 0; a = ENVIRON["HOOK_ANCHOR"] }
{ p = 1
  while (p <= length($0)) {
    if (substr($0, p, 1) !~ /[A-Za-z0-9_]/) { p++; continue }
    if (p > 1 && substr($0, p - 1, 1) ~ /[A-Za-z0-9_]/) { p++; continue }
    end = p
    while (end <= length($0) && substr($0, end, 1) ~ /[A-Za-z0-9_]/) end++
    if (substr($0, p, end - p) == a) { n++; p = end; continue }
    p++ } }
END { print n + 0 }'
OCC_FILE="$REPO/occ-cases.txt"
printf 'foo éfoo fooé foo_bar foo\r\n\xfffoo\xff 9foo foo9 _foo x.foo foo-x\n%s foo\n' \
  "$(printf 'w%.0s ' {1..6000})" >"$OCC_FILE"
# spellchecker:on
OCC_OUT=$(
  source "$HOOK_DIR/hook-utils.sh"
  eval "$(sed -n '/^# shellcheck disable=SC2329 # reached through/,/^# emit_tokens. lines into SPV_OUT/p' "$HOOK")"
  for loc in C.UTF-8 C; do
    for a in foo foo_bar 9foo foo9 _foo x w S3MARKb; do
      want=$(HOOK_ANCHOR="$a" LC_ALL=$loc awk "$OCC_WALK" "$OCC_FILE" 2>/dev/null)
      got=$(LC_ALL=$loc spv_word_occurrences "$a" "$OCC_FILE" 2>/dev/null)
      [[ "$want" == "$got" ]] || printf 'bad %s %s walk=%s split=%s\n' "$loc" "$a" "$want" "$got"
    done
  done
  echo occ-ok
)
if [[ "$OCC_OUT" == occ-ok ]]; then
  ok "word-anchor split counter matches the character walk (non-ASCII, invalid UTF-8, CR, long line)"
else
  bad "word-anchor split counter differs from the character walk: $OCC_OUT"
fi

FIXED_WALK='BEGIN { n = 0; a = ENVIRON["HOOK_ANCHOR"] }
{ p = 1
  while (p <= length($0)) {
    i = index(substr($0, p), a)
    if (i == 0) break
    n++
    p = p + i } }
END { print n + 0 }'
FIXED_FILE="$REPO/fixed-occ.txt"
printf 'docs/docs/docs\ndocs/old.md and docs/old.md\né docs/old.md\nsee docs/docs\n' >"$FIXED_FILE"
FIXED_OUT=$(
  source "$HOOK_DIR/hook-utils.sh"
  eval "$(sed -n '/^# shellcheck disable=SC2329 # reached through/,/^# emit_tokens. lines into SPV_OUT/p' "$HOOK")"
  for loc in C.UTF-8 C; do
    for a in 'docs/docs' 'docs/old.md' 'docs/docs/docs' 'nope'; do
      want=$(HOOK_ANCHOR="$a" LC_ALL=$loc awk "$FIXED_WALK" "$FIXED_FILE" 2>/dev/null)
      got=$(LC_ALL=$loc spv_anchor_occurrences "$a" "$FIXED_FILE" 2>/dev/null)
      [[ "$want" == "$got" ]] || printf 'bad %s %s awk=%s bash=%s\n' "$loc" "$a" "$want" "$got"
    done
  done
  echo fixed-ok
)
if [[ "$FIXED_OUT" == fixed-ok ]]; then
  ok "non-word anchor counter matches awk index(), including an overlapping path"
else
  bad "non-word anchor counter differs from awk index(): $FIXED_OUT"
fi

SPV_GIT_LOG="$TEST_TMPDIR/stale-git.log"
SPV_REAL_GIT=$(type -P git)
SPV_GIT_SHIM="$TEST_TMPDIR/git-shim"
mkdir -p "$SPV_GIT_SHIM"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexec %q "$@"\n' \
  "$SPV_GIT_LOG" "$SPV_REAL_GIT" >"$SPV_GIT_SHIM/git"
chmod +x "$SPV_GIT_SHIM/git"
rm -f "$REPO/.git/guardrails-deleted-paths"
: >"$SPV_GIT_LOG"
OUT=$(PATH="$SPV_GIT_SHIM:$PATH" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'The shared spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md` today.')" 2>&1)
assert_contains "deleted-path cache: cold fire still names the removed path" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"
COLD_LOGS=$(grep -c 'log HEAD' "$SPV_GIT_LOG" || true)
if [[ "$COLD_LOGS" -ge 1 ]]; then
  ok "deleted-path cache: a cold fire walks history"
else
  bad "deleted-path cache: cold fire did not walk history"
fi
: >"$SPV_GIT_LOG"
OUT=$(PATH="$SPV_GIT_SHIM:$PATH" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'The shared spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md` today.')" 2>&1)
assert_contains "deleted-path cache: a repeat fire still names the removed path" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"
WARM_LOGS=$(grep -c 'log HEAD' "$SPV_GIT_LOG" || true)
assert_eq "deleted-path cache: a repeat fire at the same HEAD does not walk history" \
  0 "$WARM_LOGS"
git_c "$REPO" commit --allow-empty -qm "cache key moves with HEAD" >/dev/null 2>&1
: >"$SPV_GIT_LOG"
OUT=$(PATH="$SPV_GIT_SHIM:$PATH" CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$TARGET" 'The shared spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md` today.')" 2>&1)
assert_contains "deleted-path cache: a new HEAD still names the removed path" "$OUT" \
  "  plugins/re-anchor/context/re-anchor-audit-correct.md"
NEW_LOGS=$(grep -c 'log HEAD' "$SPV_GIT_LOG" || true)
if [[ "$NEW_LOGS" -ge 1 ]]; then
  ok "deleted-path cache: a new HEAD walks history again"
else
  bad "deleted-path cache: a new HEAD reused the previous set"
fi

CACHE_REPO="$TEST_TMPDIR/cache-repo"
mkdir -p "$CACHE_REPO/docs" "$CACHE_REPO/guides"
git -C "$CACHE_REPO" init -q
echo old >"$CACHE_REPO/docs/old-spec.md"
echo keep >"$CACHE_REPO/docs/keep.md"
git_c "$CACHE_REPO" add -A >/dev/null 2>&1
git_c "$CACHE_REPO" commit -qm seed >/dev/null 2>&1
git_c "$CACHE_REPO" mv docs/old-spec.md guides/old-spec.md >/dev/null 2>&1
git_c "$CACHE_REPO" commit -qm move >/dev/null 2>&1
CACHE_TARGET="$CACHE_REPO/notes.md"
: >"$CACHE_TARGET"
CACHE_PAYLOAD=$(write_json "$CACHE_TARGET" 'See `docs/old-spec.md` here.')
CACHE_DEL="$CACHE_REPO/.git/guardrails-deleted-paths"
CACHE_LS="$CACHE_REPO/.git/guardrails-ls-files"
CACHE_HEAD=$(git -C "$CACHE_REPO" rev-parse HEAD | tr -d '\r')
CACHE_PREV=$(git -C "$CACHE_REPO" rev-parse HEAD~1 | tr -d '\r')

cache_fire() {
  : >"$SPV_GIT_LOG"
  OUT=$(PATH="$SPV_GIT_SHIM:$PATH" CLAUDE_PROJECT_DIR="$CACHE_REPO" bash "$HOOK" \
    <<<"$CACHE_PAYLOAD" 2>&1)
  CACHE_WALKS=$(grep -c 'log HEAD' "$SPV_GIT_LOG" || true)
}
cache_is_whole() {
  local -a l
  local n
  mapfile -t l <"$1"
  n=$((${#l[@]} - 1 - $2))
  ((n >= 0)) && [[ "${l[${#l[@]} - 1]}" == "end $n" ]] &&
    [[ "$(printf '%s\n' "${l[@]:0:${#l[@]}-1}" | grep -c '^end [0-9]')" == 0 ]]
}
assert_whole() {
  if cache_is_whole "$2" "$3" && { [[ -z "${4-}" ]] || [[ "$(cat "$2")" == *"$4"* ]]; }; then
    ok "$1"
  else
    bad "$1: $(cat "$2" 2>&1)"
  fi
}

printf '%s\nok\nend 0\n' "$CACHE_HEAD" >"$CACHE_DEL"
cache_fire
assert_absent "cache: a whole file at this HEAD is trusted, not walked over" "$OUT" "deleted from this repo"
assert_eq "cache: a whole file at this HEAD starts no history walk" 0 "$CACHE_WALKS"

printf '%s\nok\n' "$CACHE_HEAD" >"$CACHE_DEL"
cache_fire
assert_contains "cache: a deleted-path file cut after its header is a miss, the finding stays" "$OUT" \
  "  docs/old-spec.md"
if ((CACHE_WALKS >= 1)) && cache_is_whole "$CACHE_DEL" 2; then
  ok "cache: the cut file is rebuilt whole"
else
  bad "cache: the cut file was not rebuilt whole (walks=$CACHE_WALKS)"
fi

printf '%s\nok\nsome/other.md\nend 3\n' "$CACHE_HEAD" >"$CACHE_DEL"
cache_fire
assert_contains "cache: a sentinel count that disagrees with the lines read is a miss" "$OUT" \
  "  docs/old-spec.md"
assert_whole "cache: the disagreeing file is rebuilt whole" "$CACHE_DEL" 2 docs/old-spec.md

printf '%s\nok\nsome/other.md\nend 1\nmore/other.md\nend 3\n' "$CACHE_HEAD" >"$CACHE_DEL"
cache_fire
assert_contains "cache: a sentinel inside the body is a miss even when the count agrees" "$OUT" \
  "  docs/old-spec.md"

printf '%s\nok\nend 0\n' "$CACHE_PREV" >"$CACHE_DEL"
cache_fire
assert_contains "cache: a file keyed to another HEAD is a miss, the finding stays" "$OUT" \
  "  docs/old-spec.md"
if ((CACHE_WALKS >= 1)) && [[ "$(head -n 1 "$CACHE_DEL")" == "$CACHE_HEAD" ]]; then
  ok "cache: the other-HEAD file is rebuilt for this HEAD"
else
  bad "cache: the other-HEAD file was reused (walks=$CACHE_WALKS)"
fi

touch -t 202001010000 "$CACHE_REPO/.git/index"
printf 'poison.md\nend 1\n' >"$CACHE_LS"
cache_fire
assert_absent "cache: a whole tracked-file list newer than the index is trusted" "$OUT" "guides/old-spec.md"

printf 'poison.md\n' >"$CACHE_LS"
cache_fire
assert_contains "cache: a tracked-file list with no sentinel is a miss" "$OUT" "guides/old-spec.md"
printf 'poison.md\nend 4\n' >"$CACHE_LS"
cache_fire
assert_contains "cache: a tracked-file list whose count disagrees is a miss" "$OUT" "guides/old-spec.md"
printf 'poison.md\nend 1\nother.md\nend 3\n' >"$CACHE_LS"
cache_fire
assert_contains "cache: a sentinel inside the tracked-file list is a miss" "$OUT" "guides/old-spec.md"
assert_whole "cache: the rebuilt tracked-file list is whole and current" "$CACHE_LS" 0 guides/old-spec.md

printf 'poison.md\nend 1\n' >"$CACHE_LS"
touch -t 202001010000 "$CACHE_LS"
touch "$CACHE_REPO/.git/index"
cache_fire
assert_contains "cache: a tracked-file list older than the index is rebuilt" "$OUT" "guides/old-spec.md"
assert_absent "cache: the stale tracked-file list is gone from the file" "$(cat "$CACHE_LS")" poison.md
assert_whole "cache: the stale tracked-file list was replaced whole" "$CACHE_LS" 0 guides/old-spec.md

EMPTY_CACHE_REPO="$TEST_TMPDIR/cache-empty"
mkdir -p "$EMPTY_CACHE_REPO/docs"
git -C "$EMPTY_CACHE_REPO" init -q
echo x >"$EMPTY_CACHE_REPO/docs/a.md"
git_c "$EMPTY_CACHE_REPO" add -A >/dev/null 2>&1
git_c "$EMPTY_CACHE_REPO" commit -qm seed >/dev/null 2>&1
git_c "$EMPTY_CACHE_REPO" rm -q docs/a.md >/dev/null 2>&1
git_c "$EMPTY_CACHE_REPO" commit -qm empty >/dev/null 2>&1
mkdir -p "$EMPTY_CACHE_REPO/docs"
: >"$EMPTY_CACHE_REPO/notes.md"
EMPTY_OUT=$(CLAUDE_PROJECT_DIR="$EMPTY_CACHE_REPO" bash "$HOOK" \
  <<<"$(write_json "$EMPTY_CACHE_REPO/notes.md" 'See `docs/a.md`.')" 2>&1)
assert_contains "cache: a repo with no tracked files still reports the removed path" "$EMPTY_OUT" \
  "  docs/a.md"
assert_eq "cache: an empty tracked-file list is written as a whole file of zero" \
  "end 0" "$(cat "$EMPTY_CACHE_REPO/.git/guardrails-ls-files" 2>/dev/null)"

CONC_BAD=0
for _ in 1 2 3 4 5; do
  rm -f "$CACHE_DEL" "$CACHE_LS"
  (CLAUDE_PROJECT_DIR="$CACHE_REPO" bash "$HOOK" <<<"$CACHE_PAYLOAD" >"$TEST_TMPDIR/conc-a" 2>&1) &
  # shellcheck disable=SC2031
  conc_pid_a=$!
  (CLAUDE_PROJECT_DIR="$CACHE_REPO" bash "$HOOK" <<<"$CACHE_PAYLOAD" >"$TEST_TMPDIR/conc-b" 2>&1) &
  # shellcheck disable=SC2031
  conc_pid_b=$!
  wait "$conc_pid_a" || CONC_BAD=1
  wait "$conc_pid_b" || CONC_BAD=1
  [[ "$(cat "$TEST_TMPDIR/conc-a")" == *"  docs/old-spec.md"* ]] || CONC_BAD=1
  [[ "$(cat "$TEST_TMPDIR/conc-b")" == *"  docs/old-spec.md"* ]] || CONC_BAD=1
  cache_is_whole "$CACHE_DEL" 2 || CONC_BAD=1
  cache_is_whole "$CACHE_LS" 0 || CONC_BAD=1
done
assert_eq "cache: two cold fires at once both report the finding and leave whole caches" 0 "$CONC_BAD"
cache_fire
assert_contains "cache: the caches the concurrent fires left are readable" "$OUT" "  docs/old-spec.md"
assert_eq "cache: and they are trusted, so no walk runs" 0 "$CACHE_WALKS"

rm -f "$CACHE_DEL" "$CACHE_LS"
chmod 555 "$CACHE_REPO/.git"
RO_ERR=$(CLAUDE_PROJECT_DIR="$CACHE_REPO" bash "$HOOK" <<<"$CACHE_PAYLOAD" 2>&1 >/dev/null)
chmod 755 "$CACHE_REPO/.git"
assert_silent "cache: an unwritable git directory leaves stderr empty" "$RO_ERR"

report
