#!/usr/bin/env bash

set -uo pipefail
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/hardcoded-path-check.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
git -C "$TEST_TMPDIR" init -q

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

SKIPPED=0
# A case whose git path form this host cannot pin is neither a pass nor a failure.
# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
host_git_rewrites_worktree_path() {
  local d tl
  d="$(mktemp -d)"
  git -C "$d" init -q
  tl="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  rm -rf "$d"
  [[ -n "$tl" && "$tl" != "$d" ]]
}

unset CLAUDE_PROJECT_DIR

SL='/'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
LINUX_HOME="${SL}home${SL}jdoe${SL}project"
MAC_HOME="${SL}Users${SL}alice${SL}dev${SL}repo"
MAC_SHARED="${SL}Users${SL}Shared${SL}output"
WIN_HOME="C:${BS}Users${BS}bob${BS}repo"

FIXTURE="$TEST_TMPDIR/fixture.txt"
PS1_FIXTURE="$TEST_TMPDIR/script.ps1"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME} && ls")" 2>&1)
RC=$?
assert_exit "linux home → exit 2" 2 "$RC"
assert_contains "linux home → message" "$OUT" "Linux user path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${MAC_HOME} && ls")" 2>&1)
RC=$?
assert_exit "macos home → exit 2" 2 "$RC"
assert_contains "macos → message" "$OUT" "macOS user path"
if [[ "$OUT" == *$'\n\nUse portable alternatives:'* ]]; then
  ok "violation block → blank line before guidance"
else
  bad "violation block → blank line before guidance: expected \$'\\n\\nUse portable alternatives:' in output: $OUT"
fi

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${WIN_HOME} && dir")" 2>&1)
RC=$?
assert_exit "windows home → exit 2" 2 "$RC"
assert_contains "windows → message" "$OUT" "Windows user path"

LONG_LINE="var a=\"$(printf 'x%.0s' {1..600})\";cd ${LINUX_HOME};var b=\"$(printf 'y%.0s' {1..600})\";"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "$LONG_LINE")" 2>&1)
RC=$?
assert_exit "minified line with a linux home → exit 2" 2 "$RC"
assert_contains "report names the file project-relative" "$OUT" "path(s) in fixture.txt:"
assert_absent "report does not name the absolute file" "$OUT" "$FIXTURE"
longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' <<<"$OUT")
if ((longest <= 160)); then
  ok "no report line exceeds 160 characters (longest $longest)"
else
  bad "a report line is $longest characters, over the 160 cap"
fi

NUL_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$FIXTURE" --arg p "$LINUX_HOME" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:("harmless first line" + ([0] | implode) + "cd " + $p + " && ls")}}')
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$NUL_PAYLOAD" 2>&1)
RC=$?
assert_exit "machine path AFTER a NUL byte in content → exit 2" 2 "$RC"
assert_contains "path after NUL → NUL refusal message" "$OUT" "NUL byte"

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

NB_PROBE="$TEST_TMPDIR/plugins/guardrails/probe-notebook.ipynb"
for NB_VIA in direct dispatched; do
  expect "NotebookEdit real shape in project ($NB_VIA) → exit 2" 2 --via "$NB_VIA" --hook "$HOOK" \
    --merge-stderr --payload "$(notebook_json "$NB_PROBE" "cd ${LINUX_HOME}")" -- CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
  assert_contains "NotebookEdit real shape ($NB_VIA) → message" "$GUARD_OUT" "Linux user path"
done
NB_FAKE=$(MSYS_NO_PATHCONV=1 jq -n --arg fp "$NB_PROBE" --arg s "cd ${LINUX_HOME}" \
  '{tool_name:"NotebookEdit",tool_input:{file_path:$fp,new_source:$s}}')
expect_both "NotebookEdit file_path fallback → exit 2" 2 --hook "$HOOK" --merge-stderr \
  --payload "$NB_FAKE" -- CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
