#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAP="$SCRIPT_DIR/worktree-reap.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

OLD_TS=1700000000
NOW_TS=$((OLD_TS + 72 * 3600))

assert_dir_exists() {
  local label="$1" path="$2"
  if [[ -d "$path" ]]; then
    pass "$label"
  else
    _fail_with "$label" "expected directory $path"
  fi
}

assert_dir_absent() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    pass "$label"
  else
    _fail_with "$label" "expected absent, found $path"
  fi
}

mkrepo_with_origin() {
  local origin work
  origin="$(mktemp -d "$TEST_TMPDIR/originXXXXXX")"
  work="$(mktemp -d "$TEST_TMPDIR/workXXXXXX")"
  {
    git init -q --bare -b main "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.email t@t.t
    git -C "$work" config user.name t
    git -C "$work" config commit.gpgsign false
    printf 'seed\n' >"$work/README.md"
    git -C "$work" add README.md
    GIT_AUTHOR_DATE="@$OLD_TS +0000" GIT_COMMITTER_DATE="@$OLD_TS +0000" \
      git -C "$work" commit -qm init
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -q -u origin main
    git -C "$work" remote set-head origin main
  } >/dev/null 2>&1
  printf '%s\t%s' "$work" "$origin"
}

commit_at() {
  local dir="$1" file="$2" content="$3" msg="$4" ts="$5"
  printf '%s\n' "$content" >"$dir/$file"
  git -C "$dir" add "$file" >/dev/null 2>&1
  GIT_AUTHOR_DATE="@$ts +0000" GIT_COMMITTER_DATE="@$ts +0000" \
    git -C "$dir" commit -qm "$msg" >/dev/null 2>&1
}

PROC_OK="$TEST_TMPDIR/proc-ok"
mkdir -p "$PROC_OK/9999/fd"
ln -s /tmp "$PROC_OK/9999/cwd"

CFG="$TEST_TMPDIR/claude-cfg"
mkdir -p "$CFG/projects/-proj" "$CFG/sessions" "$CFG/plugins"
HOST_NAME="reaphost"
make_lock_reason() {
  HOSTNAME="$HOST_NAME" bash -c 'source "$1"; worktree_lock_reason worktree-create.sh "$2"' \
    _ "$SCRIPT_DIR/lib/worktree-facts.sh" "$1"
}

IFS=$'\t' read -r REPO ORIGIN <<<"$(mkrepo_with_origin)"
printf '*.env\n' >"$REPO/.gitignore"
printf '*.env' >"$REPO/.worktreeinclude"
git -C "$REPO" add .gitignore .worktreeinclude
GIT_AUTHOR_DATE="@$OLD_TS +0000" GIT_COMMITTER_DATE="@$OLD_TS +0000" \
  git -C "$REPO" commit -qm "add worktreeinclude"
git -C "$REPO" push -q origin main
printf 'main-env\n' >"$REPO/app.env"

ROOT1="$TEST_TMPDIR/root1"
ROOT2="$TEST_TMPDIR/root2-chezmoi"
mkdir -p "$ROOT1" "$ROOT2"

git -C "$REPO" worktree add -q --detach "$ROOT1/wt-detached" main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT1/wt-detached/.git"

for i in 1 2 3; do
  wt="$ROOT1/wt-notrack-$i"
  git -C "$REPO" worktree add -q --no-track -b "feat/notrack-$i" "$wt" origin/main >/dev/null 2>&1
  commit_at "$wt" "nt-$i.txt" "nt $i" "nt $i" "$OLD_TS"
  git -C "$REPO" merge -q --ff-only "feat/notrack-$i" >/dev/null 2>&1
  git -C "$REPO" push -q origin main >/dev/null 2>&1
  touch -d "@$OLD_TS" "$wt/.git"
  git -C "$REPO" worktree lock --reason "$(make_lock_reason "stale-sess-$i")" "$wt"
done

