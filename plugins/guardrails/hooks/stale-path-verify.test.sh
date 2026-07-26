#!/usr/bin/env bash
# Contract test for stale-path-verify.sh (guardrails plugin).
#
# Black-box subprocess invocation. The oracle is history, so each fixture repo
# COMMITS files and then DELETES them — a fixture that only `git init`s has an
# empty deleted-path set, under which every MUST-fire case would exit quiet and
# every stay-quiet assertion would pass against an inert guard.

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

# Neutralize ambient CLAUDE_PROJECT_DIR; cases that need scoping set it.
unset CLAUDE_PROJECT_DIR

# hook::notice_once keys its once-per-session markers under CLAUDE_PLUGIN_DATA.
# Inheriting the operator's real one makes the shallow-clone notice fire on the
# first run of the suite and stay suppressed on every run after.
export CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/plugin-data"

# hook::buffer_stdin bounds its fd0 read at CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT
# seconds, default 2, and a timeout makes an advisory hook exit 0 silently. A
# single invocation costs 10-20 s of wall time on a loaded Windows/Git Bash box, so
# the default bound produces empty output and a false FAIL that looks like a logic
# defect. Raised here because these cases test detection, not the read bound.
export CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30

git_c() { git -C "$1" -c user.email=t@t.test -c user.name=t -c commit.gpgsign=false "${@:2}"; }

# ---------------------------------------------------------------------------
# Fixture repo. Its history is the oracle, so the shape of each commit matters:
#
#   surviving        docs/real.md, .claude/settings.json, lib/keep.js
#   deleted          plugins/re-anchor/context/re-anchor-audit-correct.md
#                    docs/gone.md
#   renamed          tools/legacy-emit.sh -> tools/current-emit.sh
#   deleted off-HEAD scratch/branch-only.md (on an abandoned branch)
#   never present    docs/example.md, docs/new-thing.md, .claude/testing/e2e.md,
#                    lib/emit-slides.js
#
# plugins/discipline/context/re-anchor-audit-correct.md survives and is the ONLY
# tracked file with that basename, which is what the moved-file hint keys on.
# ---------------------------------------------------------------------------
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
mkdir -p "$REPO/docs" "$REPO/.claude" "$REPO/lib" "$REPO/tools" "$REPO/scratch" \
  "$REPO/plugins/re-anchor/context" "$REPO/plugins/discipline/context"
# Keeps scratch/ populated at HEAD after the abandoned branch's `git rm` prunes
# its own empty parent, so the off-HEAD case is a citation into a directory that
# genuinely exists rather than one the shape gate would have rejected anyway.
echo keep >"$REPO/scratch/keep.md"
echo real >"$REPO/docs/real.md"
echo gone >"$REPO/docs/gone.md"
echo settings >"$REPO/.claude/settings.json"
echo keep >"$REPO/lib/keep.js"
echo emit >"$REPO/tools/legacy-emit.sh"
echo anchor >"$REPO/plugins/re-anchor/context/re-anchor-audit-correct.md"
git_c "$REPO" add -A >/dev/null 2>&1
git_c "$REPO" commit -qm seed >/dev/null 2>&1

# The move that produces the true-positive shape: the file is gone from its old
# location and present at a new one.
git_c "$REPO" rm -q "docs/gone.md" >/dev/null 2>&1
git_c "$REPO" mv "plugins/re-anchor/context/re-anchor-audit-correct.md" \
  "plugins/discipline/context/re-anchor-audit-correct.md" >/dev/null 2>&1
git_c "$REPO" commit -qm "move and delete" >/dev/null 2>&1

# A rename git records as R. Without --no-renames on the history walk, --name-only
# prints only the NEW path and the stale one never enters the set.
git_c "$REPO" mv "tools/legacy-emit.sh" "tools/current-emit.sh" >/dev/null 2>&1
git_c "$REPO" commit -qm rename >/dev/null 2>&1

# A path deleted only on an abandoned branch. HEAD's history must not see it.
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

OUT=$(run 'The shared spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md` today.')
assert_exit "deleted path in code span → exit 0 (advisory)" 0 "$RC"
assert_contains "deleted path → named" "$OUT" \
  "STALE_PATH: plugins/re-anchor/context/re-anchor-audit-correct.md"
assert_contains "deleted path → count" "$OUT" "1 cited path(s) were removed"