NB_BOTH=$(MSYS_NO_PATHCONV=1 jq -n --arg np "/tmp/other/n.ipynb" --arg fp "$NB_PROBE" --arg s "cd ${LINUX_HOME}" \
  '{tool_name:"NotebookEdit",tool_input:{notebook_path:$np,file_path:$fp,new_source:$s}}')
expect_both "NotebookEdit out-of-project notebook_path, in-project file_path → exit 0" 0 \
  --hook "$HOOK" --merge-stderr --payload "$NB_BOTH" -- CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
expect_both "NotebookEdit real shape outside the project → exit 0" 0 --hook "$HOOK" --merge-stderr \
  --payload "$(notebook_json "/tmp/other/n.ipynb" "cd ${LINUX_HOME}")" -- CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
NB_REPO="$TEST_TMPDIR/nbrepo"
mkdir -p "$NB_REPO"
git -C "$NB_REPO" init -q
printf 'ignored.ipynb\n' >"$NB_REPO/.gitignore"
expect_both "NotebookEdit real shape to a gitignored notebook → exit 0" 0 --hook "$HOOK" --merge-stderr \
  --payload "$(notebook_json "$NB_REPO/ignored.ipynb" "cd ${LINUX_HOME}")" -- CLAUDE_PROJECT_DIR="$NB_REPO"
expect_both "NotebookEdit real shape to a tracked-path notebook → exit 2" 2 --hook "$HOOK" --merge-stderr \
  --payload "$(notebook_json "$NB_REPO/kept.ipynb" "cd ${LINUX_HOME}")" -- CLAUDE_PROJECT_DIR="$NB_REPO"

REPO_REAL="$TEST_TMPDIR/realrepo"
mkdir -p "$REPO_REAL"
git -C "$REPO_REAL" init -q
OUT=$(HOME="$TEST_TMPDIR/elsewhere" CLAUDE_PROJECT_DIR="$REPO_REAL" \
  bash "$HOOK" <<<"$(write_json "$REPO_REAL/notes.txt" "checkout at $REPO_REAL/src")" 2>&1)
RC=$?
assert_exit "repo root in real non-home checkout → exit 2" 2 "$RC"
assert_contains "repo root → machine-specific repo message" "$OUT" "Machine-specific repo path"

SUBREPO="$TEST_TMPDIR/subrepo"
mkdir -p "$SUBREPO/pkg"
git -C "$SUBREPO" init -q
OUT=$(HOME="$TEST_TMPDIR/elsewhere2" CLAUDE_PROJECT_DIR="$SUBREPO/pkg" \
  bash "$HOOK" <<<"$(write_json "$SUBREPO/pkg/notes.txt" "at $SUBREPO/pkg/x")" 2>&1)
RC=$?
assert_exit "repo subdir of non-home checkout → exit 2" 2 "$RC"
assert_contains "repo subdir → machine-specific repo message" "$OUT" "Machine-specific repo path"

KREPO="$TEST_TMPDIR/kroot"
mkdir -p "$KREPO"
git -C "$KREPO" init -q
KUPPER="${KREPO%/kroot}/KROOT"
OUT=$(HOME="$TEST_TMPDIR/elsewhere3" CLAUDE_PROJECT_DIR="$KREPO" \
  bash "$HOOK" <<<"$(write_json "$KREPO/notes.txt" "at $KUPPER/x")" 2>&1)
RC=$?
assert_exit "case-variant repo root → exit 2" 2 "$RC"
KELVIN="${KREPO%/kroot}/"$'\xe2\x84\xaa'"root/x"
KWANT=0
grep -qFi "$KREPO" < <(printf 'at %s' "$KELVIN") && KWANT=2
OUT=$(HOME="$TEST_TMPDIR/elsewhere3" CLAUDE_PROJECT_DIR="$KREPO" \
  bash "$HOOK" <<<"$(write_json "$KREPO/notes.txt" "at $KELVIN")" 2>&1)