git -C "$REPO" worktree add -q -b feat/dirty-untracked "$ROOT1/wt-dirty" main >/dev/null 2>&1
commit_at "$ROOT1/wt-dirty" "d.txt" "d" "d" "$OLD_TS"
git -C "$ROOT1/wt-dirty" push -q -u origin feat/dirty-untracked >/dev/null 2>&1
git -C "$REPO" merge -q --ff-only feat/dirty-untracked >/dev/null 2>&1
git -C "$REPO" push -q origin main >/dev/null 2>&1
git -C "$ORIGIN" branch -D feat/dirty-untracked >/dev/null 2>&1
printf 'untracked!\n' >"$ROOT1/wt-dirty/keep-me.txt"
touch -d "@$OLD_TS" "$ROOT1/wt-dirty/.git"

git -C "$REPO" worktree add -q -b feat/carried-diff "$ROOT1/wt-carried" main >/dev/null 2>&1
commit_at "$ROOT1/wt-carried" "c.txt" "c" "c" "$OLD_TS"
git -C "$ROOT1/wt-carried" push -q -u origin feat/carried-diff >/dev/null 2>&1
git -C "$REPO" merge -q --ff-only feat/carried-diff >/dev/null 2>&1
git -C "$REPO" push -q origin main >/dev/null 2>&1
git -C "$ORIGIN" branch -D feat/carried-diff >/dev/null 2>&1
printf 'edited-in-wt\n' >"$ROOT1/wt-carried/app.env"
touch -d "@$OLD_TS" "$ROOT1/wt-carried/.git"

git -C "$REPO" worktree add -q --no-track -b feat/reasonless "$ROOT1/wt-reasonless" origin/main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT1/wt-reasonless/.git"
git -C "$REPO" worktree lock "$ROOT1/wt-reasonless"

IFS=$'\t' read -r REPO2 _ORIGIN2 <<<"$(mkrepo_with_origin)"
git -C "$REPO2" worktree add -q --no-track -b feat/chez-landed "$ROOT2/wt-chez" origin/main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT2/wt-chez/.git"

INC_FILE="$TEST_TMPDIR/chez.gitconfig"
printf '[worktreeroot]\n\tpath = %s\n' "$ROOT2" >"$INC_FILE"
GCFG="$TEST_TMPDIR/gitconfig"
{
  printf '[worktreeroot]\n\tpath = %s\n' "$ROOT1"
  printf '[includeIf "gitdir:%s/"]\n\tpath = %s\n' "$REPO2" "$INC_FILE"
} >"$GCFG"

WT1_PHYS="$(physical_dir "$ROOT1/wt-notrack-1")"
cat >"$CFG/plugins/installed_plugins.json" <<EOF
{
  "plugins": {
    "source-control@melodic-software": [
      {"scope": "project", "projectPath": "$WT1_PHYS", "installPath": "/tmp/p1"},
      {"scope": "local", "projectPath": "$WT1_PHYS", "installPath": "/tmp/p2"}
    ]
  }
}
EOF

WRAP_SCRIPTS="$TEST_TMPDIR/wrap-scripts"
STALE_LOG="$TEST_TMPDIR/stale-calls.log"
mkdir -p "$WRAP_SCRIPTS/lib"
cp -p "$SCRIPT_DIR/lib/worktree-facts.sh" "$WRAP_SCRIPTS/lib/"
cp -p "$SCRIPT_DIR/landed-work.sh" "$SCRIPT_DIR/worktree-root-resolve.sh" \
  "$SCRIPT_DIR/worktree-root-legacy.sh" "$SCRIPT_DIR/worktree-include.sh" "$WRAP_SCRIPTS/"
cat >"$WRAP_SCRIPTS/worktree-claim.sh" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == stale ]]; then
  printf '%s\n' "\$*" >>"$STALE_LOG"
fi
exec bash "$SCRIPT_DIR/worktree-claim.sh" "\$@"
EOF
chmod +x "$WRAP_SCRIPTS/worktree-claim.sh"