# Criterion 4: the finding carries the moved-file hint when exactly one tracked
# file now carries that basename.
assert_contains "unique surviving basename → moved-file hint" "$OUT" \
  "plugins/discipline/context/re-anchor-audit-correct.md"

# Criterion 8: the advisory must read as a prompt for a verdict, not a verdict.
assert_contains "advisory states detect-then-judge" "$OUT" "Detect-then-judge"
assert_contains "advisory exempts a deliberate deletion record" "$OUT" \
  "deletion or completion record"

OUT=$(run_edit 'Now cites `plugins/re-anchor/context/re-anchor-audit-correct.md` instead.')
assert_contains "Edit hunk scanned via new_string" "$OUT" \
  "STALE_PATH: plugins/re-anchor/context/re-anchor-audit-correct.md"

# PARTIAL-EDIT RECONSTRUCTION. An Edit may replace a bare substring INSIDE an
# existing code span: the surrounding backticks are pre-existing and never enter
# new_string, so the hunk holds no complete span for the direct scan to find. The
# edit is already applied by PostToolUse time, so the containing citation is
# recovered from disk, anchored to the hunk's own text.
#
# `docs/gone.md` is in the deleted set; `docs/real.md` survives. The fixture holds
# the post-edit state (`real` -> `gone`), which is what disk carries when the hook
# runs.
PARTIAL="$REPO/partial.md"
printf 'Untouched `tools/legacy-emit.sh` here.\nNow cites `docs/gone.md` today.\n' >"$PARTIAL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$PARTIAL" 'gone')" 2>&1)
RC=$?
assert_exit "bare-substring Edit hunk → exit 0" 0 "$RC"
assert_contains "bare-substring Edit hunk → containing citation recovered" "$OUT" \
  "STALE_PATH: docs/gone.md"

# Diff-scope is preserved: a PRE-EXISTING unrelated stale citation must NOT fire
# just because reconstruction read from disk.
assert_absent "reconstruction does NOT report an untouched neighbour" "$OUT" \
  "legacy-emit"

# Diff-scope again, against the harder shape: the hunk is unrelated prose that
# merely SHARES a path segment with an untouched stale citation elsewhere in the
# same file. Anchoring on a word token pulls that citation in — `docs` occurs in
# both — so the anchor has to be the hunk's own line, which occurs exactly once.
SEGSHARE="$REPO/segshare.md"
printf 'Untouched `docs/gone.md` here.\nThe docs folder was reorganized today.\n' >"$SEGSHARE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(edit_json "$SEGSHARE" 'The docs folder was reorganized today.')" 2>&1)
RC=$?
assert_exit "prose hunk sharing a path segment → exit 0" 0 "$RC"
assert_silent "hunk sharing only a path SEGMENT does not drag in an untouched citation" "$OUT"

# The same shape with the hunk reduced to a BARE FRAGMENT — the normal minimal
# Edit, and the one the header comment uses to motivate reconstruction. `grep -F`
# is a substring match, so the line anchor collapses onto the token anchor here
# and line-anchoring alone recovers the untouched line 1. Occurrence uniqueness is
# what holds diff-scope: `docs` occurs on both lines, so the anchor is ambiguous
# and dropped rather than guessed at.
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$SEGSHARE" 'docs')" 2>&1)
RC=$?
assert_exit "bare-fragment hunk → exit 0" 0 "$RC"
assert_silent "bare-fragment hunk does not adjudicate an untouched citation" "$OUT"

# Occurrences, not matching lines. Two occurrences on ONE physical line are a
# single grep hit, so a line-uniqueness gate would call this unique and adjudicate
# a citation sharing the line. The anchor cannot say which occurrence the edit
# landed on, so it is dropped.
ONELINE="$REPO/oneline.md"
printf 'The docs folder and the docs tree both hold `docs/gone.md` today.\n' >"$ONELINE"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(edit_json "$ONELINE" 'docs')" 2>&1)
RC=$?
assert_exit "anchor occurring twice on one line → exit 0" 0 "$RC"
assert_silent "two occurrences on a single line are ambiguous, not unique" "$OUT"

