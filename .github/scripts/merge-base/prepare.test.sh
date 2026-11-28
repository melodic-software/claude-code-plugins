#!/usr/bin/env bash
# shellcheck disable=SC2310  # tg wraps one git call, so its status is that call's
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE="$SCRIPT_DIR/prepare.sh"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BOT='melodic-automation-lanes[bot]'
BOT_EMAIL='1+melodic-automation-lanes[bot]@users.noreply.github.com'
TRAILER='Lane-Activity: pr-unblock/resolve-conflicts'
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

NOOP_BUMP="$TMP/noop-bump.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$NOOP_BUMP"
BROKEN_BUMP="$TMP/broken-bump.sh"
printf '#!/usr/bin/env bash\nexit 2\n' >"$BROKEN_BUMP"

tg() { git -C "$R" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }
put() {
  mkdir -p "$(dirname "$R/$1")"
  printf '%b' "$2" >"$R/$1"
}
commit() {
  tg add -A
  tg commit -q --allow-empty -m "$1"
}

new_repo() {
  R="$(mktemp -d "$TMP/repo.XXXXXX")"
  git init -q -b main "$R"
  tg config core.autocrlf false
  put keep.txt 'keep\n'
  commit base
}
on_pr() { tg checkout -q -B pr "${1:-main}"; }
side() {
  tg checkout -q "$1"
  put "$2" "$3"
  commit "$1 edits $2"
}