: >"$STALE_LOG"
OUT="$(
  GIT_CONFIG_GLOBAL="$GCFG" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_SCRIPTS="$WRAP_SCRIPTS" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" \
    WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --dry-run --no-log --no-pr-proof 2>&1
)"
assert_exit "dry-run exits 0" 0 "$?"
assert_contains "dry-run discovers root1 and includeIf root2" "$OUT" "$ROOT2"
assert_contains "dry-run proposes --no-track FF worktree 1" "$OUT" "would remove $WT1_PHYS"
assert_contains "dry-run counts BOTH project and local plugin records (2)" "$OUT" "leaves 2 project/local-scope plugin record(s)"
assert_contains "dry-run proposes worktree under includeIf root2" "$OUT" "would remove $(physical_dir "$ROOT2/wt-chez")"
assert_contains "dry-run skips detached HEAD cleanly" "$OUT" "detached=1"
assert_contains "dry-run skips untracked-dirty worktree" "$OUT" "skip unsafe-work"
assert_contains "dry-run skips carried-file diff worktree" "$OUT" "skip carried-file"
assert_contains "dry-run skips reasonless lock as live-lock" "$OUT" "skip live-lock"
assert_eq "dry-run: 4 locked candidates (3 stale + 1 reasonless) make exactly 1 stale --batch call (vs 4 in old reap.sh)" \
  "1" "$(wc -l <"$STALE_LOG" | tr -d ' ')"
assert_contains "dry-run stale call uses --batch" "$(cat "$STALE_LOG")" "stale --batch"

cat >"$CFG/settings.json" <<'EOF'
{"pluginConfigs":{"source-control@melodic-software":{"options":{"worktree_reap_after_hours":100}}}}
EOF
OUT_SETTINGS="$(
  GIT_CONFIG_GLOBAL="$GCFG" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --dry-run --no-log --no-pr-proof 2>&1
)"
assert_contains "settings.json pluginConfigs sets reap age to 100h" "$OUT_SETTINGS" "reap age 100 h"
assert_contains "100h threshold skips 72h worktrees as under-age" "$OUT_SETTINGS" "would remove 0 worktrees"

OUT_ENV="$(
  GIT_CONFIG_GLOBAL="$GCFG" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS=24 \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --dry-run --no-log --no-pr-proof 2>&1
)"
assert_contains "CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS overrides settings.json" "$OUT_ENV" "reap age 24 h"

OUT_CLI="$(
  GIT_CONFIG_GLOBAL="$GCFG" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS=24 \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --dry-run --no-log --no-pr-proof --reap-after-hours 12 2>&1
)"
assert_contains "CLI --reap-after-hours overrides env and settings.json" "$OUT_CLI" "reap age 12 h"
rm -f "$CFG/settings.json"

: >"$STALE_LOG"
OUT_LIVE="$(
  GIT_CONFIG_GLOBAL="$GCFG" GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_SCRIPTS="$WRAP_SCRIPTS" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" \
    WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --no-log --no-pr-proof 2>&1
)"
assert_exit "live reap exits 0" 0 "$?"
assert_dir_absent "live reap removed wt-notrack-1" "$ROOT1/wt-notrack-1"
assert_dir_absent "live reap removed wt-notrack-2" "$ROOT1/wt-notrack-2"
assert_dir_absent "live reap removed wt-notrack-3" "$ROOT1/wt-notrack-3"
assert_dir_absent "live reap removed includeIf root2 wt-chez" "$ROOT2/wt-chez"
assert_dir_exists "live reap kept detached worktree" "$ROOT1/wt-detached"
assert_dir_exists "live reap kept untracked-dirty worktree" "$ROOT1/wt-dirty"
assert_dir_exists "live reap kept carried-file-diff worktree" "$ROOT1/wt-carried"
assert_dir_exists "live reap kept reasonless-locked worktree" "$ROOT1/wt-reasonless"
assert_contains "live reap reports 4 removed worktrees" "$OUT_LIVE" "removed 4 worktrees"
assert_contains "live reap reports 2 project/local plugin records" "$OUT_LIVE" "left 2 project/local-scope plugin record(s)"
assert_eq "live reap: 1 batch call + 3 survivor pre-unlock re-checks = 4 calls (not 2*4=8)" \
  "4" "$(wc -l <"$STALE_LOG" | tr -d ' ')"

