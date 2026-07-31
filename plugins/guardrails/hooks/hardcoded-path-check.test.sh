#!/usr/bin/env bash
# Contract test for hardcoded-path-check.sh (guardrails plugin).
#
# Black-box subprocess invocation. Machine-path fixtures are assembled at
# runtime from separator + segment fragments so no contiguous machine-path
# literal appears in this file's source bytes — a path-shape scanner sees a
# clean test file.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/hardcoded-path-check.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# The scope guard skips any project dir that is not a git working tree, so
# the default active-project fixture root must BE one for scan cases to run.
git -C "$TEST_TMPDIR" init -q

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Neutralize ambient CLAUDE_PROJECT_DIR. Cases that expect scanning set it
# explicitly — with no active project the hook skips entirely (README
# "Project scoping": only files under $CLAUDE_PROJECT_DIR are policed).
unset CLAUDE_PROJECT_DIR

# Runtime-assembled machine paths (no contiguous path literal in source).
SL='/'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
LINUX_HOME="${SL}home${SL}jdoe${SL}project"
MAC_HOME="${SL}Users${SL}alice${SL}dev${SL}repo"
MAC_SHARED="${SL}Users${SL}Shared${SL}output"
WIN_HOME="C:${BS}Users${BS}bob${BS}repo"

FIXTURE="$TEST_TMPDIR/fixture.txt"
PS1_FIXTURE="$TEST_TMPDIR/script.ps1"

# ============================ DETECT (exit 2) ================================
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME} && ls")" 2>&1)
RC=$?
assert_exit "linux home → exit 2" 2 "$RC"
assert_contains "linux home → message" "$OUT" "Linux user path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${MAC_HOME} && ls")" 2>&1)
RC=$?
assert_exit "macos home → exit 2" 2 "$RC"
assert_contains "macos → message" "$OUT" "macOS user path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${WIN_HOME} && dir")" 2>&1)
RC=$?
assert_exit "windows home → exit 2" 2 "$RC"
assert_contains "windows → message" "$OUT" "Windows user path"

# Cross-OS leak: a Linux path inside a .ps1 still fires (only Windows is suppressed).
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "Set-Location ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "Linux leak in .ps1 → exit 2" 2 "$RC"
assert_contains "cross-OS leak → linux message" "$OUT" "Linux user path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(edit_json "$FIXTURE" "new path ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "cd ${MAC_HOME}")" 2>&1)
RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

# Repo-path branch: a genuine (non-home) git checkout root hardcoded in content
# is a machine-specific marker and MUST still fire — guards against the home-gate
# over-suppressing the branch entirely (the branch had no prior test).
REPO_REAL="$TEST_TMPDIR/realrepo"
mkdir -p "$REPO_REAL"
git -C "$REPO_REAL" init -q
OUT=$(HOME="$TEST_TMPDIR/elsewhere" CLAUDE_PROJECT_DIR="$REPO_REAL" \
  bash "$HOOK" <<<"$(write_json "$REPO_REAL/notes.txt" "checkout at $REPO_REAL/src")" 2>&1)
RC=$?
assert_exit "repo root in real non-home checkout → exit 2" 2 "$RC"
assert_contains "repo root → machine-specific repo message" "$OUT" "Machine-specific repo path"

# Project dir a SUBDIR of a genuine non-home checkout: the toplevel is non-home,
# so the branch stays active and a hardcoded project-dir path still fires. Guards
# the toplevel comparison against over-suppressing real checkouts reached via a
# subdirectory.
SUBREPO="$TEST_TMPDIR/subrepo"
mkdir -p "$SUBREPO/pkg"
git -C "$SUBREPO" init -q
OUT=$(HOME="$TEST_TMPDIR/elsewhere2" CLAUDE_PROJECT_DIR="$SUBREPO/pkg" \
  bash "$HOOK" <<<"$(write_json "$SUBREPO/pkg/notes.txt" "at $SUBREPO/pkg/x")" 2>&1)
RC=$?
assert_exit "repo subdir of non-home checkout → exit 2" 2 "$RC"
assert_contains "repo subdir → machine-specific repo message" "$OUT" "Machine-specific repo path"