run_prepare() {
  DIR="$(mktemp -d "$TMP/out.XXXXXX")"
  local head base
  head=$(tg rev-parse pr) base=$(tg rev-parse main)
  if tg rev-parse -q --verify MERGE_HEAD >/dev/null; then tg merge --abort; fi
  tg checkout -q pr
  invoke "$head" "$base" "$@"
}
invoke() {
  local head=$1 base=$2
  shift 2
  RC=0
  OUT=$(cd "$R" && env GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME="$BOT" GIT_COMMITTER_EMAIL="$BOT_EMAIL" "$@" \
    bash "$PREPARE" "$head" "$base" "${BUMP:-$NOOP_BUMP}" "$DIR" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}
val() { sed -n "s/^$1=//p" <<<"$OUT"; }
sha_of() {
  local s
  s=$(sha256sum <"$1")
  printf '%s' "${s%% *}"
}
merge_head() { tg rev-parse -q --verify MERGE_HEAD || true; }
stages() { tr '\0' '\n' <"$DIR/index-snapshot" | awk -F'\t' -v p="$1" '$2 == p { split($1, f, " "); s = s f[3] } END { print s }'; }

conflict() {
  new_repo
  put "$1" "$2"
  commit "add $1"
  on_pr
  side pr "$1" "$3"
  side main "$1" "$4"
}

echo '# text-conflict'
conflict a.txt 'one\n' 'pr\n' 'main\n'
CONFIG_BEFORE=$(sha_of "$R/.git/config")
run_prepare
check 'text-conflict: exit 0' 0 "$RC"
check 'text-conflict: merge-state' conflicted "$(val merge-state)"
check 'text-conflict: no escalation' '' "$(val escalation-reason)"
check 'text-conflict: MERGE_HEAD is the trusted base' "$(tg rev-parse main)" "$(merge_head)"
check 'text-conflict: snapshot holds stages 1 2 3' 123 "$(stages a.txt)"
check 'text-conflict: prints only the merge keys' 'merge-state escalation-reason conflict-tree' "$(cut -d= -f1 <<<"$OUT" | paste -sd ' ')"
check 'text-conflict: the config is untouched' "$CONFIG_BEFORE" "$(sha_of "$R/.git/config")"
check 'text-conflict: unmerged path recorded' a.txt "$(tr '\0' '\n' <"$DIR/unmerged-paths")"

echo '# conflict-tree'
conflict a.txt 'one\n' 'pr\n' 'main\n'
side main b.txt 'from main\n'
run_prepare
T0=$(val conflict-tree)
check 'conflict-tree: a full tree id' 1 "$([[ $T0 =~ ^[0-9a-f]{40}$ ]] && echo 1)"
check 'conflict-tree: the unmerged path holds the marker file' "$(git -C "$R" hash-object --no-filters a.txt)" "$(tg rev-parse "$T0:a.txt")"
T0_A=$(tg cat-file -p "$T0:a.txt")
if grep -q '^<<<<<<< ' <<<"$T0_A"; then ok 'conflict-tree: the marker file holds markers'; else not_ok 'conflict-tree: the marker file holds markers'; fi
check 'conflict-tree: a base-side path is the merge stage-0 blob' "$(tg rev-parse main:b.txt)" "$(tg rev-parse "$T0:b.txt")"
check 'conflict-tree: the head-side mode' "$(tg ls-tree pr a.txt | cut -d' ' -f1)" "$(tg ls-tree "$T0" a.txt | cut -d' ' -f1)"
check 'conflict-tree: the live index stays unmerged' 123 "$(tg ls-files -u -- a.txt | awk '{s = s $3} END {print s}')"
check 'conflict-tree: no scratch index is left behind' '' "$(find "$DIR" -name 't0-index*')"
run_prepare
check 'conflict-tree: a second run reaches the same tree' "$T0" "$(val conflict-tree)"
new_repo
put plugins/p/CHANGELOG.md 'x\n'
commit 'add changelog'
on_pr
side pr plugins/p/CHANGELOG.md 'pr\n'
side main plugins/p/CHANGELOG.md 'main\n'
BUMP="$TMP/sorting-bump.sh"
printf '#!/usr/bin/env bash\nprintf "b\\nB\\na\\n_x\\n" | sort >plugins/p/sorted.txt\ngit add plugins/p/sorted.txt\nexit 1\n' >"$BUMP"
run_prepare LC_ALL=C
T0_C=$(val conflict-tree)
run_prepare LC_ALL=en_US.UTF-8
check 'conflict-tree: the same tree under another locale' "$T0_C" "$(val conflict-tree)"
check 'conflict-tree: the bump sorted in the C locale' 'B _x a b ' "$(tg cat-file -p "$T0_C:plugins/p/sorted.txt" | tr '\n' ' ')"
unset BUMP
new_repo
on_pr
side pr p.txt 'pr\n'
side main m.txt 'main\n'
run_prepare
check 'conflict-tree: a clean merge is the merged tree' clean/"$(tg write-tree)" "$(val merge-state)/$(val conflict-tree)"
conflict .github/workflows/ci.yml 'on: push\n' 'on: pull_request\n' 'on: workflow_dispatch\n'
run_prepare
check 'conflict-tree: an escalation names none' escalate/ "$(val merge-state)/$(val conflict-tree)"

echo '# binary-conflict'
conflict a.bin 'base\0bin\n' 'pr\0bin\n' 'main\0bin\n'
run_prepare
check 'binary-conflict: escalates unresolved-conflict' escalate/unresolved-conflict "$(val merge-state)/$(val escalation-reason)"
check 'binary-conflict: MERGE_HEAD set' "$(tg rev-parse main)" "$(merge_head)"
check 'binary-conflict: snapshot holds stages 1 2 3' 123 "$(stages a.bin)"
conflict a.bin 'base\0\n' 'pr\0\n<<<<<<< x\n=======\n>>>>>>> y\n' 'main\0\n'
run_prepare
check 'binary-conflict: a head side holding marker-shaped lines still escalates' escalate/unresolved-conflict "$(val merge-state)/$(val escalation-reason)"
new_repo
put .gitattributes '*.txt conflict-marker-size=10\n'
put a.txt 'one\n'
commit 'base with long markers'
on_pr
side pr a.txt 'pr\n'
side main a.txt 'main\n'
run_prepare
check 'binary-conflict: a text conflict with 10-character markers is not taken for binary' conflicted/ "$(val merge-state)/$(val escalation-reason)"
if grep -q '^<<<<<<<<<< ' "$R/a.txt"; then ok 'binary-conflict: the base attributes set the marker size'; else not_ok 'binary-conflict: the base attributes set the marker size'; fi

echo '# modify-delete'
new_repo
put d.txt 'one\n'
commit 'add d.txt'
on_pr
side pr d.txt 'pr\n'
tg checkout -q main
tg rm -q d.txt
commit 'main deletes d.txt'
run_prepare
check 'modify-delete: escalates unresolved-conflict' escalate/unresolved-conflict "$(val merge-state)/$(val escalation-reason)"
check 'modify-delete: snapshot holds stages 1 2' 12 "$(stages d.txt)"
new_repo
put d.md 'one\n'
commit 'add d.md'
on_pr
side pr d.md '<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n'
tg checkout -q main
tg rm -q d.md
commit 'main deletes d.md'
run_prepare
check 'modify-delete: a kept side holding marker text still escalates' escalate/unresolved-conflict "$(val merge-state)/$(val escalation-reason)"

echo '# symlink-conflict'
symlink_base() {
  new_repo
  ln -s keep.txt "$R/l.txt"
  commit 'add l.txt as a symlink'
  on_pr
  local branch op
  for branch in pr main; do
    if [[ $branch == pr ]]; then op=$1; else op=$2; fi
    tg checkout -q "$branch"
    rm -f "$R/l.txt"
    if [[ $op == link:* ]]; then ln -s "${op#link:}" "$R/l.txt"; else put l.txt "${op#file:}"; fi
    commit "$branch edits l.txt"
  done
}
symlink_base 'file:pr\n' 'file:main\n'
run_prepare
check 'symlink-conflict: a symlink ancestor under two text sides is a text conflict' conflicted/ "$(val merge-state)/$(val escalation-reason)"
check 'symlink-conflict: snapshot holds stages 1 2 3' 123 "$(stages l.txt)"
symlink_base 'link:a' 'file:main\n'
run_prepare
check 'symlink-conflict: a symlink side escalates' escalate/unresolved-conflict "$(val merge-state)/$(val escalation-reason)"

echo '# workflow-conflict'
conflict .github/workflows/ci.yml 'on: push\n' 'on: pull_request\n' 'on: workflow_dispatch\n'
run_prepare
check 'workflow-conflict: merge-state' escalate "$(val merge-state)"
check 'workflow-conflict: reason' protected-path-conflict "$(val escalation-reason)"
check 'workflow-conflict: a conflicting tree is not hidden by the escalation' "$(tg rev-parse main)" "$(merge_head)"

conflict a.txt 'one\n' 'pr\n' 'main\n'
side main .github/workflows/ci.yml 'on: push\n'
run_prepare
check 'workflow-conflict: base-side workflow edit stays conflicted, not escalated' conflicted "$(val merge-state)"

echo '# protected-conflict'
for p in .claude/settings.json vendor/Settings.local.json .gitmodules vendor/.gitmodules plugins/p/.gitmodules; do
  conflict "$p" 'base\n' 'pr\n' 'main\n'
  run_prepare
  check "protected-conflict: $p escalates" escalate/protected-path-conflict "$(val merge-state)/$(val escalation-reason)"
done
for p in CLAUDE.md CLAUDE.local.md .mcp.json .claude.json .claude/rules/r.md .ripgreprc .husky/pre-commit .github/scripts/x.mjs settings.md plugins/p/Settings.local.json; do
  conflict "$p" 'base\n' 'pr\n' 'main\n'
  run_prepare
  check "protected-conflict: $p goes to the model" conflicted/ "$(val merge-state)/$(val escalation-reason)"
done
conflict .claude/settings.json 'base\n' 'pr\n' 'main\n'
side pr .gitattributes '.claude/settings.json merge=union\n.github/workflows/* merge=union\n'
run_prepare
check 'protected-conflict: a head merge=union attribute still escalates' escalate/protected-path-conflict "$(val merge-state)/$(val escalation-reason)"

echo '# clean-after-bump'
conflict plugins/p/CHANGELOG.md '# Changelog\n' '# Changelog\n\n## [1.1.0]\n' '# Changelog\n\n## [1.0.1]\n'
BUMP="$TMP/resolving-bump.sh"
cat >"$BUMP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git rev-parse -q --verify MERGE_HEAD >bump-saw-merge-head
printf '%s' "${GIT_ATTR_SOURCE:-}" >bump-attr-source
printf '# Changelog\n\n## [1.1.1]\n' >plugins/p/CHANGELOG.md
git add plugins/p/CHANGELOG.md
EOF
run_prepare
check 'clean-after-bump: merge-state' clean "$(val merge-state)"
check 'clean-after-bump: the script ran mid-merge' "$(tg rev-parse main)" "$(cat "$R/bump-saw-merge-head")"
check 'clean-after-bump: the script reads attributes from the trusted base' "$(tg rev-parse main)" "$(cat "$R/bump-attr-source")"
check 'clean-after-bump: snapshot taken after the script (stage 0 only)' 0 "$(stages plugins/p/CHANGELOG.md)"
check 'clean-after-bump: MERGE_HEAD kept for the commit' "$(tg rev-parse main)" "$(merge_head)"
BUMP="$TMP/manual-bump.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$BUMP"
conflict plugins/p/CHANGELOG.md 'x\n' 'pr\n' 'main\n'
run_prepare
check 'clean-after-bump: a script that leaves the pair is not a failure' 0/conflicted "$RC/$(val merge-state)"
BUMP=$BROKEN_BUMP
conflict a.txt 'one\n' 'pr\n' 'main\n'
run_prepare
check 'clean-after-bump: a script git failure fails prepare' 1 "$RC"
BUMP="$TMP/aborting-bump.sh"
printf '#!/usr/bin/env bash\ngit merge --abort\n' >"$BUMP"
conflict a.txt 'one\n' 'pr\n' 'main\n'
run_prepare
check 'clean-after-bump: a script that ends the merge fails prepare' 1 "$RC"
unset BUMP

echo '# no-identity'
for v in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
  conflict a.txt 'one\n' 'pr\n' 'main\n'
  run_prepare "$v="
  check "no-identity: empty $v fails" 1 "$RC"
  check "no-identity: empty $v starts no merge" '' "$(merge_head)"
  if [[ $ERR == *"$v"* ]]; then ok "no-identity: names $v"; else not_ok "no-identity: stderr does not name $v: $ERR"; fi
done

echo '# preconditions'
conflict a.txt 'one\n' 'pr\n' 'main\n'
tg checkout -q pr
DIR="$(mktemp -d "$TMP/out.XXXXXX")"
RC=0
(cd "$R" && env GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" GIT_COMMITTER_NAME="$BOT" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
  bash "$PREPARE" "$(tg rev-parse pr)" 0123456789012345678901234567890123456789 "$NOOP_BUMP" "$DIR" 2>/dev/null) || RC=$?
check 'preconditions: a trusted base that is not a commit fails' 1 "$RC"
RC=0
(cd "$R" && env GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" GIT_COMMITTER_NAME="$BOT" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
  bash "$PREPARE" "$(tg rev-parse main)" "$(tg rev-parse main)" "$NOOP_BUMP" "$DIR" 2>/dev/null) || RC=$?
check 'preconditions: HEAD other than the gated head fails' 1 "$RC"
check 'preconditions: no merge started' '' "$(merge_head)"
L41=$(printf 'a%.0s' {1..41}) L45=$(printf 'a%.0s' {1..45}) L63=$(printf 'a%.0s' {1..63})
for n in "$L41" "$L45" "$L63"; do tg branch -f "$n" main; done
for bad in pr HEAD --output=x "$(tg rev-parse --short main)" "$L41" "$L45" "$L63"; do
  invoke "$(tg rev-parse pr)" "$bad"
  check "preconditions: a trusted base given as '$bad' is refused" 1 "$RC"
  invoke "$bad" "$(tg rev-parse main)"
  check "preconditions: a gated head given as '$bad' is refused" 1 "$RC"
done
check 'preconditions: no merge started for a refused input' '' "$(merge_head)"
mkdir -p "$TMP/oldgit"
# shellcheck disable=SC2016  # the stub's own $1 and $@
printf '#!/usr/bin/env bash\nif [[ $1 == version ]]; then echo "git version 2.40.1"; exit 0; fi\nexec %q "$@"\n' "$(command -v git)" >"$TMP/oldgit/git"
chmod +x "$TMP/oldgit/git"
invoke "$(tg rev-parse pr)" "$(tg rev-parse main)" PATH="$TMP/oldgit:$PATH"
check 'preconditions: git older than 2.41 fails' 1 "$RC"
if [[ $ERR == *2.41* ]]; then ok 'preconditions: the error names the version needed'; else not_ok "preconditions: the error names the version needed: $ERR"; fi
conflict a.txt 'one\n' 'pr\n' 'main\n'
tg checkout -q pr
printf '#!/usr/bin/env bash\ntouch "%s/fsmonitor-ran"\n' "$TMP" >"$TMP/fsmonitor.sh"
chmod +x "$TMP/fsmonitor.sh"
tg config core.fsmonitor "$TMP/fsmonitor.sh"
invoke "$(git -C "$R" -c core.fsmonitor= rev-parse pr)" "$(git -C "$R" -c core.fsmonitor= rev-parse main)"
check 'preconditions: merge ran with the fsmonitor configured' conflicted "$(val merge-state)"
if [[ -e $TMP/fsmonitor-ran ]]; then not_ok 'preconditions: a configured fsmonitor command does not run'; else ok 'preconditions: a configured fsmonitor command does not run'; fi

echo '# repeat-cap'
bot_commit() {
  tg checkout -q pr
  put "bot-$RANDOM.txt" 'x\n'
  tg add -A
  GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" tg commit -q -F - <<<"$1"
}
lane_msg=$'Merge main into pr\n\n'"$TRAILER"
conflict a.txt 'one\n' 'pr\n' 'main\n'
bot_commit "$lane_msg"
bot_commit "$lane_msg"
tg checkout -q -b side pr~1
put human.txt 'h\n'
commit 'human on a side branch'
tg checkout -q pr
GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" tg merge -q --no-ff side -m "$lane_msg"
run_prepare
check 'repeat-cap: three lane commits in a row stop at the cap' escalate/repeat-cap "$(val merge-state)/$(val escalation-reason)"
check 'repeat-cap: stops before merging' '' "$(merge_head)"
run_prepare LOOP_NO_PROGRESS=4
check 'repeat-cap: under a higher loop.no-progress the merge proceeds' conflicted "$(val merge-state)"
if tg rev-parse -q --verify MERGE_HEAD >/dev/null; then tg merge --abort; fi
put human2.txt 'h\n'
commit 'human pushes on top'
run_prepare
check 'repeat-cap: a human commit on top resets the count' conflicted "$(val merge-state)"

conflict a.txt 'one\n' 'pr\n' 'main\n'
bot_commit "$lane_msg"
bot_commit 'a lane commit from another activity'
bot_commit "$lane_msg"
run_prepare
check 'repeat-cap: lane commits without the trailer are not counted' conflicted "$(val merge-state)"
run_prepare LOOP_NO_PROGRESS=2
check 'repeat-cap: ...but are walked past to reach the earlier ones' escalate/repeat-cap "$(val merge-state)/$(val escalation-reason)"
run_prepare LOOP_NO_PROGRESS=0
check 'repeat-cap: a non-positive cap fails' 1 "$RC"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all prepare.sh tests passed'
