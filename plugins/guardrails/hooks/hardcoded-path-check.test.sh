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

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Neutralize ambient CLAUDE_PROJECT_DIR so default cases hit the intended path.
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
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME} && ls")" 2>&1); RC=$?
assert_exit "linux home → exit 2" 2 "$RC"
assert_contains "linux home → message" "$OUT" "Linux user path"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${MAC_HOME} && ls")" 2>&1); RC=$?
assert_exit "macos home → exit 2" 2 "$RC"
assert_contains "macos → message" "$OUT" "macOS user path"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${WIN_HOME} && dir")" 2>&1); RC=$?
assert_exit "windows home → exit 2" 2 "$RC"
assert_contains "windows → message" "$OUT" "Windows user path"

# Cross-OS leak: a Linux path inside a .ps1 still fires (only Windows is suppressed).
OUT=$(bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "Set-Location ${LINUX_HOME}")" 2>&1); RC=$?
assert_exit "Linux leak in .ps1 → exit 2" 2 "$RC"
assert_contains "cross-OS leak → linux message" "$OUT" "Linux user path"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "new path ${LINUX_HOME}")" 2>&1); RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "cd ${MAC_HOME}")" 2>&1); RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

# Repo-path branch: a genuine (non-home) git checkout root hardcoded in content
# is a machine-specific marker and MUST still fire — guards against the home-gate
# over-suppressing the branch entirely (the branch had no prior test).
REPO_REAL="$TEST_TMPDIR/realrepo"
mkdir -p "$REPO_REAL"
git -C "$REPO_REAL" init -q
OUT=$(HOME="$TEST_TMPDIR/elsewhere" CLAUDE_PROJECT_DIR="$REPO_REAL" \
  bash "$HOOK" <<<"$(write_json "$REPO_REAL/notes.txt" "checkout at $REPO_REAL/src")" 2>&1); RC=$?
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
  bash "$HOOK" <<<"$(write_json "$SUBREPO/pkg/notes.txt" "at $SUBREPO/pkg/x")" 2>&1); RC=$?
assert_exit "repo subdir of non-home checkout → exit 2" 2 "$RC"
assert_contains "repo subdir → machine-specific repo message" "$OUT" "Machine-specific repo path"

# Generic Windows checkout root under a widened root name (Projects/Dev/Repos):
# content carries no "Users"/"repos" literal, so it exercises the cheap
# pre-filter gate — which must trip on every root HPP_WIN_REPO_BODY accepts, or
# the scan early-returns and the leak passes (fail-open).
WIN_PROJECTS="D:${BS}Projects${BS}acme${BS}src"
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "build from ${WIN_PROJECTS}")" 2>&1); RC=$?
assert_exit "windows Projects checkout root → exit 2" 2 "$RC"
assert_contains "windows Projects root → message" "$OUT" "Windows repo path"

# ============================ ALLOW (exit 0) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'echo "hello world"')" 2>&1); RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

# shellcheck disable=SC2016
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'cd $HOME/project && cd ~/dev')" 2>&1); RC=$?
assert_exit "dynamic \$HOME / ~ → exit 0" 0 "$RC"
assert_silent "dynamic refs → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp file ${MAC_SHARED}")" 2>&1); RC=$?
assert_exit "macos Shared dir → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "\$cfg = '${WIN_HOME}'")" 2>&1); RC=$?
assert_exit "Windows path in .ps1 → suppressed → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1); RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

# Outside CLAUDE_PROJECT_DIR → exit 0 (another repo's concern).
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "/tmp/other/file.txt" "$LINUX_HOME")" 2>&1); RC=$?
assert_exit "outside CLAUDE_PROJECT_DIR → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/some/repo/.claude/hooks/foo.sh" "pattern ${LINUX_HOME}")" 2>&1); RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/some/repo/.lefthook/pre-commit/foo.sh" "pattern ${LINUX_HOME}")" 2>&1); RC=$?
assert_exit ".lefthook/ self-exemption → exit 0" 0 "$RC"

# CC session/workflow state under ~/.claude/projects/ (outside any repo tree).
projects_fp="C:${BS}Users${BS}bob${BS}.claude${BS}projects${BS}my-repo${BS}wf.js"
OUT=$(bash "$HOOK" <<<"$(write_json "$projects_fp" "const out = '${WIN_HOME}'")" 2>&1); RC=$?
assert_exit ".claude/projects/ CC-state self-exemption → exit 0" 0 "$RC"

# Gitignored file → exit 0 (consumer seam via .gitignore + git check-ignore).
GITREPO="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
printf 'ignored.txt\n' >"$GITREPO/.gitignore"
OUT=$(CLAUDE_PROJECT_DIR="$GITREPO" bash "$HOOK" <<<"$(write_json "$GITREPO/ignored.txt" "$LINUX_HOME")" 2>&1); RC=$?
assert_exit "gitignored file → exit 0 (consumer seam)" 0 "$RC"

# Kill switch — disabled path is a clean no-op even on a real machine path.
OUT=$(CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "$LINUX_HOME")" 2>&1); RC=$?
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
OUT=$(CLAUDE_PROJECT_DIR="$HOME_DIR" bash "$HOOK" <<<"$(write_json "$HOME_CMD" "copy $HOME_UNDER dst")" 2>&1); RC=$?
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
  bash "$HOOK" <<<"$(write_json "$GITHOME/notes.txt" "path $GITHOME/data/app.bin")" 2>&1); RC=$?
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
  bash "$HOOK" <<<"$(write_json "$HOMEREPO/Desktop/run.txt" "path $HOMEREPO/Desktop/data.bin")" 2>&1); RC=$?
assert_exit "F1: home-is-checkout, project = subdir of home → exit 0" 0 "$RC"
assert_silent "F1: home-checkout subdir → no stderr" "$OUT"

# ============================ TELEMETRY ====================================
TEL="$(mktemp -p "$TEST_TMPDIR")"
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