# `replace_all` is the one shape where repetition is EXPECTED, not ambiguous:
# every occurrence is a place this call edited, so uniqueness must not be required
# or the guard goes silent on a genuine multi-site staleness. Built inline rather
# than through edit_json — that helper is shared across guard suites and gated by
# hook-utils-sync, so this suite's payload variant stays local to it.
replall_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s,replace_all:true}}'
}
REPLALL="$REPO/replall.md"
printf 'First `docs/gone.md` here.\nSecond `docs/gone.md` there.\n' >"$REPLALL"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" <<<"$(replall_json "$REPLALL" 'gone')" 2>&1)
RC=$?
assert_exit "replace_all Edit → exit 0" 0 "$RC"
assert_contains "replace_all → repeated anchor still adjudicated" "$OUT" \
  "STALE_PATH: docs/gone.md"

# A line-citation suffix is stripped for resolution; the finding names the path
# without it.
OUT=$(run 'Per `plugins/re-anchor/context/re-anchor-audit-correct.md:12` the rule applies.')
assert_contains "line citation suffix stripped → still fires" "$OUT" \
  "STALE_PATH: plugins/re-anchor/context/re-anchor-audit-correct.md"

# CRITERION 2, behaviorally. git records tools/legacy-emit.sh -> tools/current-emit.sh
# as a rename; with git's default rename detection --name-only prints only the new
# path, so this case fails and the guard is silently inert.
OUT=$(run 'Run `tools/legacy-emit.sh` to build.')
assert_contains "renamed-away path fires (--no-renames in effect)" "$OUT" \
  "STALE_PATH: tools/legacy-emit.sh"

# ============================ MUST STAY QUIET ===============================
#
# One case per false-positive class measured on the corpus sweep. Each is a
# citation whose leading directory DOES exist here, so a gate keyed on path shape
# rather than provenance adjudicates it; the provenance gate must not.

# Cause 1 (72% of findings): consumer-project config a marketplace documents but
# never carries. `.claude/` exists locally, which is exactly why shape-based
# gating could not tell these apart.
OUT=$(run 'Consumers put their suite under `.claude/testing/e2e.md`.')
assert_exit "consumer config path → exit 0" 0 "$RC"
assert_silent "consumer config path never in this repo → silent" "$OUT"

# Cause 2: a subtree-relative citation. `lib/` exists at the root, but the cited
# file is relative to a skill root, not the repo root.
OUT=$(run 'The generator lives at `lib/emit-slides.js` beside the skill.')
assert_silent "subtree-relative citation → silent" "$OUT"

# Cause 3: forward-looking — a path this change set has not written yet.
OUT=$(run 'CREATE: `docs/new-thing.md` in the next step.')
assert_silent "forward-looking path never committed → silent" "$OUT"

# Cause 4: an illustrative placeholder.
OUT=$(run 'For instance `docs/example.md` would do.')
assert_silent "illustrative placeholder → silent" "$OUT"

# Cause 5: a code span holding markdown link syntax is example text, not a link.
# Its destination must never be extracted as one.
OUT=$(run 'Write it as `[the guide](docs/gone.md)` in prose.')
assert_silent "link literal inside a code span → silent" "$OUT"

# Link destinations are out of scope entirely — including one naming a genuinely
# removed file, which is the case a destination extractor would most want.
OUT=$(run 'See [the guide](docs/gone.md) for details.')
assert_silent "link destination to a removed file → silent (links out of scope)" "$OUT"

# HEAD, not --all: a path that only ever existed on an abandoned branch is not a
# stale mainline citation.
OUT=$(run 'Scratch notes were at `scratch/branch-only.md`.')
assert_silent "path deleted only off HEAD → silent" "$OUT"

# The provenance gate replaces the first-segment gate rather than layering with
# it: a coincident leading directory is no longer sufficient.
OUT=$(run 'Upstream lives at `docs/never-existed.md` and `plugins/other/thing.sh`.')
assert_silent "coincident first segment with no provenance → silent" "$OUT"

OUT=$(run 'Read `docs/real.md` before starting.')
assert_silent "existing path → silent" "$OUT"

OUT=$(run 'Glob it with `plugins/*/SKILL.md` or `docs/**/*.md`.')
assert_silent "glob patterns → silent" "$OUT"

OUT=$(run 'Placeholders like `plugins/<name>/plugin.json` and `docs/${topic}/PLAN.md`.')
assert_silent "placeholder metacharacters → silent" "$OUT"

