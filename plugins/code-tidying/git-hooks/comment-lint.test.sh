#!/usr/bin/env bash
# test-scope: plugins/code-tidying/git-hooks/entries.json plugins/code-tidying/lib/git-hooks/check-lib.sh plugins/code-tidying/lib/git-hooks/install.mjs plugins/code-tidying/scripts/comment-settings.sh plugins/code-tidying/scripts/comment-census.py plugins/code-tidying/scripts/code-extensions.txt plugins/code-tidying/scripts/generated-marker.ere plugins/code-tidying/lib/parse-concern-value.sh plugins/code-tidying/lib/yaml-subset.awk plugins/code-tidying/lib/resolve-convention-home.sh plugins/code-tidying/.claude-plugin/plugin.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/comment-lint.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
FIXTURES="$HERE/fixtures"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

MSG='comment outside the %s posture: delete it, move the reason into the code or the commit message, or link the outside constraint; /code-tidying:remove-comments fixes it'
finding() {
  printf "%s:%s: $MSG" "$1" "$2" "$3"
}

PYDIR="$WORK/py"
mkdir -p "$PYDIR"
REAL_PY=""
while IFS= read -r candidate; do
  if "$candidate" -c 'import pygments' >/dev/null 2>&1; then
    REAL_PY="$candidate"
    break
  fi
done < <(type -ap python3)

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  mkdir -p "$REPO/docs/conventions"
  printf '%s\n' "$@" >"$REPO/docs/conventions/code-tidying.yaml"
  printf 'x=1\n' >"$REPO/seed.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