RC=$?
assert_exit "Kelvin-sign repo root → same verdict as grep -Fi ($KWANT)" "$KWANT" "$RC"

for DSEG in -foo -e --help; do
  DREPO="$TEST_TMPDIR/dash/$DSEG"
  mkdir -p "$DREPO"
  git -C "$DREPO" init -q
  OUT=$(HOME="$TEST_TMPDIR/elsewhere4" CLAUDE_PROJECT_DIR="$DREPO" \
    bash "$HOOK" <<<"$(write_json "$DREPO/notes.txt" "at $DREPO/x")" 2>&1)
  RC=$?
  assert_exit "dash root $DSEG in content → exit 2" 2 "$RC"
  assert_contains "dash root $DSEG → machine-specific repo message" "$OUT" "Machine-specific repo path"
  OUT=$(HOME="$TEST_TMPDIR/elsewhere4" CLAUDE_PROJECT_DIR="$DREPO" \
    bash "$HOOK" <<<"$(write_json "$DREPO/notes.txt" "clean text")" 2>&1)
  RC=$?
  assert_exit "dash root $DSEG, clean content → exit 0" 0 "$RC"
  if [[ -z "$OUT" ]]; then ok "dash root $DSEG, clean content → silent"; else fail "dash root $DSEG, clean content → output: $OUT"; fi
done

HPP_LIB="$HOOK_DIR/../lib/path-detection/hardcoded-path-patterns.sh"
OUT=$(bash -c 'source "$1"; readonly LC_ALL=C.UTF-8; hpp::scan_text "at /r/work/x" /r/work a.txt; echo "rc=$?"' _ "$HPP_LIB" 2>&1)
assert_contains "readonly LC_ALL → root still flagged" "$OUT" "Machine-specific repo path"
assert_contains "readonly LC_ALL → rc 1" "$OUT" "rc=1"
OUT=$(LC_ALL=xx_XX.UTF-8 bash -c 'source "$1"; exec 2>&1; hpp::scan_text a /r/work a.txt; echo "rc=$? lc=$LC_ALL"' _ "$HPP_LIB")
if [[ "$OUT" == "rc=0 lc=xx_XX.UTF-8" ]]; then ok "missing-locale LC_ALL → restored, no warning"; else fail "missing-locale LC_ALL → got: $OUT"; fi

WIN_PROJECTS="D:${BS}Projects${BS}acme${BS}src"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "build from ${WIN_PROJECTS}")" 2>&1)
RC=$?
assert_exit "windows Projects checkout root → exit 2" 2 "$RC"
assert_contains "windows Projects root → message" "$OUT" "Windows repo path"

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

ESC_BARE_REPO="C:${BS}${BS}Dev${BS}${BS}GitHub"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cfg = \"${ESC_BARE_REPO}\"")" 2>&1)
RC=$?
assert_exit "escaped bare windows repo value → exit 2" 2 "$RC"
assert_contains "escaped bare repo value → message" "$OUT" "Escaped Windows repo path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "projects - personal repos (reference${SL}reading only)")" 2>&1)
RC=$?
assert_exit "checkout-root prose with later slash → exit 0" 0 "$RC"
assert_silent "checkout-root prose → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see ${SL}Users${SL} for details")" 2>&1)
RC=$?
assert_exit "bare Users root + prose → exit 0" 0 "$RC"
assert_silent "bare Users root prose → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${LINUX_HOME} && ls")" 2>&1)
RC=$?
assert_exit "no project + machine path → exit 0 (skip)" 0 "$RC"
assert_silent "no project → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "path = ${WIN_HOME}")" 2>&1)
RC=$?
assert_exit "no project + Edit dotfile-style path → exit 0 (skip)" 0 "$RC"
assert_silent "no project Edit → no stderr" "$OUT"