OUT=$(run 'Fetch <https://example.com/docs/gone.md> and `https://a.test/docs/gone.md`.')
assert_silent "URLs → silent" "$OUT"

OUT=$(run 'Absolute paths `/etc/hosts` and `C:/Windows/system32/x.dll`.')
assert_silent "absolute paths → silent (hardcoded-path-check owns those)" "$OUT"

OUT=$(run 'User config at `~/.claude/settings.json`.')
assert_silent "home-relative → silent" "$OUT"

OUT=$(run 'Parent escape `../docs/gone.md` and `docs/../plugins/x.sh`.')
assert_silent "parent-escaping paths → silent" "$OUT"

OUT=$(run 'Prose mentioning plugins/re-anchor/context/re-anchor-audit-correct.md outside a span.')
assert_silent "unquoted prose path → not scanned" "$OUT"

OUT=$(run 'A whole command: `cp docs/gone.md docs/real.md`.')
assert_silent "multi-token code span → not a path candidate" "$OUT"

# A CHANGELOG is an append-only record and this oracle selects for exactly what
# such a record documents.
CHANGELOG="$REPO/CHANGELOG.md"
: >"$CHANGELOG"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$CHANGELOG" 'Removed `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
RC=$?
assert_exit "CHANGELOG.md → exit 0" 0 "$RC"
assert_silent "CHANGELOG.md citing a removed path → silent" "$OUT"

# Non-markdown files are out of scope: a path literal in a script resolves
# against the runtime CWD, not the repo root.
SCRIPT="$REPO/tool.sh"
: >"$SCRIPT"
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(write_json "$SCRIPT" 'cat plugins/re-anchor/context/re-anchor-audit-correct.md')" 2>&1)
RC=$?
assert_exit "non-markdown file → exit 0" 0 "$RC"
assert_silent "non-markdown file → not scanned" "$OUT"

# A tool other than Write|Edit carries nothing this call wrote.
OUT=$(CLAUDE_PROJECT_DIR="$REPO" bash "$HOOK" \
  <<<"$(notebook_json "$TARGET" 'plugins/re-anchor/context/re-anchor-audit-correct.md')" 2>&1)
RC=$?
assert_exit "NotebookEdit payload → exit 0" 0 "$RC"
assert_silent "NotebookEdit payload → silent" "$OUT"

# ============================ NO HISTORY ====================================

# A repository with no commits has an unborn HEAD. `git log HEAD` errors there,
# so the guard must produce an empty set silently rather than leak git's
# "ambiguous argument 'HEAD'" to stderr.
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

# A non-git directory: hook::repo_root falls back to the written file's own
# directory, where no history exists at all.
NOGIT="$TEST_TMPDIR/nogit"
mkdir -p "$NOGIT/docs"
NOGIT_TARGET="$NOGIT/notes.md"
: >"$NOGIT_TARGET"
OUT=$(CLAUDE_PROJECT_DIR="$NOGIT" bash "$HOOK" \
  <<<"$(write_json "$NOGIT_TARGET" 'Read `docs/nope.md`.')" 2>&1)
RC=$?
assert_exit "non-git directory → exit 0" 0 "$RC"
assert_silent "non-git directory → silent" "$OUT"

# ============================ PRESENT BUT NOT ON DISK =======================
#
# Two shapes where the working tree does not answer "is this path here". Both need
# a repo whose history deletes the path, so the provenance gate is satisfied and
# only the existence gate stands between the citation and a false finding.

# A path deleted historically and then restored is BOTH in the deleted set and
# tracked at HEAD. A sparse checkout leaves such a path unmaterialized on purpose;
# skip-worktree is the index bit sparse checkout itself sets to mark that.
SPARSE="$TEST_TMPDIR/sparse"
mkdir -p "$SPARSE/docs"
git -C "$SPARSE" init -q
echo v1 >"$SPARSE/docs/restored.md"
echo v1 >"$SPARSE/docs/truly-gone.md"
git_c "$SPARSE" add -A >/dev/null 2>&1
git_c "$SPARSE" commit -qm seed >/dev/null 2>&1
git_c "$SPARSE" rm -q docs/restored.md docs/truly-gone.md >/dev/null 2>&1
git_c "$SPARSE" commit -qm delete >/dev/null 2>&1
# `git rm` prunes the parent it emptied, so the directory has to come back first.
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