IFS=$'\t' read -r REPO_DOWN _ORIGIN_DOWN <<<"$(mkrepo_with_origin)"
mkdir -p "$REPO_DOWN/docs/conventions"
printf '## Workspace environment\n- down: docker compose down\n' >"$REPO_DOWN/docs/conventions/workspace-environment.md"
git -C "$REPO_DOWN" add docs/conventions/workspace-environment.md
GIT_AUTHOR_DATE="@$OLD_TS +0000" GIT_COMMITTER_DATE="@$OLD_TS +0000" \
  git -C "$REPO_DOWN" commit -qm "add workspace down"
git -C "$REPO_DOWN" push -q origin main
ROOT_DOWN="$TEST_TMPDIR/root-down"
mkdir -p "$ROOT_DOWN"
git -C "$REPO_DOWN" worktree add -q --no-track -b feat/down-wt "$ROOT_DOWN/wt-down" origin/main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT_DOWN/wt-down/.git"

OUT_DOWN="$(
  CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --root "$ROOT_DOWN" --no-log --no-pr-proof 2>&1
)"
assert_exit "workspace-down guard exits 0" 0 "$?"
assert_contains "workspace-down skips the repo" "$OUT_DOWN" "workspace-down=1"
assert_dir_exists "workspace-down leaves worktree untouched" "$ROOT_DOWN/wt-down"

IFS=$'\t' read -r REPO_PROC _ORIGIN_PROC <<<"$(mkrepo_with_origin)"
ROOT_PROC="$TEST_TMPDIR/root-proc"
mkdir -p "$ROOT_PROC"
git -C "$REPO_PROC" worktree add -q --no-track -b feat/proc-wt "$ROOT_PROC/wt-held" origin/main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT_PROC/wt-held/.git"

PROC_HELD="$TEST_TMPDIR/proc-held"
mkdir -p "$PROC_HELD/4242"
ln -s "$(physical_dir "$ROOT_PROC/wt-held")" "$PROC_HELD/4242/cwd"
OUT_HELD="$(
  CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_HELD" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --root "$ROOT_PROC" --no-log --no-pr-proof 2>&1
)"
assert_contains "process-holds skips held worktree" "$OUT_HELD" "process-holds=1"
assert_dir_exists "held worktree stays on disk" "$ROOT_PROC/wt-held"

PROC_EMPTY="$TEST_TMPDIR/proc-empty"
mkdir -p "$PROC_EMPTY"
OUT_EMPTY="$(
  CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_EMPTY" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --root "$ROOT_PROC" --no-log --no-pr-proof 2>&1
)"
assert_contains "unreadable/empty /proc fails closed with process-scan skip" "$OUT_EMPTY" "process-scan=1"
assert_dir_exists "worktree survives unreadable /proc" "$ROOT_PROC/wt-held"

IFS=$'\t' read -r REPO_ROLL _ORIGIN_ROLL <<<"$(mkrepo_with_origin)"
ROOT_ROLL="$TEST_TMPDIR/root-roll"
mkdir -p "$ROOT_ROLL"
git -C "$REPO_ROLL" worktree add -q --no-track -b feat/roll "$ROOT_ROLL/wt-roll" origin/main >/dev/null 2>&1
touch -d "@$OLD_TS" "$ROOT_ROLL/wt-roll/.git"
ROLL_REASON="$(make_lock_reason "roll-stale")"
git -C "$REPO_ROLL" worktree lock --reason "$ROLL_REASON" "$ROOT_ROLL/wt-roll"