NONREPO="$(mktemp -d)"
mkdir -p "$NONREPO/.claude"
OUT=$(CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" <<<"$(write_json "$NONREPO/.claude/tool.conf" "root = ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "non-worktree project + machine-local conf → exit 0 (skip)" 0 "$RC"
assert_silent "non-worktree project → no stderr" "$OUT"
rm -rf "$NONREPO"

WT="$TEST_TMPDIR/realwt"
mkdir -p "$WT"
git -C "$WT" init -q
OUT=$(CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" <<<"$(write_json "$WT/notes.txt" "root = ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "same content in real work tree → exit 2" 2 "$RC"
assert_contains "real work tree → linux message" "$OUT" "Linux user path"

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

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${SL}Users${SL}Shared")" 2>&1)
RC=$?
assert_exit "bare macos Shared at EOL → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp ${SL}Users${SL}Shared ${SL}Users${SL}alice")" 2>&1)
RC=$?
assert_exit "Shared + user path on one line → exit 2" 2 "$RC"
assert_contains "Shared + user path → macOS message" "$OUT" "macOS user path"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${SL}Users${SL}SharedStuff")" 2>&1)
RC=$?
assert_exit "SharedStuff segment → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${SL}Users${SL}Shared; ls")" 2>&1)
RC=$?
assert_exit "Shared followed by semicolon → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp '${SL}Users${SL}Shared' out")" 2>&1)
RC=$?
assert_exit "single-quoted Shared → exit 0" 0 "$RC"

RUNNER_HOME="${SL}home${SL}runner"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cd ${RUNNER_HOME}${SL}work${SL}repo && ls")" 2>&1)
RC=$?
assert_exit "runner home with a child path → exit 0" 0 "$RC"
assert_silent "runner home → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "{\"cwd\": \"${RUNNER_HOME}\"}")" 2>&1)
RC=$?
assert_exit "bare quoted runner home → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${RUNNER_HOME}2${SL}x")" 2>&1)
RC=$?
assert_exit "runner2 segment → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "ls ${RUNNER_HOME}-x${SL}y")" 2>&1)
RC=$?
assert_exit "runner-x segment → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "cp ${RUNNER_HOME}${SL}a ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "runner home + user home on one line → exit 2" 2 "$RC"
assert_contains "runner home + user home → linux message" "$OUT" "Linux user path"
assert_absent "runner home + user home → never reports the defanged copy" "$OUT" "${SL}home-runner"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "copy ${WIN_HOME}${BS}a.txt ${WIN_HOME}${BS}b.txt")" 2>&1)
RC=$?
assert_exit "macOS candidates all excluded as Windows → exit 0" 0 "$RC"
assert_silent "all-Windows candidates → no stderr" "$OUT"

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

COL0="ls ${SL}Users${SL}Shared${SL}a
${MAC_HOME} is the checkout"
OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "$COL0")" 2>&1)
RC=$?
assert_exit "Shared block, violation at column 0 → exit 2" 2 "$RC"
assert_contains "column-0 violation → original file line number" "$OUT" "2:${MAC_HOME}"

SPAWN_SHIM="$TEST_TMPDIR/spawn-shim"
SPAWN_LOG="$TEST_TMPDIR/spawn-log"
mkdir -p "$SPAWN_SHIM"
for _bin in grep sed; do
  _real="$(command -v "$_bin")"
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

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see https://example.test${SL}home${SL}alice for docs")" 2>&1)
RC=$?
assert_exit "URL containing home suffix → exit 0" 0 "$RC"
assert_silent "URL home suffix → no stderr" "$OUT"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "see https://example.test${SL}Users${SL}alice page")" 2>&1)
RC=$?
assert_exit "URL containing Users suffix → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$FIXTURE" "vol:${SL}home${SL}alice mount")" 2>&1)
RC=$?
assert_exit "colon-prefixed linux home → exit 2" 2 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$PS1_FIXTURE" "\$cfg = '${WIN_HOME}'")" 2>&1)
RC=$?
assert_exit "Windows path in .ps1 → suppressed → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1)
RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "/tmp/other/file.txt" "$LINUX_HOME")" 2>&1)
RC=$?
assert_exit "outside CLAUDE_PROJECT_DIR → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/.claude/hooks/foo.sh" "pattern ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/.lefthook/pre-commit/foo.sh" "pattern ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit ".lefthook/ self-exemption → exit 0" 0 "$RC"