# Generic Windows checkout root under a widened root name (Projects/Dev/Repos):
# content carries no "Users"/"repos" literal, so it exercises the cheap
# pre-filter gate — which must trip on every root HPP_WIN_REPO_BODY accepts, or
# the scan early-returns and the leak passes (fail-open).
WIN_PROJECTS="D:${BS}Projects${BS}acme${BS}src"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "build from ${WIN_PROJECTS}")" 2>&1)
RC=$?
assert_exit "windows Projects checkout root → exit 2" 2 "$RC"
assert_contains "windows Projects root → message" "$OUT" "Windows repo path"

# --- Right-boundary regressions (#1093): a bare path VALUE at end of line has
# no trailing separator and must still fire. The old bodies required one, so
# exactly the config-value shape the guard exists to catch was missed while
# prose satisfied the requirement via a greedy space-permitting segment. ---
WIN_BARE_REPO="C:${SL}Dev${SL}GitHub"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "root = ${WIN_BARE_REPO}")" 2>&1)
RC=$?
assert_exit "bare windows repo value at EOL → exit 2" 2 "$RC"
assert_contains "bare repo value → message" "$OUT" "Windows repo path"

WIN_BARE_HOME="C:${BS}Users${BS}bob"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "home = ${WIN_BARE_HOME}")" 2>&1)
RC=$?
assert_exit "bare windows user home at EOL → exit 2" 2 "$RC"
assert_contains "bare windows home → message" "$OUT" "Windows user path"

LINUX_BARE_HOME="${SL}home${SL}jdoe"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_BARE_HOME}")" 2>&1)
RC=$?
assert_exit "bare linux home at EOL → exit 2" 2 "$RC"
assert_contains "bare linux home → message" "$OUT" "Linux user path"

MAC_BARE_HOME="${SL}Users${SL}alice"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "backup ${MAC_BARE_HOME}")" 2>&1)
RC=$?
assert_exit "bare macos home at EOL → exit 2" 2 "$RC"
assert_contains "bare macos home → message" "$OUT" "macOS user path"

# JSON-escaped bare value (doubled separators, end of string value).
ESC_BARE_REPO="C:${BS}${BS}Dev${BS}${BS}GitHub"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cfg = \"${ESC_BARE_REPO}\"")" 2>&1)
RC=$?
assert_exit "escaped bare windows repo value → exit 2" 2 "$RC"
assert_contains "escaped bare repo value → message" "$OUT" "Escaped Windows repo path"

# The prose false positive the old greedy segment produced: checkout-root
# words plus a later slash on the same line, but no drive-letter anchor.
# Must stay clean under the whitespace-excluding segment class.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "projects - personal repos (reference${SL}reading only)")" 2>&1)
RC=$?
assert_exit "checkout-root prose with later slash → exit 0" 0 "$RC"
assert_silent "checkout-root prose → no stderr" "$OUT"

# Root-with-no-child prose: separator then whitespace. The class requires at
# least one non-space child character, so this must not match.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see ${SL}Users${SL} for details")" 2>&1)
RC=$?
assert_exit "bare Users root + prose → exit 0" 0 "$RC"
assert_silent "bare Users root prose → no stderr" "$OUT"

# ============================ NO-PROJECT SKIP ================================
# No active project (CLAUDE_PROJECT_DIR unset): the hook does not scan at all.
# A no-project target (e.g. a $HOME dotfile) is machine-local, not a portable
# repo artifact, and without a project root the gitignore escape hatch below
# would be unreachable — so the scope guard skips instead of scanning.
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME} && ls")" 2>&1)
RC=$?
assert_exit "no project + machine path → exit 0 (skip)" 0 "$RC"
assert_silent "no project → no stderr" "$OUT"

# The reported incident shape: Edit of a $HOME dotfile carrying an absolute
# user-home path (a machine-local gitconfig include) from a no-project session.
OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "path = ${WIN_HOME}")" 2>&1)
RC=$?
assert_exit "no project + Edit dotfile-style path → exit 0 (skip)" 0 "$RC"
assert_silent "no project Edit → no stderr" "$OUT"