# The exemption is the SKIP-WORKTREE BIT, not the mere index entry. Clearing the
# bit leaves the same path tracked and the same absence from disk, but the shape is
# now an UNSTAGED DELETION (`git status` reports ` D`) — a genuine working-tree
# disappearance rather than a by-design sparse one, so it must be adjudicated.
# `ls-files --error-unmatch` reports the entry in both shapes and cannot separate
# them; the `S` tag can.
git -C "$SPARSE" update-index --no-skip-worktree docs/restored.md >/dev/null 2>&1
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "unstaged deletion → exit 0" 0 "$RC"
assert_contains "unstaged deletion is not a sparse exemption → fires" "$OUT" \
  "STALE_PATH: docs/restored.md"

# assume-unchanged (`ls-files -v` tag `h`) is deliberately NOT exempted. It is a
# stat-skipping performance promise about a path the user keeps on disk, not a
# declaration that the path is absent by design, so a deleted one is a real
# working-tree disappearance — the same shape as the unstaged deletion above.
# Exempting `h` would reinstate the suppression this change removes, for a
# narrower set. #1509's acceptance text names the variant alongside
# skip-worktree; only `S` earns the exemption, and this case pins that.
git -C "$SPARSE" update-index --assume-unchanged docs/restored.md >/dev/null 2>&1
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/restored.md` first.')" 2>&1)
RC=$?
assert_exit "assume-unchanged deletion → exit 0" 0 "$RC"
assert_contains "assume-unchanged is not a sparse exemption → fires" "$OUT" \
  "STALE_PATH: docs/restored.md"
git -C "$SPARSE" update-index --no-assume-unchanged docs/restored.md >/dev/null 2>&1

git -C "$SPARSE" update-index --skip-worktree docs/restored.md >/dev/null 2>&1

# The index check must not swallow a genuine removal. Same repo, same absence from
# disk — the only difference is that this one is in no index entry either.
OUT=$(CLAUDE_PROJECT_DIR="$SPARSE" bash "$HOOK" \
  <<<"$(write_json "$SPARSE_TARGET" 'Read `docs/truly-gone.md` first.')" 2>&1)
assert_contains "deleted and never restored → still fires" "$OUT" \
  "STALE_PATH: docs/truly-gone.md"

# A deleted path reintroduced as a symlink whose target is unavailable is present
# in the working tree, but `-e` reports false for it.
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
  # A Windows box without the symlink privilege cannot build the fixture at all, so
  # the arm is pinned in source instead — the same fallback the jq-removal case
  # takes for its own non-simulable condition.
  assert_contains "existence gate accepts the link itself" "$(cat "$HOOK")" \
    '|| -L "$REPO_ROOT/${cand%/}"'
fi

# ============================ SHALLOW CLONE =================================

# Over truncated history the deleted-path set is empty and the guard would do
# nothing while appearing healthy. The degradation must be announced.
SHALLOW_REPO="$TEST_TMPDIR/shallow"
if git clone -q --no-local --depth 1 "$REPO" "$SHALLOW_REPO" >/dev/null 2>&1 &&
  [[ "$(git -C "$SHALLOW_REPO" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
  SHALLOW_TARGET="$SHALLOW_REPO/notes.md"
  : >"$SHALLOW_TARGET"

  # Ordered before the notice has ever fired, so this proves the notice is gated
  # on a candidate the guard could not adjudicate rather than on once-per-session.
  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'Read `docs/real.md` first.')" 2>&1)
  assert_silent "shallow clone with nothing absent → silent" "$OUT"

  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'The spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
  RC=$?
  assert_exit "shallow clone → exit 0" 0 "$RC"
  assert_contains "shallow clone → visible prerequisite notice" "$OUT" "clone is shallow"
  assert_contains "shallow clone → notice names the remedy" "$OUT" "fetch --unshallow"
  assert_absent "shallow clone → no finding claimed" "$OUT" "STALE_PATH"

  OUT=$(CLAUDE_PROJECT_DIR="$SHALLOW_REPO" bash "$HOOK" \
    <<<"$(write_json "$SHALLOW_TARGET" 'The spoke is `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
  assert_silent "shallow clone → notice is once per session, not per write" "$OUT"

  # The notice is once-per-session but telemetry is per-run, and a sink reading
  # `ok` here would record an un-run check as a healthy one — the same
  # looks-healthy-while-inert failure the visible notice exists to prevent.
  SHALLOW_TEL="$(mktemp -p "$TEST_TMPDIR")"
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