HOMECO="$TEST_TMPDIR/homeco"
mkdir -p "$HOMECO"
git -C "$HOMECO" init -q
OUT=$(CLAUDE_PROJECT_DIR="$HOMECO" bash "$HOOK" <<<"$(write_json "$HOMECO/.claude/projects/my-repo/wf.js" "const out = '${WIN_HOME}'")" 2>&1)
RC=$?
assert_exit ".claude/projects/ CC-state self-exemption → exit 0" 0 "$RC"

GITREPO="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITREPO"
git -C "$GITREPO" init -q
printf 'ignored.txt\n' >"$GITREPO/.gitignore"
# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
if host_git_rewrites_worktree_path; then
  skip "gitignored file → exit 0 (consumer seam)" \
    "git --show-toplevel spelling diverges from the bash fixture path"
else
  OUT=$(CLAUDE_PROJECT_DIR="$GITREPO" bash "$HOOK" <<<"$(write_json "$GITREPO/ignored.txt" "$LINUX_HOME")" 2>&1)
  RC=$?
  assert_exit "gitignored file → exit 0 (consumer seam)" 0 "$RC"
  git -C "$GITREPO" add .gitignore
  printf '#!/bin/sh\ntouch "%s"\n' "$TEST_TMPDIR/fsm-ran" >"$TEST_TMPDIR/fsm.sh"
  chmod +x "$TEST_TMPDIR/fsm.sh"
  git -C "$GITREPO" config core.fsmonitor "$TEST_TMPDIR/fsm.sh"
  OUT=$(CLAUDE_PROJECT_DIR="$GITREPO" bash "$HOOK" <<<"$(write_json "$GITREPO/ignored.txt" "$LINUX_HOME")" 2>&1)
  RC=$?
  assert_exit "gitignored file, planted core.fsmonitor → exit 0" 0 "$RC"
  assert_file_absent "gitignored file: a planted core.fsmonitor never runs" "$TEST_TMPDIR/fsm-ran"
  git -C "$GITREPO" check-ignore -q -- ignored.txt >/dev/null 2>&1
  if [[ -e "$TEST_TMPDIR/fsm-ran" ]]; then ok "fixture: plain git check-ignore runs the planted fsmonitor"; else bad "fixture: the planted fsmonitor never fires, so the check above proves nothing"; fi
fi

OUT=$(CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "$LINUX_HOME")" 2>&1)
RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"


HOME_DIR="C:${BS}Users${BS}bob"
HOME_CMD="${HOME_DIR}${BS}Desktop${BS}run.cmd"
HOME_UNDER="${HOME_DIR}${BS}AppData${BS}Local${BS}Docker${BS}img.vhdx"
OUT=$(CLAUDE_PROJECT_DIR="$HOME_DIR" bash "$HOOK" <<<"$(write_json "$HOME_CMD" "copy $HOME_UNDER dst")" 2>&1)
RC=$?
assert_exit "F1: non-git home project + path under home → exit 0" 0 "$RC"
assert_silent "F1: non-git home → no stderr" "$OUT"


GITHOME="$TEST_TMPDIR/githome"
mkdir -p "$GITHOME"
git -C "$GITHOME" init -q
GITHOME_TL="$(git -C "$GITHOME" rev-parse --show-toplevel)"
OUT=$(HOME="$GITHOME_TL" CLAUDE_PROJECT_DIR="$GITHOME" \
  bash "$HOOK" <<<"$(write_json "$GITHOME/notes.txt" "path $GITHOME/data/app.bin")" 2>&1)