# ======================= NON-WORKTREE PROJECT SKIP ==========================
# CLAUDE_PROJECT_DIR set but NOT a git working tree (home-directory sessions —
# the harness sets a project dir for any directory): skip entirely. The target
# is machine-local, and no exemption rung is reachable there (the .claude
# carve-outs don't cover machine-local plugin config; git check-ignore errors
# outside a work tree), so scanning would leave only the global kill switch.
# The reported incident shape: Write of ~/.claude/<plugin>.conf naming
# absolute machine roots.
# Own tmpdir — $TEST_TMPDIR is itself a work tree now, so a subdir of it
# would not exercise the non-worktree path.
NONREPO="$(mktemp -d)"
mkdir -p "$NONREPO/.claude"
OUT=$(CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" <<<"$(write_json "$NONREPO/.claude/tool.conf" "root = ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "non-worktree project + machine-local conf → exit 0 (skip)" 0 "$RC"
assert_silent "non-worktree project → no stderr" "$OUT"
rm -rf "$NONREPO"

# Same content under a REAL work tree still fires — the skip keys on the
# work-tree probe, not on path shape.
WT="$TEST_TMPDIR/realwt"
mkdir -p "$WT"
git -C "$WT" init -q
OUT=$(CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" <<<"$(write_json "$WT/notes.txt" "root = ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "same content in real work tree → exit 2" 2 "$RC"
assert_contains "real work tree → linux message" "$OUT" "Linux user path"

# ============================ ALLOW (exit 0) ================================
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" 'echo "hello world"')" 2>&1)
RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

# shellcheck disable=SC2016
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" 'cd $HOME/project && cd ~/dev')" 2>&1)
RC=$?
assert_exit "dynamic \$HOME / ~ → exit 0" 0 "$RC"
assert_silent "dynamic refs → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp file ${MAC_SHARED}")" 2>&1)
RC=$?
assert_exit "macos Shared dir → exit 0" 0 "$RC"

# Bare Shared at EOL: the body now matches it (no trailing separator needed),
# so the driver's Shared exclusion must cover the bare form too.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${SL}Users${SL}Shared")" 2>&1)
RC=$?
assert_exit "bare macos Shared at EOL → exit 0" 0 "$RC"

# Shared exclusion must be match-level, not line-level: a line holding a bare
# Shared path AND a user-specific path still fires on the user-specific one.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp ${SL}Users${SL}Shared ${SL}Users${SL}alice")" 2>&1)
RC=$?
assert_exit "Shared + user path on one line → exit 2" 2 "$RC"
assert_contains "Shared + user path → macOS message" "$OUT" "macOS user path"

# Defang boundary guard: a real segment merely PREFIXED with Shared is a user
# directory, not the shared one — it must still flag.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${SL}Users${SL}SharedStuff")" 2>&1)
RC=$?
assert_exit "SharedStuff segment → exit 2" 2 "$RC"

# Shell / prose punctuation right after Shared is a boundary, not a longer
# segment — common command shapes must stay clean.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${SL}Users${SL}Shared; ls")" 2>&1)
RC=$?
assert_exit "Shared followed by semicolon → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp '${SL}Users${SL}Shared' out")" 2>&1)
RC=$?
assert_exit "single-quoted Shared → exit 0" 0 "$RC"

# Every macOS-body candidate is a Windows path, so the candidate block is empty
# once the Windows exclusion has run. Under `pipefail` that stage reports
# failure, and a scan that aborts there would fail OPEN rather than pass clean.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "copy ${WIN_HOME}${BS}a.txt ${WIN_HOME}${BS}b.txt")" 2>&1)
RC=$?
assert_exit "macOS candidates all excluded as Windows → exit 0" 0 "$RC"
assert_silent "all-Windows candidates → no stderr" "$OUT"

