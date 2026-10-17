#!/usr/bin/env bash
# Tests for post.sh on throwaway repositories: prepare.sh starts the merge of
# `main` (the trusted base) into `pr` (the gated head), the test then does what
# a model or claude-code-action would, and post.sh checks the result.
# shellcheck disable=SC2310  # tg wraps one git call, so its status is that call's
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE="$SCRIPT_DIR/prepare.sh"
POST="$SCRIPT_DIR/post.sh"

# Keep the developer's own git configuration, and any inherited repository
# location, out of every fixture.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BOT='melodic-automation-lanes[bot]'
BOT_EMAIL='1+melodic-automation-lanes[bot]@users.noreply.github.com'
NOOP_BUMP="$TMP/noop-bump.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$NOOP_BUMP"
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

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
side() {
  tg checkout -q "$1"
  put "$2" "$3"
  commit "$1 edits $2"
}
# conflict <path> <base> <pr> <main>: a fresh repo where both sides edit path.
conflict() {
  new_repo
  put "$1" "$2"
  commit "add $1"
  tg checkout -q -b pr
  side pr "$1" "$3"
  side main "$1" "$4"
}

# prepare: runs prepare.sh on `pr`; sets DIR and the three hashes post.sh reads.
prepare() {
  DIR="$(mktemp -d "$TMP/out.XXXXXX")"
  local out
  tg checkout -q pr
  out=$(cd "$R" && env GIT_AUTHOR_NAME="$BOT" GIT_AUTHOR_EMAIL="$BOT_EMAIL" \
    GIT_COMMITTER_NAME="$BOT" GIT_COMMITTER_EMAIL="$BOT_EMAIL" \
    bash "$PREPARE" "$(tg rev-parse pr)" "$(tg rev-parse main)" "$NOOP_BUMP" "$DIR" 2>/dev/null)
  CONFIG_SHA256=$(sed -n 's/^config-sha256=//p' <<<"$out")
  ATTRIBUTES_SHA256=$(sed -n 's/^attributes-sha256=//p' <<<"$out")
  SNAPSHOT_SHA256=$(sed -n 's/^snapshot-sha256=//p' <<<"$out")
  STATE=$(sed -n 's/^merge-state=//p' <<<"$out")
  GATED_HEAD=$(tg rev-parse pr) TRUSTED_BASE=$(tg rev-parse main)
}
# run_post [env assignments...]: sets OUT, ERR and RC.
run_post() {
  RC=0
  OUT=$(cd "$R" && env CONFIG_SHA256="$CONFIG_SHA256" ATTRIBUTES_SHA256="$ATTRIBUTES_SHA256" \
    SNAPSHOT_SHA256="$SNAPSHOT_SHA256" GATED_HEAD="$GATED_HEAD" TRUSTED_BASE="$TRUSTED_BASE" \
    "$@" bash "$POST" "$DIR" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}
reason() { sed -n 's/^escalation-reason=//p' <<<"$OUT"; }
tree() { sed -n 's/^tree=//p' <<<"$OUT"; }
# entry <path>: "<mode> <sha> <stage>" for each index entry at path.
entry() { tg ls-files -s -- "$1" | cut -f1 | tr '\n' ' ' | sed 's/ $//'; }
blob() { git -C "$R" hash-object --stdin; }

echo '# text-conflict'
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
check 'text-conflict: prepared conflicted' conflicted "$STATE"
run_post
check 'text-conflict: left unmerged is unresolved' 0/unresolved-conflict "$RC/$(reason)"
check 'text-conflict: an escalation prints no tree' '' "$(tree)"
put a.txt 'pr and main\n'
tg add a.txt
put a.txt 'unstaged edit\n'
run_post
check 'text-conflict: resolved and staged passes' 0/ "$RC/$(reason)"
T=$(tree)
check 'text-conflict: the tree holds the staged resolution' "$(printf 'pr and main\n' | blob)" "$(tg rev-parse -q --verify "${T:-missing}:a.txt" 2>/dev/null || true)"
check 'text-conflict: the tree keeps the untouched files' "$(tg rev-parse pr:keep.txt)" "$(tg rev-parse -q --verify "${T:-missing}:keep.txt" 2>/dev/null || true)"

echo '# merge-guard'
# A model that aborts the merge, or commits it, leaves a state post.sh refuses.
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
tg merge --abort
run_post
check 'merge-guard: an aborted merge fails' 1 "$RC"
check 'merge-guard: and prints nothing' '' "$OUT"
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
put a.txt 'resolved\n'
tg add a.txt
tg commit -q -m 'model commits'
run_post
check 'merge-guard: a moved HEAD fails' 1 "$RC"
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
put a.txt 'resolved\n'
tg add a.txt
tg update-ref HEAD pr~1
run_post
check 'merge-guard: HEAD moved under a live merge fails' 1 "$RC"
tg update-ref HEAD "$GATED_HEAD"
run_post TRUSTED_BASE="$(tg rev-parse main~1)"
check 'merge-guard: MERGE_HEAD other than the trusted base fails' 1 "$RC"
# Hex of a length between the two object-id sizes is a ref name, never an id.
L45=$(printf 'a%.0s' {1..45})
tg branch -f "$L45" main
for bad in main HEAD "$(tg rev-parse --short main)" "$L45"; do
  run_post TRUSTED_BASE="$bad"
  check "merge-guard: a trusted base given as '$bad' is refused" 1 "$RC"
  run_post GATED_HEAD="$bad"
  check "merge-guard: a gated head given as '$bad' is refused" 1 "$RC"
done
run_post
check 'merge-guard: the untouched state still passes' 0/ "$RC/$(reason)"

echo '# binary-conflict'
conflict a.bin 'base\0\n' 'pr\0\n' 'main\0\n'
prepare
run_post
check 'binary-conflict: left unmerged is unresolved' unresolved-conflict "$(reason)"
tg checkout -q --theirs a.bin
tg add a.bin
run_post
check 'binary-conflict: a side chosen and staged passes' 0/ "$RC/$(reason)"

echo '# modify-delete'
new_repo
put d.txt 'one\n'
commit 'add d.txt'
tg checkout -q -b pr
side pr d.txt 'pr\n'
tg checkout -q main
tg rm -q d.txt
commit 'main deletes d.txt'
prepare
run_post
check 'modify-delete: left unmerged is unresolved' unresolved-conflict "$(reason)"
tg rm -q d.txt
run_post
check 'modify-delete: the deletion staged passes' 0/ "$RC/$(reason)"

echo '# unresolved-marker'
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
tg add a.txt
run_post
check 'unresolved-marker: markers staged are unresolved' unresolved-conflict "$(reason)"
put a.txt '<<<<<<< HEAD\r\npr\r\n=======\r\nmain\r\n>>>>>>> main\r\n'
tg add a.txt
run_post
check 'unresolved-marker: CRLF markers are unresolved' unresolved-conflict "$(reason)"
put a.txt '<<<<<<<\npr\n||||||| base\none\n=======\nmain\n>>>>>>>\n'
tg add a.txt
run_post
check 'unresolved-marker: bare diff3 markers are unresolved' unresolved-conflict "$(reason)"
put a.txt 'Title\n=======\n\n<<<<<<<< not a marker\n>>>>>>>> not either\n'
tg add a.txt
run_post
check 'unresolved-marker: a setext heading and 8-char runs are not markers' 0/ "$RC/$(reason)"
put a.txt '>>>>>>> end\n=======\n<<<<<<< start\n'
tg add a.txt
run_post
check 'unresolved-marker: markers out of order are not a conflict' 0/ "$RC/$(reason)"
put a.txt '<<<<<<< a\nno separator\n>>>>>>> b\n'
tg add a.txt
run_post
check 'unresolved-marker: no ======= line is not a conflict' 0/ "$RC/$(reason)"
put a.txt '<<<<<<<< eight\n=========\n>>>>>>>>>> ten\n'
tg add a.txt
run_post
check 'unresolved-marker: longer markers of any size are markers' unresolved-conflict "$(reason)"
put a.txt '<<<<<< six\n======\n>>>>>> six\n'
tg add a.txt
run_post
check 'unresolved-marker: six-character runs are not markers' 0/ "$RC/$(reason)"
# conflict-marker-size=10 in the base attributes: git writes 10-character
# markers, and staging them unchanged is still caught.
new_repo
put .gitattributes '*.txt conflict-marker-size=10\n'
put a.txt 'one\n'
commit 'base with long markers'
tg checkout -q -b pr
side pr a.txt 'pr\n'
side main a.txt 'main\n'
prepare
tg add a.txt
run_post
check 'unresolved-marker: conflict-marker-size=10 markers are caught' unresolved-conflict "$(reason)"
# Markers in a path that never conflicted (a doc quoting them) are not checked.
conflict a.txt 'one\n' 'pr\n' 'main\n'
side main doc.md '<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> b\n'
prepare
put a.txt 'resolved\n'
tg add a.txt
run_post
check 'unresolved-marker: a path that never conflicted is not checked' 0/ "$RC/$(reason)"
# The marked file moved to a new path clears the unmerged entries but not the
# markers: a path staged since the snapshot is checked wherever it lives.
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
cp "$R/a.txt" "$R/b.txt"
tg rm -q --cached a.txt
rm "$R/a.txt"
tg add b.txt
run_post
check 'unresolved-marker: markers moved to a new path are unresolved' unresolved-conflict "$(reason)"
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
cp "$R/a.txt" "$R/keep.txt"
put a.txt 'resolved\n'
tg add a.txt keep.txt
run_post
check 'unresolved-marker: markers copied over another path are unresolved' unresolved-conflict "$(reason)"
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
put a.txt 'resolved\n'
put b.txt 'new\n'
tg add a.txt b.txt
run_post
check 'unresolved-marker: a new path without markers passes' 0/ "$RC/$(reason)"

echo '# workflow-staged'
WF=.github/workflows/ci.yml
for change in edit add remove mode; do
  conflict a.txt 'one\n' 'pr\n' 'main\n'
  side pr "$WF" 'on: push\n'
  prepare
  put a.txt 'resolved\n'
  tg add a.txt
  case $change in
    edit)
      put "$WF" 'on: pull_request_target\n'
      tg add "$WF"
      ;;
    add)
      put .github/workflows/new.yml 'on: push\n'
      tg add .github/workflows/new.yml
      ;;
    remove) tg rm -q --cached "$WF" ;;
    mode) tg update-index --chmod=+x "$WF" ;;
    *) exit 2 ;;
  esac
  run_post
  check "workflow-staged: a model $change of a workflow escalates" 0/workflow-staged "$RC/$(reason)"