RC=$?
assert_exit "F1: git checkout equal to \$HOME → exit 0" 0 "$RC"
assert_silent "F1: \$HOME checkout → no stderr" "$OUT"

HOMEREPO="$TEST_TMPDIR/homerepo"
mkdir -p "$HOMEREPO/Desktop"
git -C "$HOMEREPO" init -q
HOMEREPO_TL="$(git -C "$HOMEREPO" rev-parse --show-toplevel)"
# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
if host_git_rewrites_worktree_path; then
  skip "F1: home-is-checkout, project = subdir of home → exit 0" \
    "git --show-toplevel spelling diverges from the bash fixture path"
else
  OUT=$(HOME="$HOMEREPO_TL" CLAUDE_PROJECT_DIR="$HOMEREPO/Desktop" \
    bash "$HOOK" <<<"$(write_json "$HOMEREPO/Desktop/run.txt" "path $HOMEREPO/Desktop/data.bin")" 2>&1)
  RC=$?
  assert_exit "F1: home-is-checkout, project = subdir of home → exit 0" 0 "$RC"
  assert_silent "F1: home-checkout subdir → no stderr" "$OUT"
fi

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

HOOK_SRC=$(cat "$HOOK")
assert_contains "path helper: uses hook::repo_relative_path_to" "$HOOK_SRC" 'hook::repo_relative_path_to'
assert_absent "path helper: no hand-rolled prefix strip" "$HOOK_SRC" '_fwd#'

TELP="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKP="$(make_sink "cat >\"$TELP\"")"
mkdir -p "$TEST_TMPDIR/src"
env HOOK_TELEMETRY_SINK="$SINKP" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/src/run.sh" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || true
if wait_for_sink "$TELP"; then
  assert_contains "telemetry: data.file is repo-relative" "$(jq -r '.data.file' "$TELP")" "src/run.sh"
else
  bad "telemetry: no envelope written for the repo-relative case"
fi

TELPS="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKPS="$(make_sink "cat >\"$TELPS\"")"
env HOOK_TELEMETRY_SINK="$SINKPS" CLAUDE_PROJECT_DIR="$TEST_TMPDIR/" \
  bash "$HOOK" <<<"$(write_json "$TEST_TMPDIR/src/run.sh" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || true
if wait_for_sink "$TELPS"; then
  assert_eq "trailing-slash project dir: data.file stays repo-relative" \
    "src/run.sh" "$(jq -r '.data.file' "$TELPS")"
else
  bad "trailing-slash project dir: no envelope written"
fi

TELOK="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKOK="$(make_sink "cat >>\"$TELOK\"")"
env HOOK_TELEMETRY_SINK="$SINKOK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(write_json "$FIXTURE" 'echo "hello world"')" >/dev/null 2>&1 || true
if wait_for_sink "$TELOK"; then
  sleep 0.2
  assert_eq "telemetry on, clean content: exactly one envelope" "1" "$(jq -s 'length' "$TELOK")"
  assert_eq "telemetry on, clean content: status ok" "ok" "$(jq -rs '.[0].status' "$TELOK")"
else
  bad "telemetry on, clean content: no envelope written"
fi