check() {
  local repo="$1" err rc
  shift
  err="$(cd "$repo" && bash "$CHECK" "$@" 2>&1 >/dev/null </dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

stage_fixture() {
  local fixture="$1" target="$2"
  mkdir -p "$(dirname "$REPO/$target")"
  cp "$FIXTURES/$fixture" "$REPO/$target"
  git -C "$REPO" add -- "$target"
}

planted() {
  local target="$1" posture="$2" line first=1
  while IFS=: read -r line _; do
    ((first)) || printf '\n'
    first=0
    finding "$target" "$line" "$posture"
  done < <(grep -n PLANTED "$REPO/$target")
}

expect "--help prints the usage and exits 0" "0|yes" \
  "$(out="$(bash "$CHECK" --help 2>&1)"; printf '%s|' "$?"; [[ "$out" == *"comment_lint"* ]] && echo yes)"

new_repo 'comment_lint: block'
printf 'x=1\n# a planted note\n' >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
NOPY="$WORK/nopy"
mkdir -p "$NOPY"
for t in git bash sed awk cat mktemp rm dirname grep tr head mkdir pwd cp; do
  p="$(command -v "$t")" && ln -s "$p" "$NOPY/$t"
done
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPY" bash "$CHECK" 2>&1)"
expect "missing python3: an agent fails with the install command and the skip key" "1|yes|yes" \
  "$?|$(grep -q '^FAIL: python3 missing. Install: ' <<<"$out" && echo yes)|$(grep -qF 'git -c checks.skipmissing=python3 commit' <<<"$out" && echo yes)"
out="$(cd "$REPO" && PATH="$NOPY" bash "$CHECK" 2>&1)"
expect "missing python3: a person gets a notice and exit 0" "0|yes" "$?|$(grep -q '^NOTICE: python3 missing' <<<"$out" && echo yes)"

if [[ -z "$REAL_PY" ]]; then
  echo "SKIP: no python3 on PATH imports pygments -- the judging cases are skipped"
  echo "comment-lint: $PASS passed, $FAIL failed"
  ((FAIL == 0))
  exit
fi

NOPYG="$WORK/nopygments"
mkdir -p "$NOPYG"
printf '#!/bin/sh\nexec "%s" -S "$@"\n' "$REAL_PY" >"$NOPYG/python3"
chmod +x "$NOPYG/python3"
expect "control: the stand-in python3 cannot import pygments" 1 \
  "$("$NOPYG/python3" -c 'import pygments' >/dev/null 2>&1; echo $?)"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPYG:$PATH" bash "$CHECK" 2>&1)"
expect "python3 without pygments: an agent fails naming pygments" "1|yes|yes" \
  "$?|$(grep -q '^FAIL: pygments missing. Install: ' <<<"$out" && echo yes)|$(grep -qF 'git -c checks.skipmissing=pygments commit' <<<"$out" && echo yes)"
git -C "$REPO" config checks.skipmissing pygments
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPYG:$PATH" bash "$CHECK" 2>&1)"
expect "python3 without pygments, named in checks.skipmissing: skipped, exit 0" "0|SKIPPED: pygments (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && PATH="$NOPYG:$PATH" bash "$CHECK" 2>&1)"
expect "python3 without pygments: a person gets a notice and exit 0" "0|yes" "$?|$(grep -q '^NOTICE: pygments missing' <<<"$out" && echo yes)"

UNPARSED="$WORK/unparsed"
mkdir -p "$UNPARSED"
printf '#!/bin/sh\nprintf "%%s\\n" "%s"\necho "comment-lint: bad.sh: not judged, the comment reader failed: boom" >&2\nexit 5\n' \
  "$(finding ok.sh 2 necessary)" >"$UNPARSED/python3"
chmod +x "$UNPARSED/python3"
for level in report block; do
  new_repo "comment_lint: $level"
  printf 'x=1\n# note\n' >"$REPO/ok.sh"
  printf 'y=1\n' >"$REPO/bad.sh"
  git -C "$REPO" add ok.sh bad.sh
  out="$(cd "$REPO" && PATH="$UNPARSED:$PATH" bash "$CHECK" 2>&1 >/dev/null </dev/null)"
  rc=$?
  want=0
  [[ "$level" == block ]] && want=1
  expect "$level, one file unparsed: the other file's finding is still reported" "$want|yes|yes" \
    "$rc|$(grep -qxF "$(finding ok.sh 2 necessary)" <<<"$out" && echo yes)|$(grep -qF 'bad.sh: not judged' <<<"$out" && echo yes)"
done

ln -s "$REAL_PY" "$PYDIR/python3"
export PATH="$PYDIR:$PATH"

for fixture in shape1.py.txt shape2.sh.txt shape3.sh.txt shape4.py.txt shape5.yml.txt shape6.sh.txt shape7.py.txt shape8.sh.txt shape9.ps1.txt; do
  target="src/${fixture%.txt}"
  new_repo 'comment_lint: block'
  stage_fixture "$fixture" "$target"
  expect "block, $fixture: exactly the planted lines fail" "1|$(planted "$target" necessary)" "$(check "$REPO")"
done

new_repo 'comment_lint: block'
stage_fixture quiet.sh.txt src/quiet.sh
expect "stay quiet: a --flag, \${#name}, a quoted # and a heredoc body are no comment" "0|" "$(check "$REPO")"

new_repo 'comment_lint: block'
stage_fixture shape2.sh.txt notes/shape2.txt
stage_fixture shape2.sh.txt notes/shape2.md
expect "a file whose extension is not in the code list is not judged" "0|" "$(check "$REPO")"

new_repo 'comment_lint: block'
printf 'x=1\n# old note\n' >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
git -C "$REPO" commit -q -m old --no-verify
printf 'x=1\n# old note\ny=2\n' >"$REPO/seed.sh"
git -C "$REPO" add seed.sh
expect "a comment on a line the change did not add never fails" "0|" "$(check "$REPO")"

for marker in 'sync-managed: from lib/x.sh' '@generated' 'DO NOT EDIT' 'Code generated by protoc-gen-go. DO NOT EDIT.' \
  'GENERATED from lib/x.sh by scripts/sync-shared-copies.sh. Do not edit this copy:' 'This file is generated; do not edit it' \
  'Do not edit this file' 'do not edit by hand' 'Do NOT edit manually' 'do not edit directly' 'DO NOT EDIT -->'; do
  new_repo 'comment_lint: block'
  { printf '#!/bin/sh\n# %s\n' "$marker"; cat "$FIXTURES/shape2.sh.txt"; } >"$REPO/gen.sh"
  git -C "$REPO" add gen.sh
  expect "a file carrying '$marker' in its first 10 lines is skipped, and the skip is named" \
    "0|code-tidying: comment lint skipped gen.sh (a generated or sync-managed marker in its first 10 lines)" "$(check "$REPO")"
done

for marker in 'do not edit the order below' 'Do not edit historical entries; add a new one instead.'; do
  new_repo 'comment_lint: block'
  { printf '#!/bin/sh\n# %s PLANTED\n' "$marker"; cat "$FIXTURES/shape2.sh.txt"; } >"$REPO/gen.sh"
  git -C "$REPO" add gen.sh
  expect "a hand-written '$marker' line is no generated marker: the file is judged" \
    "1|$(planted gen.sh necessary)" "$(check "$REPO")"
done

new_repo 'comment_lint: report'
stage_fixture shape6.sh.txt src/a.sh
expect "report: the finding prints and the commit is not blocked" "0|$(finding src/a.sh 3 necessary)" "$(check "$REPO")"

for level in 'comment_lint: off' '' 'comment_lint: loud'; do
  new_repo "$level"
  stage_fixture shape6.sh.txt src/a.sh
  got="$(check "$REPO")"
  if [[ "$level" == *loud ]]; then
    expect "an invalid level does not run the lint and says so" "0|yes" \
      "${got%%|*}|$(grep -q 'comment_lint' <<<"${got#*|}" && echo yes)"
  else
    expect "level '${level:-unset}': silent, exit 0" "0|" "$got"
  fi
done

for posture in explanatory strict balanced conservative; do
  new_repo 'comment_lint: block' "comment_posture: $posture"
  stage_fixture shape6.sh.txt src/a.sh
  expect "posture $posture: the lint does not run" "0|" "$(check "$REPO")"
done

for posture in auto aggressive necessary; do
  new_repo 'comment_lint: block' "comment_posture: $posture"
  stage_fixture shape8.sh.txt src/a.sh
  expect "posture $posture reads as necessary: the link passes" "1|$(finding src/a.sh 4 necessary)" "$(check "$REPO")"
done

new_repo 'comment_lint: block' 'comment_posture: none'
stage_fixture shape8.sh.txt src/a.sh
expect "posture none: the linked run that necessary passes fails too" \
  "1|$(finding src/a.sh 1 none)
$(finding src/a.sh 2 none)
$(finding src/a.sh 4 none)" "$(check "$REPO")"

new_repo 'comment_lint: block'
mkdir -p "$REPO/docs/adr" "$REPO/src"
printf '# 42\n' >"$REPO/docs/adr/0042-use-postgres.md"
printf 'x=1\n# See ADR-0042\ny=1\n# See docs/adr/0042\nz=1\n# See ADR-0043\n' >"$REPO/src/a.sh"
git -C "$REPO" add -A
expect "an ADR pointer passes only when the record exists" "1|$(finding src/a.sh 6 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block'
mkdir -p "$REPO/docs/adr" "$REPO/src"
printf '# 42\n' >"$REPO/docs/adr/0042-use-postgres.md"
printf 'x=1\n# See ADR-0042\n' >"$REPO/src/a.sh"
git -C "$REPO" add -- src/a.sh
expect "a staged ADR pointer to an untracked record fails" "1|$(finding src/a.sh 2 necessary)" "$(check "$REPO")"
expect "--worktree: the same pointer passes on the untracked record" "0|" "$(check "$REPO" --worktree)"
git -C "$REPO" add -- docs/adr
rm "$REPO/docs/adr/0042-use-postgres.md"
expect "a staged ADR pointer to a staged record passes when the work tree lost it" "0|" "$(check "$REPO")"

new_repo 'comment_lint: block' 'comment_adr_dir: docs/decisions'
mkdir -p "$REPO/docs/decisions" "$REPO/src"
printf '# 7\n' >"$REPO/docs/decisions/0007-x.md"
printf 'x=1\n# See ADR-0007\n' >"$REPO/src/a.sh"
git -C "$REPO" add -A
expect "comment_adr_dir: docs/decisions holds the record ADR-0007 names" "0|" "$(check "$REPO")"

new_repo 'comment_lint: block'
mkdir -p "$REPO/docs/conventions"
printf 'comment_posture: none\n' >"$REPO/docs/conventions/code-tidying.local.yaml"
git -C "$REPO" add -A
stage_fixture shape8.sh.txt src/a.sh
expect "the personal override's posture is read too: none fails the link" 1 "$(got="$(check "$REPO")"; printf '%s' "${got%%|*}")"

new_repo 'comment_lint: block'
printf 'comment_lint: off\n' >"$REPO/docs/conventions/code-tidying.local.yaml"
stage_fixture shape6.sh.txt src/a.sh
expect "comment_lint in the personal override does not lower the level" "1|$(finding src/a.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block' 'comment_lint_allow:' '  - "silent-skip-ok:"' '  - "^# (test|case)-scope:"'
printf 'x=1 # silent-skip-ok: output discarded by design\n# test-scope: a b\n# plain note\n' >"$REPO/src.sh"
git -C "$REPO" add src.sh
expect "comment_lint_allow patterns pass repository markers, and only those" "1|$(finding src.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block' 'comment_lint_allow:' '  - "a["'
stage_fixture shape6.sh.txt src/a.sh
got="$(check "$REPO")"
expect "an allow pattern grep -E rejects blocks, naming the setting" "1|yes" \
  "${got%%|*}|$(grep -q 'comment_lint_allow' <<<"${got#*|}" && echo yes)"

skipped() {
  printf 'code-tidying: comment lint skipped %s (comment_lint_exclude: %s)' "$1" "$2"
}

new_repo 'comment_lint: block' 'comment_lint_exclude:' '  - "vendor/pinned/**"'
stage_fixture shape6.sh.txt vendor/pinned/a.sh
stage_fixture shape6.sh.txt vendor/pinned/deep/b.sh
stage_fixture shape6.sh.txt vendor/other.sh
expect "comment_lint_exclude: a file under the glob is skipped and named, a sibling outside it is judged" \
  "1|$(skipped vendor/pinned/a.sh 'vendor/pinned/**')
$(skipped vendor/pinned/deep/b.sh 'vendor/pinned/**')
$(finding vendor/other.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block' 'comment_lint_exclude:' '  - "gen/*.sh"' '  - "a?.sh"'
stage_fixture shape6.sh.txt gen/a.sh
stage_fixture shape6.sh.txt gen/sub/b.sh
stage_fixture shape6.sh.txt ab.sh
stage_fixture shape6.sh.txt abc.sh
expect "comment_lint_exclude: * and ? match within one path segment, never across /" \
  "1|$(skipped ab.sh 'a?.sh')
$(skipped gen/a.sh 'gen/*.sh')
$(finding abc.sh 3 necessary)
$(finding gen/sub/b.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block' 'comment_lint_exclude:' '  - "**/x.sh"' '  - "p.q.sh"'
stage_fixture shape6.sh.txt x.sh
stage_fixture shape6.sh.txt p/q/x.sh
stage_fixture shape6.sh.txt pzq.sh
expect "comment_lint_exclude: **/ matches zero or more segments, and . is literal" \
  "1|$(skipped p/q/x.sh '**/x.sh')
$(skipped x.sh '**/x.sh')
$(finding pzq.sh 3 necessary)" "$(check "$REPO")"

for setting in unset 'comment_lint_exclude:'; do
  new_repo 'comment_lint: block' "${setting#unset}"
  stage_fixture shape6.sh.txt vendor/pinned/a.sh
  expect "comment_lint_exclude ${setting/comment_lint_exclude:/empty}: every file is judged" \
    "1|$(finding vendor/pinned/a.sh 3 necessary)" "$(check "$REPO")"
done

new_repo 'comment_lint: block'
printf 'comment_lint_exclude:\n  - "vendor/**"\n' >"$REPO/docs/conventions/code-tidying.local.yaml"
stage_fixture shape6.sh.txt vendor/a.sh
expect "comment_lint_exclude in the personal override is not read" \
  "1|$(finding vendor/a.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block'
printf 'x=1\n# loose note\n' >"$REPO/loose.sh"
expect "--worktree judges an untracked file" "1|$(finding loose.sh 2 necessary)" "$(check "$REPO" --worktree)"

new_repo 'comment_lint: block'
stage_fixture shape6.sh.txt src/a.sh
printf 'x=1 # keep this exact wording remove-comments-ignore\nz=0\ny=2\n' >"$REPO/src/a.sh"
expect "partly staged: the staged comment is judged, not the work tree" "1|$(finding src/a.sh 3 necessary)" "$(check "$REPO")"

new_repo 'comment_lint: block'
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
expect "the vendored installer installs the entry" '[{"entry":"comment-lint","status":"installed"}]' \
  "$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# code-tidying comment-lint sha256:[0-9a-f]{64}$' <<<"$(sed -n 2p "$REPO/.git/hooks/code-tidying/comment-lint.sh")" && echo yes)"
stage_fixture shape6.sh.txt src/a.sh
err="$(git -C "$REPO" commit -q -m change 2>&1)"
rc=$?
expect "git commit runs the installed copy and fails on the added comment" "1|$(finding src/a.sh 3 necessary)" "$rc|$err"
expect "verify reports ok after the install" "ok	comment-lint" "$(node "$INSTALL" verify --repo "$REPO")"
printf 'x=1 # keep this exact wording remove-comments-ignore\n' >"$REPO/src/a.sh"
git -C "$REPO" add src/a.sh
err="$(git -C "$REPO" commit -q -m clean 2>&1)"
expect "git commit with only allowed comments passes" "0|" "$?|$err"

echo "comment-lint: $PASS passed, $FAIL failed"
((FAIL == 0))