# The defang is evaluated over the whole candidate block, so the survivor's
# reported entry must still carry its ORIGINAL line number and ORIGINAL
# un-defanged text. Padding with Shared-only lines puts the real violation
# beyond the first three candidates, which is exactly where a block-relative
# index would be reported in place of the file-relative one.
MIXED="ls ${SL}Users${SL}Shared${SL}a
ls ${SL}Users${SL}Shared${SL}b
ls ${SL}Users${SL}Shared${SL}c
ls ${SL}Users${SL}Shared${SL}d
cd ${MAC_HOME}"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "$MIXED")" 2>&1)
RC=$?
assert_exit "Shared-padded block, violation at line 5 → exit 2" 2 "$RC"
assert_contains "padded block → original file line number" "$OUT" "5:cd ${MAC_HOME}"
assert_absent "padded block → never reports the defanged copy" "$OUT" "${SL}Users-Shared"

# Survivor at COLUMN 0 of its line, inside a block that also carries a Shared
# token so the defang branch runs. The candidate reaches the re-test carrying
# `grep -n`'s line-number prefix, so the boundary's `^` alternative no longer
# sits at the start of the string — the lib strips that prefix to keep both
# passes' conditions identical. Without the strip this case is matched only by
# the boundary class also happening to accept ":", and a violation flagged on
# the first pass would be silently dropped on the second.
COL0="ls ${SL}Users${SL}Shared${SL}a
${MAC_HOME} is the checkout"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "$COL0")" 2>&1)
RC=$?
assert_exit "Shared block, violation at column 0 → exit 2" 2 "$RC"
assert_contains "column-0 violation → original file line number" "$OUT" "2:${MAC_HOME}"

# Shared-heavy content must cost a BOUNDED number of subprocesses, not one per
# candidate. All-Shared is the pathological shape: no candidate survives the
# defang, so the reporting short-circuit never fires and a per-candidate loop
# runs to completion, spawning a sed and a grep on every line. A guard killed
# at its hook timeout fails OPEN, so this is a correctness property.
#
# The pin COUNTS SPAWNS instead of timing the run. Elapsed time here is
# dominated by process-spawn latency: repeats of the identical 400-line corpus
# measured 5.0s and 15.2s on one machine, a spread wider than the 4x signal a
# wall-clock ratio exists to detect, so any such ratio is either flaky or too
# loose to discriminate. A count is exact and load-invariant. `grep`/`sed`
# shims on PATH tally every spawn the hook makes; the hoisted form issues one
# fixed pipeline, so quadrupling the input must not add a single process.
# Measured on Git Bash: 12 spawns at both sizes hoisted, against 210 at 100
# lines for the per-candidate loop (100 `sed` + 110 `grep`) — and that shape's
# wall clock grew 13x for 4x the input (22s to 288s), fork pressure compounding
# into exactly the timeout death this case exists to prevent.
SPAWN_SHIM="$TEST_TMPDIR/spawn-shim"
SPAWN_LOG="$TEST_TMPDIR/spawn-log"
mkdir -p "$SPAWN_SHIM"
for _bin in grep sed; do
  _real="$(command -v "$_bin")"
  # Unquoted delimiter so the real binary path is baked in; every other
  # expansion is escaped and resolves when the shim RUNS.
  cat >"$SPAWN_SHIM/$_bin" <<SHIM
#!/usr/bin/env bash
printf 'x\n' >>"\${HPP_SPAWN_LOG:-/dev/null}"
exec '$_real' "\$@"
SHIM
  chmod +x "$SPAWN_SHIM/$_bin"
done

shared_block() {
  local n="$1" i out=""
  for ((i = 1; i <= n; i++)); do out="${out}cp ${SL}Users${SL}Shared${SL}lib${i}${SL}a.txt out${i}"$'\n'; done
  printf '%s' "$out"
}
SHARED_100=$(write_json "$FIXTURE" "$(shared_block 100)")
SHARED_400=$(write_json "$FIXTURE" "$(shared_block 400)")