GITSHIM="$(mktemp -d "$TEST_TMPDIR/gitshim.XXXXXX")"
printf '#!/usr/bin/env bash\ntouch "%s/called"\nexit 1\n' "$GITSHIM" >"$GITSHIM/git"
chmod +x "$GITSHIM/git"
OUT=$(env -u HOOK_TELEMETRY_SINK PATH="$GITSHIM:$PATH" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(write_json "$FIXTURE" 'echo "hello world"')" 2>&1)
RC=$?
assert_exit "telemetry off, clean content, git unreachable → exit 0" 0 "$RC"
assert_silent "telemetry off, clean content → no stderr" "$OUT"
if [[ -e "$GITSHIM/called" ]]; then
  bad "telemetry off, clean content: git was called (early exit not taken)"
else
  ok "telemetry off, clean content: no git call"
fi


run_bounded() {
  local rc=0
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$TEST_TMPDIR" timeout 150 bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

for SZ in 65535 65536 65600 65663 65664; do
  assert_bounded_exit "boundary: clean ${SZ}-byte payload → exit 0" \
    0 "$(run_bounded "$(sized_write_json "$SZ")")"
done

for SZ in 65536 65600; do
  assert_bounded_exit "boundary: linux home path in ${SZ}-byte payload → exit 2" \
    2 "$(run_bounded "$(sized_write_json "$SZ" "$LINUX_HOME")")"
done

BOUND_ERR=$(printf '%s' "$(sized_write_json 65600 "$LINUX_HOME")" |
  CLAUDE_PROJECT_DIR="$TEST_TMPDIR" timeout 150 bash "$HOOK" 2>&1 >/dev/null)
assert_contains "boundary: in-window block still reports the label" "$BOUND_ERR" "Linux user path"
assert_absent "boundary: no SIGPIPE noise on stderr" "$BOUND_ERR" "Broken pipe"

RC=0
printf '%s' "$(sized_write_json 0)" |
  CLAUDE_PROJECT_DIR="$TEST_TMPDIR" timeout 30 bash "$HOOK" >/dev/null 2>&1 || RC=$?
assert_exit "boundary: empty content → exit 0" 0 "$RC"


RC=0
bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "import os")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP create_or_update_file: clean content → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "cd ${LINUX_HOME} && ls")" 2>&1)
RC=$?
assert_exit "MCP create_or_update_file: Linux user path → exit 2" 2 "$RC"
assert_contains "MCP create_or_update_file: names the label" "$OUT" "Linux user path detected"
assert_contains "MCP create_or_update_file: names the repo path" "$OUT" "src/app.py"
assert_contains "MCP create_or_update_file: names the GitHub destination" "$OUT" "content bound for GitHub"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "p = '${MAC_HOME}'")" 2>&1)
RC=$?
assert_exit "MCP create_or_update_file: macOS user path → exit 2" 2 "$RC"

RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "y = 2")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: all clean → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "cd ${LINUX_HOME}" "b.py" "y = 2")" 2>&1)
RC=$?
assert_exit "MCP push_files: bad path in the FIRST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: first-file block names its path" "$OUT" "a.py"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "cd ${LINUX_HOME}")" 2>&1)
RC=$?
assert_exit "MCP push_files: bad path in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: last-file block names its path" "$OUT" "b.py"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","files":[]}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: empty files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: absent files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__delete_file","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","path":"src/app.py"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP delete_file: no content to scan → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "cd ${LINUX_HOME} && ls" | scoped create_or_update_file)" 2>&1)
RC=$?
assert_exit "MCP scoped create_or_update_file: Linux user path → exit 2" 2 "$RC"
assert_contains "MCP scoped create_or_update_file: names the repo path" "$OUT" "src/app.py"
OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "cd ${LINUX_HOME}" | scoped push_files)" 2>&1)
RC=$?
assert_exit "MCP scoped push_files: bad path in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP scoped push_files: names the last file" "$OUT" "b.py"

RC=0
bash "$HOOK" <<<"$(mcp_single_json ".claude/hooks/guard.sh" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted .claude/hooks path is exempt" 0 "$RC"

RC=0
bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: an UNSET CLAUDE_PROJECT_DIR does not skip the remote write" 2 "$RC"
RC=0
CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a SET CLAUDE_PROJECT_DIR does not skip the remote write" 2 "$RC"

RC=0
CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED=false bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "cd ${LINUX_HOME}")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: disabled guard allows the write" 0 "$RC"

echo "SKIPPED=$SKIPPED"
report