done
# A workflow change merged in from the base differs from the PR head, which
# the lane token cannot push: it escalates on a conflicted and a clean merge.
conflict a.txt 'one\n' 'pr\n' 'main\n'
side main "$WF" 'on: push\n'
prepare
put a.txt 'resolved\n'
tg add a.txt
run_post
check 'workflow-staged: a base-side workflow change in a conflicted merge escalates' 0/workflow-staged "$RC/$(reason)"
check 'workflow-staged: and prints no tree' '' "$(tree)"
new_repo
put "$WF" 'on: push\n'
commit 'add workflow'
tg checkout -q -b pr
side pr a.txt 'pr\n'
side main "$WF" 'on: pull_request\n'
prepare
check 'workflow-staged: prepared clean' clean "$STATE"
run_post
check 'workflow-staged: a base-side workflow change in a clean merge escalates' 0/workflow-staged "$RC/$(reason)"
# A workflow the merge leaves as the PR head has it passes, unstaged edits aside.
conflict a.txt 'one\n' 'pr\n' 'main\n'
side pr "$WF" 'on: push\n'
prepare
put a.txt 'resolved\n'
tg add a.txt
put "$WF" 'unstaged worktree edit\n'
run_post
check 'workflow-staged: a head-side workflow and an unstaged edit pass' 0/ "$RC/$(reason)"
# Paths git would quote (non-ASCII here) are compared like any other.
for name in ci.yml é.yml; do
  for change in none remove mode; do
    new_repo
    put ".github/workflows/$name" 'on: push\n'
    put a.txt 'one\n'
    commit "add $name"
    tg checkout -q -b pr
    side pr a.txt 'pr\n'
    side main a.txt 'main\n'
    case $change in
      none) want=0/ ;;
      remove)
        tg rm -q ".github/workflows/$name"
        want=0/workflow-staged
        ;;
      mode)
        chmod +x "$R/.github/workflows/$name"
        tg update-index --chmod=+x ".github/workflows/$name"
        want=0/workflow-staged
        ;;
      *) exit 2 ;;
    esac
    commit "main $change $name"
    prepare
    put a.txt 'resolved\n'
    tg add a.txt
    run_post
    check "workflow-staged: base-side $change of $name" "$want" "$RC/$(reason)"
  done