# Sets SPAWN_RC and SPAWN_COUNT. Not a command substitution — that would run
# the body in a subshell and strand both.
run_shimmed() {
  : >"$SPAWN_LOG"
  CLAUDE_PROJECT_DIR="$TEST_TMPDIR" HPP_SPAWN_LOG="$SPAWN_LOG" PATH="$SPAWN_SHIM:$PATH" \
    bash "$HOOK" <<<"$1" >/dev/null 2>&1
  SPAWN_RC=$?
  SPAWN_COUNT=$(wc -l <"$SPAWN_LOG")
  SPAWN_COUNT=${SPAWN_COUNT//[[:space:]]/}
}

run_shimmed "$SHARED_100"
assert_exit "100 Shared-only lines → exit 0" 0 "$SPAWN_RC"
SPAWNS_SMALL=$SPAWN_COUNT

run_shimmed "$SHARED_400"
assert_exit "400 Shared-only lines → exit 0" 0 "$SPAWN_RC"
SPAWNS_LARGE=$SPAWN_COUNT

# A zero tally means the shims never ran, which would make the equality below
# pass vacuously — the silent-skip shape this suite otherwise guards against.
if ((SPAWNS_SMALL > 0)); then
  ok "spawn shims active (${SPAWNS_SMALL} grep/sed spawns at 100 lines)"
else
  bad "spawn shims never fired — the bounded-cost pin cannot discriminate"
fi

if ((SPAWNS_LARGE == SPAWNS_SMALL)); then
  ok "Shared defang is bounded, not per-candidate (${SPAWNS_SMALL} spawns at 100 lines, ${SPAWNS_LARGE} at 400)"
else
  bad "Shared defang scales with candidate count: ${SPAWNS_SMALL} spawns at 100 lines, ${SPAWNS_LARGE} at 400"
fi

# Left boundary: a URL whose path merely CONTAINS a home-root suffix is not a
# filesystem root — must stay clean (macOS and Linux shapes).
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see https://example.test${SL}home${SL}alice for docs")" 2>&1)
RC=$?
assert_exit "URL containing home suffix → exit 0" 0 "$RC"
assert_silent "URL home suffix → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see https://example.test${SL}Users${SL}alice page")" 2>&1)
RC=$?
assert_exit "URL containing Users suffix → exit 0" 0 "$RC"

# Colon-prefixed value position (yaml/docker) is a boundary — must still flag.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "vol:${SL}home${SL}alice mount")" 2>&1)
RC=$?
assert_exit "colon-prefixed linux home → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "\$cfg = '${WIN_HOME}'")" 2>&1)
RC=$?
assert_exit "Windows path in .ps1 → suppressed → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1)
RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

# Outside CLAUDE_PROJECT_DIR → exit 0 (another repo's concern).
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "/tmp/other/file.txt" "$LINUX_HOME")" 2>&1)
RC=$?
assert_exit "outside CLAUDE_PROJECT_DIR → exit 0" 0 "$RC"

# Case-exemption pins run inside a REAL work tree — the scope guard's
# non-worktree skip would otherwise exit before the carve-outs and leave them
# unpinned.
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/.claude/hooks/foo.sh" "pattern ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/.lefthook/pre-commit/foo.sh" "pattern ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit ".lefthook/ self-exemption → exit 0" 0 "$RC"

# CC session/workflow state under ~/.claude/projects/, with home itself a
# checkout (dotfiles-as-home) so the run reaches the case-exemption rather
# than exiting at the non-worktree skip.
HOMECO="$TEST_TMPDIR/homeco"
mkdir -p "$HOMECO"
git -C "$HOMECO" init -q
OUT=$(CLAUDE_PROJECT_DIR="$HOMECO" bash "$HOOK" <<<"$(write_json "$HOMECO/.claude/projects/my-repo/wf.js" "const out = '${WIN_HOME}'")" 2>&1)
RC=$?
assert_exit ".claude/projects/ CC-state self-exemption → exit 0" 0 "$RC"

# Gitignored file → exit 0 (consumer seam via .gitignore + git check-ignore).
GITREPO="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
printf 'ignored.txt\n' >"$GITREPO/.gitignore"
OUT=$(CLAUDE_PROJECT_DIR="$GITREPO" bash "$HOOK" <<<"$(write_json "$GITREPO/ignored.txt" "$LINUX_HOME")" 2>&1)
RC=$?
assert_exit "gitignored file → exit 0 (consumer seam)" 0 "$RC"