# ======================= INCOMPLETE HISTORY WALK ============================

# A clone that is NOT shallow can still fail mid-walk — a partial clone offline,
# a damaged object store. git emits the deletions it already resolved and THEN
# exits nonzero, so a partial deleted-path set is indistinguishable from a
# complete one unless the status is checked. The fixture reproduces exactly that:
# HEAD's own diff resolves (docs/late.md is emitted) and the older one cannot.
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

# The fixture is only meaningful when the walk BOTH emitted something AND failed;
# anything else is testing a different condition than the one the guard guards.
if ((WALK_RC != 0)) && [[ "$WALK_OUT" == *docs/late.md* ]] &&
  [[ "$(git -C "$WALK_REPO" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" != "true" ]]; then
  WALK_TARGET="$WALK_REPO/notes.md"
  : >"$WALK_TARGET"

  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'Read `docs/keep.md` first.')" 2>&1)
  assert_silent "incomplete walk with nothing absent → silent" "$OUT"

  # docs/late.md IS in the partial set. Adjudicating off it would look like a
  # correct finding while the rest of history went unread.
  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'The spoke is `docs/late.md`.')" 2>&1)
  RC=$?
  assert_exit "incomplete walk → exit 0" 0 "$RC"
  assert_contains "incomplete walk → visible prerequisite notice" "$OUT" "history walk exited nonzero"
  assert_contains "incomplete walk → notice names the diagnostic" "$OUT" "diff-filter=D"
  assert_absent "incomplete walk → partial set never adjudicated" "$OUT" "STALE_PATH"

  OUT=$(CLAUDE_PROJECT_DIR="$WALK_REPO" bash "$HOOK" \
    <<<"$(write_json "$WALK_TARGET" 'The spoke is `docs/late.md`.')" 2>&1)
  assert_silent "incomplete walk → notice is once per session, not per write" "$OUT"
else
  bad "incomplete history walk: fixture could not be built"
fi

# ============================ KILL SWITCH ===================================

OUT=$(CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_STALE_PATH_VERIFY_ENABLED=false \
  bash "$HOOK" <<<"$(write_json "$TARGET" 'Cite `plugins/re-anchor/context/re-anchor-audit-correct.md`.')" 2>&1)
RC=$?
assert_exit "kill switch → exit 0" 0 "$RC"
assert_silent "kill switch → silent" "$OUT"

# ============================ EMPTY STDIN ===================================

# hook::buffer_stdin returns 1 (no payload) → this advisory hook skips silently.
OUT=$(bash "$HOOK" </dev/null 2>&1)
RC=$?
assert_exit "empty stdin → exit 0" 0 "$RC"
assert_silent "empty stdin → no output" "$OUT"

# ============================ SOURCE CONTRACT ===============================

HOOK_SRC=$(cat "$HOOK")

# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils across Git Bash and Linux, the same constraint
# secret-pattern-detection.test.sh and require-jq-notice-isolation.test.sh both
# document. Assert the fail-open guard is present; require_jq's own behavior is
# covered by lib/hook-utils.test.sh and the notice key's plugin-wide uniqueness
# by require-jq-notice-isolation.test.sh.
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'
assert_contains "jq guard: hook-specific notice key" "$HOOK_SRC" 'guardrails-stale-path-verify'

# The repo root is resolved from the written file, never from the process CWD, so
# the hook is correct in a linked worktree and in a bare-hub clone.
assert_contains "repo root is file-anchored" "$HOOK_SRC" 'hook::repo_root "$(dirname "$FILE")"'

# The behavioral rename case above is the real proof, but pin the flags too: a
# refactor that drops either one changes the guard's meaning silently.
assert_contains "history walk passes --no-renames" "$HOOK_SRC" '--no-renames'
assert_contains "history walk is scoped to HEAD, not --all" "$HOOK_SRC" 'log HEAD --no-renames'
assert_absent "history walk does not read --all" "$HOOK_SRC" 'log --all'

# ============================ TELEMETRY =====================================

TEL="$(mktemp -p "$TEST_TMPDIR")"
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

report