FAIL_RM_BIN="$TEST_TMPDIR/fail-rm-bin"
mkdir -p "$FAIL_RM_BIN"
REAL_GIT="$(command -v git)"
cat >"$FAIL_RM_BIN/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
*" worktree remove "*)
  echo "simulated remove failure" >&2
  exit 1
  ;;
*) exec "$REAL_GIT" "\$@" ;;
esac
EOF
chmod +x "$FAIL_RM_BIN/git"

OUT_ROLL="$(
  PATH="$FAIL_RM_BIN:$PATH" \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --root "$ROOT_ROLL" --no-log --no-pr-proof 2>&1
)"
assert_exit "failed worktree remove exits non-zero (1)" 1 "$?"
assert_contains "failed remove logs FAILED" "$OUT_ROLL" "FAILED to remove"
ROLL_STANZA="$(git -C "$REPO_ROLL" worktree list --porcelain | awk -v RS= '/wt-roll/')"
assert_contains "failed remove restores the original lock reason" "$ROLL_STANZA" "$ROLL_REASON"

LOCK_LOG="$TEST_TMPDIR/reap-lock.log"
OUT_FLOCK="$(
  (
    exec 8>"$LOCK_LOG.lock"
    flock -n 8
    CLAUDE_CONFIG_DIR="$CFG" WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
      bash "$REAP" --root "$ROOT_PROC" --log "$LOCK_LOG" --no-pr-proof 2>&1
  )
)"
assert_exit "flock contention exits 0 quietly" 0 "$?"
assert_contains "flock contention logs lock message" "$OUT_FLOCK" "another reap run holds"

IFS=$'\t' read -r REPO_RL1 _ORIGIN_RL1 <<<"$(mkrepo_with_origin)"
IFS=$'\t' read -r REPO_RL2 _ORIGIN_RL2 <<<"$(mkrepo_with_origin)"
ROOT_RL="$TEST_TMPDIR/root-rl"
mkdir -p "$ROOT_RL"
git -C "$REPO_RL1" worktree add -q --no-track -b feat/rl1 "$ROOT_RL/wt-rl1" origin/main >/dev/null 2>&1
commit_at "$ROOT_RL/wt-rl1" "rl1.txt" "rl1" "rl1" "$OLD_TS"
touch -d "@$OLD_TS" "$ROOT_RL/wt-rl1/.git"
git -C "$REPO_RL2" worktree add -q --no-track -b feat/rl2 "$ROOT_RL/wt-rl2" origin/main >/dev/null 2>&1
commit_at "$ROOT_RL/wt-rl2" "rl2.txt" "rl2" "rl2" "$OLD_TS"
touch -d "@$OLD_TS" "$ROOT_RL/wt-rl2/.git"

RL_GH_BIN="$TEST_TMPDIR/rl-gh-bin"
RL_GH_LOG="$TEST_TMPDIR/rl-gh.log"
mkdir -p "$RL_GH_BIN"
cat >"$RL_GH_BIN/gh" <<EOF
#!/usr/bin/env bash
echo call >>"$RL_GH_LOG"
echo "GraphQL: API rate limit exceeded" >&2
exit 1
EOF
chmod +x "$RL_GH_BIN/gh"
: >"$RL_GH_LOG"

OUT_RL="$(
  PATH="$RL_GH_BIN:$PATH" \
    CLAUDE_CONFIG_DIR="$CFG" HOSTNAME="$HOST_NAME" \
    WORKTREE_REAP_PROC_ROOT="$PROC_OK" WORKTREE_REAP_NOW="$NOW_TS" \
    bash "$REAP" --root "$ROOT_RL" --dry-run --no-log 2>&1
)"
assert_contains "rate limit triggers backoff message" "$OUT_RL" "rate limit; the merged-PR proof is off"
assert_contains "rate limit total counts 1 gh call" "$OUT_RL" "gh calls 1;"
assert_eq "rate limit stops second repo from calling gh" "1" "$(wc -l <"$RL_GH_LOG" | tr -d ' ')"

[[ $FAILED -eq 0 ]] || exit 1