# Kill switch — disabled path is a clean no-op even on a real machine path.
OUT=$(CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "$LINUX_HOME")" 2>&1)
RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"

# --- Repo-path branch must not flag paths under a project dir that is the
# user's home (or a non-git dir). The branch matched PROJECT_ROOT as a literal
# substring and was never OS-suppressed. ---

# F1a — the reported incident: project dir is a NON-git home (e.g. a
# chezmoi-managed home, which is not itself a work tree). A .cmd suppresses the
# Windows-user branch, so ONLY the repo branch could fire; it must stay silent.
HOME_DIR="C:${BS}Users${BS}bob"
HOME_CMD="${HOME_DIR}${BS}Desktop${BS}run.cmd"
HOME_UNDER="${HOME_DIR}${BS}AppData${BS}Local${BS}Docker${BS}img.vhdx"
OUT=$(CLAUDE_PROJECT_DIR="$HOME_DIR" bash "$HOOK" <<<"$(write_json "$HOME_CMD" "copy $HOME_UNDER dst")" 2>&1)
RC=$?
assert_exit "F1: non-git home project + path under home → exit 0" 0 "$RC"
assert_silent "F1: non-git home → no stderr" "$OUT"

# The gate compares the git toplevel against $HOME, so the two must be in the
# same path form. git canonicalizes an MSYS /tmp path to a native Windows path on
# Git Bash, so derive $HOME from git's own --show-toplevel output (an identity on
# Linux, where /tmp is not remapped) — this mirrors a real environment, where
# $HOME and git agree on the path form.

# F1b — belt-and-suspenders: project dir IS a git checkout but equals $HOME
# (dotfiles-as-home). The enclosing-checkout-is-home clause suppresses the branch.
GITHOME="$TEST_TMPDIR/githome"
mkdir -p "$GITHOME"
git -C "$GITHOME" init -q
GITHOME_TL="$(git -C "$GITHOME" rev-parse --show-toplevel)"
OUT=$(HOME="$GITHOME_TL" CLAUDE_PROJECT_DIR="$GITHOME" \
  bash "$HOOK" <<<"$(write_json "$GITHOME/notes.txt" "path $GITHOME/data/app.bin")" 2>&1)
RC=$?
assert_exit "F1: git checkout equal to \$HOME → exit 0" 0 "$RC"
assert_silent "F1: \$HOME checkout → no stderr" "$OUT"

# F1c — the side door: $HOME is itself a git checkout (chezmoi dotfiles) and the
# project dir is a SUBDIR of home (e.g. $HOME/Desktop). rev-parse discovers the
# parent checkout at home; the home comparison must run against that TOPLEVEL,
# not the subdir — comparing the subdir leaves it neither home nor a home-ancestor
# and re-enables the branch, hard-denying paths under the subdir.
HOMEREPO="$TEST_TMPDIR/homerepo"
mkdir -p "$HOMEREPO/Desktop"
git -C "$HOMEREPO" init -q
HOMEREPO_TL="$(git -C "$HOMEREPO" rev-parse --show-toplevel)"
OUT=$(HOME="$HOMEREPO_TL" CLAUDE_PROJECT_DIR="$HOMEREPO/Desktop" \
  bash "$HOOK" <<<"$(write_json "$HOMEREPO/Desktop/run.txt" "path $HOMEREPO/Desktop/data.bin")" 2>&1)
RC=$?
assert_exit "F1: home-is-checkout, project = subdir of home → exit 0" 0 "$RC"
assert_silent "F1: home-checkout subdir → no stderr" "$OUT"

# ============================ TELEMETRY ====================================
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "hardcoded-path-check"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: violation label" "$(jq -r '.data.violations[]' "$TEL")" "Linux user path detected"
  assert_absent "telemetry: no matched path in envelope" "$(cat "$TEL")" "jdoe"
else
  bad "telemetry: no envelope written on block"
fi

report