done

echo '# sensitive-reset'
# The base edits CLAUDE.md, the PR edits .claude/settings.json, and a.txt
# conflicts. claude-code-action then resets those index entries to the PR head
# (git reset -- <SENSITIVE_PATHS>), and the model stages a new .mcp.json.
new_repo
put a.txt 'one\n'
put CLAUDE.md 'base rules\n'
put .claude/settings.json '{}\n'
commit 'sensitive files'
tg checkout -q -b pr
put a.txt 'pr\n'
put .claude/settings.json '{"pr": true}\n'
ODD=$'.claude/odd "name"\\\twith\ttabs\nand a newline.md'
mkdir -p "$R/.claude"
printf 'odd\n' >"$R/$ODD"
commit 'pr side'
side main a.txt 'main\n'
put CLAUDE.md 'main rules\n'
commit 'main edits CLAUDE.md'
prepare
check 'sensitive-reset: prepared conflicted, not escalated' conflicted "$STATE"
tg reset -q -- CLAUDE.md .claude >/dev/null 2>&1
put .mcp.json '{"servers": {}}\n'
tg add .mcp.json
put a.txt 'resolved\n'
tg add a.txt
check 'sensitive-reset: the reset dropped the base CLAUDE.md' "$(tg rev-parse pr:CLAUDE.md)" "$(tg ls-files -s -- CLAUDE.md | cut -d' ' -f2)"
run_post
check 'sensitive-reset: passes' 0/ "$RC/$(reason)"
check 'sensitive-reset: CLAUDE.md is the base edit again' "100644 $(printf 'main rules\n' | blob) 0" "$(entry CLAUDE.md)"
check 'sensitive-reset: .claude keeps the PR edit' "100644 $(printf '{"pr": true}\n' | blob) 0" "$(entry .claude/settings.json)"
check 'sensitive-reset: a model-added sensitive path is dropped' '' "$(entry .mcp.json)"
check 'sensitive-reset: a path with quotes, tabs and a newline is re-applied' "100644 $(printf 'odd\n' | blob) 0" "$(entry "$ODD")"
check 'sensitive-reset: no other .claude entry appears' 2 "$(tg ls-files -z -- .claude | tr -cd '\0' | wc -c | tr -d ' ')"
check 'sensitive-reset: other staged paths are kept' "100644 $(printf 'resolved\n' | blob) 0" "$(entry a.txt)"

echo '# git-config-rewrite'
conflict a.txt 'one\n' 'pr\n' 'main\n'
tg config remote.origin.url https://github.com/o/r
cp "$R/.git/config" "$TMP/config.before"
prepare
put a.txt 'resolved\n'
tg add a.txt
tg config remote.origin.url 'https://x-access-token:ghs_example@github.com/o/r'
tg config core.fsmonitor "$TMP/fsmonitor.sh"
printf '#!/usr/bin/env bash\ntouch "%s/fsmonitor-ran"\n' "$TMP" >"$TMP/fsmonitor.sh"
chmod +x "$TMP/fsmonitor.sh"
mkdir -p "$R/.git/info"
printf '* diff=evil\n' >"$R/.git/info/attributes"
run_post
check 'git-config-rewrite: passes' 0/ "$RC/$(reason)"
if cmp -s "$TMP/config.before" "$R/.git/config"; then ok 'git-config-rewrite: .git/config restored byte for byte'; else not_ok 'git-config-rewrite: .git/config not restored'; fi
if [[ -e $R/.git/info/attributes ]]; then not_ok 'git-config-rewrite: an added attributes file is removed'; else ok 'git-config-rewrite: an added attributes file is removed'; fi
if [[ -e $TMP/fsmonitor-ran ]]; then not_ok 'git-config-rewrite: the rewritten fsmonitor never runs'; else ok 'git-config-rewrite: the rewritten fsmonitor never runs'; fi
# An attributes file that existed before the merge is put back as it was.
conflict a.txt 'one\n' 'pr\n' 'main\n'
mkdir -p "$R/.git/info"
printf '*.bin binary\n' >"$R/.git/info/attributes"
prepare
put a.txt 'resolved\n'
tg add a.txt
printf '* filter=evil\n' >"$R/.git/info/attributes"
run_post
check 'git-config-rewrite: an existing attributes file is restored' "$(printf '*.bin binary\n')" "$(cat "$R/.git/info/attributes")"

echo '# tampered-copy'
for target in config index-snapshot attributes; do
  conflict a.txt 'one\n' 'pr\n' 'main\n'
  mkdir -p "$R/.git/info"
  printf '*.bin binary\n' >"$R/.git/info/attributes"
  prepare
  put a.txt 'resolved\n'
  tg add a.txt
  tg config remote.origin.url 'https://x-access-token:ghs_example@github.com/o/r'
  cp "$R/.git/config" "$TMP/config.rewritten"
  printf 'x' >>"$DIR/$target"
  run_post
  check "tampered-copy: a changed $target copy fails" 1 "$RC"
  check "tampered-copy: no escalation reason printed for $target" '' "$OUT"
  check "tampered-copy: the error names the $target copy" "post.sh: $DIR/$target does not match its recorded SHA-256" "$ERR"
  if cmp -s "$TMP/config.rewritten" "$R/.git/config"; then ok "tampered-copy: nothing restored from a tampered $target"; else not_ok "tampered-copy: .git/config was written despite a tampered $target"; fi
done
conflict a.txt 'one\n' 'pr\n' 'main\n'
prepare
for v in CONFIG_SHA256 ATTRIBUTES_SHA256 SNAPSHOT_SHA256 GATED_HEAD TRUSTED_BASE; do
  run_post "$v="
  check "tampered-copy: an empty $v fails" 1 "$RC"
done

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all post.sh tests passed'
