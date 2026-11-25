#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/exec-bit-check.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
[[ -f "$HELPER" ]] || skip_suite "exec-bit-check.sh not found at $HELPER"

printf 'SUITE: exec-bit-check.test.sh on %s\n' "$(git --version 2>/dev/null || printf 'git unknown')"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO_SEQ=0

mkrepo() {
  REPO_SEQ=$((REPO_SEQ + 1))
  local repo="$TEST_TMPDIR/repo$REPO_SEQ"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    printf 'seed\n' >seed.txt
    git add seed.txt
    git commit -qm "seed"
  ) >/dev/null 2>&1
  printf '%s\n' "$repo"
}

write_padded_script() {
  {
    printf '#!/usr/bin/env bash\n'
    for _ in {1..30}; do printf 'echo line\n'; done
  } >"$1"
}

staged_mode() {
  (cd "$1" && git ls-files --stage -- "$2" 2>/dev/null | head -n 1 | cut -d' ' -f1)
}

copy_records() {
  (cd "$1" && git diff --cached --name-status | grep -c '^C') | tr -d ' \r'
}

copy_unpaired_skip() {
  fail_discriminating_skip "$1 unpaired on $(git --version 2>/dev/null): git diff --cached --name-status has ${2:-0} C record(s), expected 1 — copy-arm discriminating coverage did not run"
}

repo="$(mkrepo)"
(
  cd "$repo" || exit 1
  printf '#!/usr/bin/env bash\necho hi\n' >new-script.sh
  printf 'plain text, no shebang\n' >notes.txt
  printf '#!/usr/bin/env bash\necho ok\n' >already-exec.sh
  git add new-script.sh notes.txt already-exec.sh
  git update-index --chmod=+x -- already-exec.sh
) >/dev/null 2>&1

out="$(bash "$HELPER" --repo-dir "$repo" --list 2>/dev/null)"
assert_contains "reports a newly-added shebang file staged 100644" "$out" "new-script.sh"
assert_not_contains "ignores a newly-added file with no shebang" "$out" "notes.txt"
assert_not_contains "ignores a newly-added shebang file already staged 100755" "$out" "already-exec.sh"

probe="$(bash "$HELPER" --repo-dir "$repo" --probe 2>/dev/null)"
assert_contains "probe names the offending path" "$probe" "new-script.sh"
assert_contains "probe reports the count" "$probe" "1 staged shebang file(s)"

bash "$HELPER" --repo-dir "$repo" --list >/dev/null 2>&1
assert_exit "--list exits 0 even with findings" 0 "$?"

repo2="$(mkrepo)"
(
  cd "$repo2" || exit 1
  printf '#!/usr/bin/env bash\necho v1\n' >tracked.sh
  git add tracked.sh
  git commit -qm "add tracked.sh"
  printf '#!/usr/bin/env bash\necho v2\n' >tracked.sh
  git add tracked.sh
) >/dev/null 2>&1

out2="$(bash "$HELPER" --repo-dir "$repo2" --list 2>/dev/null)"
assert_silent "an already-tracked (M) shebang file is not reported" "$out2"

repo3="$(mkrepo)"
(
  cd "$repo3" || exit 1
  printf '#!/usr/bin/env bash\necho gone\n' >doomed.sh
  git add doomed.sh
  git commit -qm "add doomed.sh"
  git rm -q --cached doomed.sh
) >/dev/null 2>&1

out3="$(bash "$HELPER" --repo-dir "$repo3" --list 2>/dev/null)"
assert_silent "a staged deletion (D) is not reported as an add" "$out3"

repo4="$(mkrepo)"
symlink_ok=1
(
  cd "$repo4" || exit 1
  printf '#!/usr/bin/env bash\necho target\n' >target.sh
  ln -s target.sh link.sh
) >/dev/null 2>&1 || symlink_ok=0

if [[ "$symlink_ok" -eq 1 ]] && [[ -L "$repo4/link.sh" ]]; then
  (cd "$repo4" && git add target.sh link.sh) >/dev/null 2>&1
  link_mode="$(staged_mode "$repo4" "link.sh")"
  if [[ "$link_mode" == "120000" ]]; then
    out4="$(bash "$HELPER" --repo-dir "$repo4" --list 2>/dev/null)"
    assert_not_contains "a symlink (mode 120000) is never reported" "$out4" "link.sh"
  else
    skip_case "symlink staged as $link_mode, not 120000 (core.symlinks off)"
  fi
else
  skip_case "symlinks unsupported on this platform"
fi

repo5="$(mkrepo)"
(
  cd "$repo5" || exit 1
  printf '#!/usr/bin/env bash\necho fixme\n' >fixme.sh
  git add fixme.sh
) >/dev/null 2>&1

assert_eq "before --fix the index records 100644" "100644" "$(staged_mode "$repo5" fixme.sh)"

fix_out="$(bash "$HELPER" --repo-dir "$repo5" --fix -- fixme.sh 2>&1)"
fix_rc=$?
assert_exit "--fix exits 0 on success" 0 "$fix_rc"
assert_contains "--fix names the path it fixed" "$fix_out" "fixme.sh"
assert_eq "after --fix the index records 100755" "100755" "$(staged_mode "$repo5" fixme.sh)"

if [[ -x "$repo5/fixme.sh" ]]; then
  pass "after --fix the worktree file is executable"
else
  skip_case "worktree exec bit not observable on this filesystem"
fi

(cd "$repo5" && git add fixme.sh) >/dev/null 2>&1
assert_eq "the fix survives a subsequent git add" "100755" "$(staged_mode "$repo5" fixme.sh)"

after="$(bash "$HELPER" --repo-dir "$repo5" --list 2>/dev/null)"
assert_silent "nothing remains to report after --fix" "$after"

nothing="$(bash "$HELPER" --repo-dir "$repo5" --fix -- fixme.sh 2>&1)"
assert_contains "--fix on a clean tree says so" "$nothing" "nothing to fix"

clean_probe="$(bash "$HELPER" --repo-dir "$repo5" --probe 2>/dev/null)"
assert_eq "probe prints 'none' when clean" "none" "$clean_probe"

repo5b="$(mkrepo)"
(
  cd "$repo5b" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho nofilemode\n' >nofilemode.sh
  git add nofilemode.sh
) >/dev/null 2>&1

out5b="$(bash "$HELPER" --repo-dir "$repo5b" --list 2>/dev/null)"
assert_contains "detects the offender under core.filemode=false" "$out5b" "nofilemode.sh"

bash "$HELPER" --repo-dir "$repo5b" --fix -- nofilemode.sh >/dev/null 2>&1
assert_eq "--fix reaches the index under core.filemode=false" \
  "100755" "$(staged_mode "$repo5b" nofilemode.sh)"

repo6="$(mkrepo)"
(
  cd "$repo6" || exit 1
  mkdir -p tools other
  printf '#!/usr/bin/env bash\necho a\n' >tools/a.sh
  printf '#!/usr/bin/env bash\necho b\n' >other/b.sh
  git add tools/a.sh other/b.sh
) >/dev/null 2>&1

scoped="$(bash "$HELPER" --repo-dir "$repo6" --list -- tools 2>/dev/null)"
assert_contains "pathspec keeps the in-scope path" "$scoped" "tools/a.sh"
assert_not_contains "pathspec excludes the out-of-scope path" "$scoped" "other/b.sh"

repo7="$(mkrepo)"
(
  cd "$repo7" || exit 1
  printf '#!/usr/bin/env bash\necho spaced\n' >"my script.sh"
  git add "my script.sh"
) >/dev/null 2>&1

out7="$(bash "$HELPER" --repo-dir "$repo7" --list 2>/dev/null)"
assert_contains "a path containing a space is reported intact" "$out7" "my script.sh"

bash "$HELPER" --repo-dir "$repo7" --fix -- "my script.sh" >/dev/null 2>&1
assert_eq "a path containing a space is fixed" "100755" "$(staged_mode "$repo7" "my script.sh")"

bash "$HELPER" --repo-dir "$repo" --bogus-flag >/dev/null 2>&1
assert_exit "unknown argument exits 2" 2 "$?"

bash "$HELPER" --repo-dir >/dev/null 2>&1
assert_exit "--repo-dir with no value exits 2" 2 "$?"

nonrepo="$TEST_TMPDIR/not-a-repo"
mkdir -p "$nonrepo"
bash "$HELPER" --repo-dir "$nonrepo" --list >/dev/null 2>&1
assert_exit "a non-repository exits 3" 3 "$?"

bash "$HELPER" --repo-dir "$TEST_TMPDIR/does-not-exist" --list >/dev/null 2>&1
assert_exit "an unreachable --repo-dir exits 3" 3 "$?"

bash "$HELPER" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"

repo8b="$(mkrepo)"
(
  cd "$repo8b" || exit 1
  printf '#!/usr/bin/env bash\necho scoped\n' >scoped.sh
  git add scoped.sh
) >/dev/null 2>&1

refusal="$(bash "$HELPER" --repo-dir "$repo8b" --fix 2>&1)"
refuse_rc=$?
assert_exit "bare --fix refuses with exit 2" 2 "$refuse_rc"
assert_contains "the refusal explains the required scope" "$refusal" "needs an explicit scope"
assert_eq "a refused --fix mutates nothing" "100644" "$(staged_mode "$repo8b" scoped.sh)"

bash "$HELPER" --repo-dir "$repo8b" --list >/dev/null 2>&1
assert_exit "--list stays unscoped and exits 0" 0 "$?"

bash "$HELPER" --repo-dir "$repo8b" --probe >/dev/null 2>&1
assert_exit "--probe stays unscoped and exits 0" 0 "$?"

bash "$HELPER" --repo-dir "$repo8b" --fix -- scoped.sh >/dev/null 2>&1
assert_eq "--fix with an explicit pathspec is allowed" "100755" "$(staged_mode "$repo8b" scoped.sh)"

repo8c="$(mkrepo)"
(
  cd "$repo8c" || exit 1
  printf '#!/usr/bin/env bash\necho swept\n' >swept.sh
  git add swept.sh
) >/dev/null 2>&1

bash "$HELPER" --repo-dir "$repo8c" --fix --all >/dev/null 2>&1
assert_eq "--fix --all is the explicit whole-index opt-in" "100755" "$(staged_mode "$repo8c" swept.sh)"

repo9="$(mkrepo)"
empty="$(bash "$HELPER" --repo-dir "$repo9" --list 2>/dev/null)"
assert_silent "an empty staged set reports nothing" "$empty"
bash "$HELPER" --repo-dir "$repo9" --list >/dev/null 2>&1
assert_exit "an empty staged set exits 0" 0 "$?"

repo10="$(mkrepo)"
(
  cd "$repo10" || exit 1
  mkdir -p sub/nested
  printf '#!/usr/bin/env bash\necho deep\n' >sub/nested/deep.sh
  printf '#!/usr/bin/env bash\necho top\n' >toplevel.sh
  git add sub/nested/deep.sh toplevel.sh
) >/dev/null 2>&1

from_sub="$(cd "$repo10/sub" && bash "$HELPER" --list 2>/dev/null)"
assert_contains "run from a subdirectory still sees the root-level offender" "$from_sub" "toplevel.sh"
assert_contains "run from a subdirectory still sees the nested offender" "$from_sub" "sub/nested/deep.sh"

sub_probe="$(cd "$repo10/sub" && bash "$HELPER" --probe 2>/dev/null)"
assert_contains "probe from a subdirectory reports both offenders" "$sub_probe" "2 staged shebang file(s)"

(cd "$repo10/sub" && bash "$HELPER" --fix -- nested/deep.sh) >/dev/null 2>&1
assert_eq "a cwd-relative pathspec from a subdirectory is re-anchored and fixed" \
  "100755" "$(staged_mode "$repo10" sub/nested/deep.sh)"
assert_eq "the re-anchored --fix did not touch the out-of-scope path" \
  "100644" "$(staged_mode "$repo10" toplevel.sh)"

repo11="$(mkrepo)"
sym_ok=1
(
  cd "$repo11" || exit 1
  printf '#!/usr/bin/env bash\necho real\n' >swapped.sh
  git add swapped.sh
  mkdir -p outside
  printf 'not a script\n' >outside/victim.txt
  rm -f swapped.sh
  ln -s outside/victim.txt swapped.sh
) >/dev/null 2>&1 || sym_ok=0

if [[ "$sym_ok" -eq 1 ]] && [[ -L "$repo11/swapped.sh" ]]; then
  sym_out="$(bash "$HELPER" --repo-dir "$repo11" --fix -- swapped.sh 2>&1)"
  sym_rc=$?
  assert_exit "a worktree symlink over a staged regular file fails --fix" 4 "$sym_rc"
  assert_contains "the refusal names the symlink mismatch" "$sym_out" "worktree entry is a symlink"
  if [[ -x "$repo11/outside/victim.txt" ]]; then
    fail "the symlink target must not become executable" "not executable" "executable"
  else
    pass "the symlink target was not made executable"
  fi
else
  skip_case "symlinks unsupported on this platform"
fi

repo12="$(mkrepo)"
(
  cd "$repo12" || exit 1
  printf '#!/usr/bin/env bash\necho one\n' >one.sh
  printf '#!/usr/bin/env bash\necho two\n' >two.sh
  git add one.sh two.sh
) >/dev/null 2>&1

nul_count="$(bash "$HELPER" --repo-dir "$repo12" --list0 2>/dev/null | tr -dc '\0' | wc -c | tr -d ' \r')"
assert_eq "--list0 emits one NUL terminator per offender" "2" "$nul_count"

bash "$HELPER" --repo-dir "$repo12" --list0 >/dev/null 2>&1
assert_exit "--list0 exits 0" 0 "$?"

repo_nl="$(mkrepo)"
nl_name=$'we\nird.sh'
(
  cd "$repo_nl" || exit 1
  printf '#!/usr/bin/env bash\n' >"$nl_name"
  git add -- "$nl_name"
) >/dev/null 2>&1
nl_probe="$(bash "$HELPER" --repo-dir "$repo_nl" --probe 2>/dev/null)"
assert_eq "--probe keeps a newline in a path on one line" "1" "$(printf '%s\n' "$nl_probe" | wc -l | tr -d ' ')"
assert_contains "--probe shell-quotes the newline" "$nl_probe" "\$'we\\nird.sh'"
nl_list="$(bash "$HELPER" --repo-dir "$repo_nl" --list 2>/dev/null)"
assert_eq "--list keeps a newline in a path on one line" "1" "$(printf '%s\n' "$nl_list" | wc -l | tr -d ' ')"

repo13="$(mkrepo)"
(
  cd "$repo13" || exit 1
  git config core.filemode false
  printf 'unrelated\n' >other.txt
  git add other.txt
  printf '#!/usr/bin/env bash\necho pathspec\n' >ps.sh
  git add ps.sh
) >/dev/null 2>&1

bash "$HELPER" --repo-dir "$repo13" --fix -- ps.sh >/dev/null 2>&1
assert_eq "index is corrected to 100755 before either commit form" \
  "100755" "$(staged_mode "$repo13" ps.sh)"

(cd "$repo13" && git commit -q -m "test: pathspec" -- ps.sh) >/dev/null 2>&1
ps_head="$(cd "$repo13" && git ls-tree HEAD -- ps.sh | cut -d' ' -f1)"
assert_eq "a pathspec (--only) commit LOSES the exec bit under core.filemode=false" \
  "100644" "$ps_head"

repo14="$(mkrepo)"
(
  cd "$repo14" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho plain\n' >pl.sh
  git add pl.sh
) >/dev/null 2>&1

bash "$HELPER" --repo-dir "$repo14" --fix -- pl.sh >/dev/null 2>&1
(cd "$repo14" && git commit -q -m "test: plain") >/dev/null 2>&1
pl_head="$(cd "$repo14" && git ls-tree HEAD -- pl.sh | cut -d' ' -f1)"
assert_eq "a plain index commit PRESERVES the exec bit under core.filemode=false" \
  "100755" "$pl_head"

repo15="$(mkrepo)"
(
  cd "$repo15" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho renamed\n' >src.sh
  git add src.sh
  git update-index --chmod=+x -- src.sh
  git commit -qm "seed the executable source"
  git mv src.sh moved.sh
  git rm -q --cached moved.sh
  git add moved.sh
) >/dev/null 2>&1

rename_status="$(cd "$repo15" && git diff --cached --name-status | head -n 1 | cut -f1)"
assert_contains "the fixture really is reported as a rename" "$rename_status" "R"
assert_eq "the rename destination really did drop the exec bit" \
  "100644" "$(staged_mode "$repo15" moved.sh)"

rename_out="$(bash "$HELPER" --repo-dir "$repo15" --list 2>/dev/null)"
assert_contains "a rename destination that dropped the bit is reported" "$rename_out" "moved.sh"

bash "$HELPER" --repo-dir "$repo15" --fix -- moved.sh >/dev/null 2>&1
assert_eq "--fix corrects a rename destination" "100755" "$(staged_mode "$repo15" moved.sh)"

repo16="$(mkrepo)"
(
  cd "$repo16" || exit 1
  git config core.filemode false
  git config diff.renames copies
  write_padded_script orig.sh
  git add orig.sh
  git update-index --chmod=+x -- orig.sh
  git commit -qm "seed the executable copy source"
  printf 'echo appended\n' >>orig.sh
  cp orig.sh dup.sh
  git add orig.sh dup.sh
) >/dev/null 2>&1

copy_status="$(copy_records "$repo16")"
if [[ "$copy_status" == "1" ]]; then
  copy_out="$(bash "$HELPER" --repo-dir "$repo16" --list 2>/dev/null)"
  assert_contains "a copy destination that dropped the bit is reported" "$copy_out" "dup.sh"

  bash "$HELPER" --repo-dir "$repo16" --fix -- dup.sh >/dev/null 2>&1
  assert_eq "--fix corrects a copy destination" "100755" "$(staged_mode "$repo16" dup.sh)"
else
  copy_unpaired_skip "copy-arm fixture" "$copy_status"
fi

repo17="$(mkrepo)"
(
  cd "$repo17" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho scoped\n' >from.sh
  git add from.sh
  git update-index --chmod=+x -- from.sh
  git commit -qm "seed the scoped rename source"
  git mv from.sh to.sh
  git rm -q --cached to.sh
  git add to.sh
) >/dev/null 2>&1

bash "$HELPER" --repo-dir "$repo17" --fix -- from.sh >/dev/null 2>&1
assert_eq "a --fix scoped to the rename SOURCE leaves the destination untouched" \
  "100644" "$(staged_mode "$repo17" to.sh)"

repo18="$(mkrepo)"
(
  cd "$repo18" || exit 1
  printf '#!/usr/bin/env bash\necho kept\n' >keep.sh
  git add keep.sh
  git update-index --chmod=+x -- keep.sh
  git commit -qm "seed the preserved-bit rename source"
  git mv keep.sh renamed.sh
) >/dev/null 2>&1

assert_eq "the fixture's rename destination KEPT the exec bit" \
  "100755" "$(staged_mode "$repo18" renamed.sh)"
assert_eq "a rename that preserved the exec bit is NOT reported" \
  "" "$(bash "$HELPER" --repo-dir "$repo18" --list 2>/dev/null)"

repo19="$(mkrepo)"
(
  cd "$repo19" || exit 1
  printf '#!/usr/bin/env bash\necho sourced\n' >lib.sh
  git add lib.sh
  git commit -qm "seed the deliberately non-executable shebang source"
  git mv lib.sh lib-moved.sh
) >/dev/null 2>&1

nonexec_raw="$(cd "$repo19" && git diff --cached --raw | head -n 1)"
assert_contains "the fixture really is a rename off a 100644 source" \
  "$nonexec_raw" ":100644 100644"
assert_eq "the fixture's destination really is 100644 with a shebang" \
  "100644" "$(staged_mode "$repo19" lib-moved.sh)"
assert_eq "a rename whose SOURCE was never executable is NOT reported" \
  "" "$(bash "$HELPER" --repo-dir "$repo19" --list 2>/dev/null)"

repo24="$(mkrepo)"
(
  cd "$repo24" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho sourced\n' >dis-lib.sh
  git add dis-lib.sh
  git commit -qm "seed the disagreement fixture's non-executable source"
  git mv dis-lib.sh dis-lib-moved.sh
  printf '#!/usr/bin/env bash\necho unrelated\n' >zz-dis-extra.sh
  git add zz-dis-extra.sh
) >/dev/null 2>&1

(cd "$repo24" && git config diff.renames false) >/dev/null 2>&1
dis_off_status="$(cd "$repo24" && git diff --cached --name-status | tr '\t' ' ' | tr '\n' ';')"
dis_off_head="$(cd "$repo24" && git rev-parse 'HEAD^{tree}' 2>/dev/null)"
dis_off_index="$(cd "$repo24" && git write-tree 2>/dev/null)"
dis_off="$(bash "$HELPER" --repo-dir "$repo24" --list 2>/dev/null | sort | tr '\n' ' ')"

(cd "$repo24" && git config diff.renames true) >/dev/null 2>&1
dis_on_status="$(cd "$repo24" && git diff --cached --name-status | tr '\t' ' ' | tr '\n' ';')"
dis_on_raw="$(cd "$repo24" && git diff --cached --raw | grep 'dis-lib-moved\.sh')"
dis_on_head="$(cd "$repo24" && git rev-parse 'HEAD^{tree}' 2>/dev/null)"
dis_on_index="$(cd "$repo24" && git write-tree 2>/dev/null)"
dis_on="$(bash "$HELPER" --repo-dir "$repo24" --list 2>/dev/null | sort | tr '\n' ' ')"

if [[ "$dis_off_status" == *"A dis-lib-moved.sh;"* ]] && [[ "$dis_off_status" == *"D dis-lib.sh;"* ]] &&
  [[ "$dis_on_status" == *"R"*"dis-lib.sh dis-lib-moved.sh;"* ]]; then
  assert_eq "HEAD is identical across the two diff.renames runs" \
    "$dis_off_head" "$dis_on_head"
  assert_eq "the INDEX is identical across the two diff.renames runs" \
    "$dis_off_index" "$dis_on_index"
  assert_contains "the diff.renames=true run really pairs it as a rename off a 100644 source" \
    "$dis_on_raw" ":100644 100644"
  assert_eq "diff.renames=false REPORTS the moved 100644 shebang file (as an add)" \
    "dis-lib-moved.sh zz-dis-extra.sh " "$dis_off"
  assert_eq "diff.renames=true does NOT report it (the kept #2141 gate)" \
    "zz-dis-extra.sh " "$dis_on"
  dis_verdict="$([[ "$dis_off" == "$dis_on" ]] && printf 'AGREE' || printf 'DISAGREE')"
  assert_eq "the two diff.renames configurations DISAGREE on identical staged content — deliberate, kept in #2141" \
    "DISAGREE" "$dis_verdict"
else
  fail_discriminating_skip "this git did not produce both a D+A and an R pairing for the disagreement fixture (renames=false saw: ${dis_off_status:-<empty>} | renames=true saw: ${dis_on_status:-<empty>})"
fi

repo21="$(mkrepo)"
(
  cd "$repo21" || exit 1
  git config core.filemode false
  git config diff.renames copies
  write_padded_script tpl.sh
  git add tpl.sh
  git commit -qm "seed the deliberately non-executable copy source"
  printf 'echo appended\n' >>tpl.sh
  cp tpl.sh tpl-copy.sh
  git add tpl.sh tpl-copy.sh
) >/dev/null 2>&1

nonexec_copy_status="$(copy_records "$repo21")"
if [[ "$nonexec_copy_status" == "1" ]]; then
  assert_contains "the fixture really is a copy off a 100644 source" \
    "$(cd "$repo21" && git diff --cached --raw | grep 'tpl-copy\.sh')" ":100644 100644"
  assert_eq "the copy fixture's destination really is 100644 with a shebang" \
    "100644" "$(staged_mode "$repo21" tpl-copy.sh)"
  assert_eq "a copy whose SOURCE was never executable IS reported" \
    "tpl-copy.sh" "$(bash "$HELPER" --repo-dir "$repo21" --list 2>/dev/null)"

  bash "$HELPER" --repo-dir "$repo21" --fix --all >/dev/null 2>&1
  assert_eq "--fix corrects a copy destination off a non-executable source" \
    "100755" "$(staged_mode "$repo21" tpl-copy.sh)"
  assert_eq "the copy SOURCE is not itself admitted by the copy arm" \
    "100644" "$(staged_mode "$repo21" tpl.sh)"
else
  copy_unpaired_skip "non-executable copy fixture" "$nonexec_copy_status"
fi

repo22="$(mkrepo)"
(
  cd "$repo22" || exit 1
  git config core.filemode false
  write_padded_script lib.sh
  git add lib.sh
  git commit -qm "seed the agreement fixture's non-executable source"
  printf 'echo appended\n' >>lib.sh
  cp lib.sh copy.sh
  printf '#!/usr/bin/env bash\necho unrelated\n' >extra.sh
  git add lib.sh copy.sh extra.sh
) >/dev/null 2>&1

(cd "$repo22" && git config diff.renames false) >/dev/null 2>&1
agree_off_status="$(cd "$repo22" && git diff --cached --name-status | grep -c '^A.*copy\.sh' | tr -d ' \r')"
agree_off="$(bash "$HELPER" --repo-dir "$repo22" --list 2>/dev/null | sort | tr '\n' ' ')"

(cd "$repo22" && git config diff.renames copies) >/dev/null 2>&1
agree_on_status="$(copy_records "$repo22")"
agree_on="$(bash "$HELPER" --repo-dir "$repo22" --list 2>/dev/null | sort | tr '\n' ' ')"

if [[ "$agree_off_status" == "1" ]] && [[ "$agree_on_status" == "1" ]]; then
  assert_eq "diff.renames=false reports the destination (as an add)" \
    "copy.sh extra.sh " "$agree_off"
  assert_eq "diff.renames=copies reports the same destination (as a copy)" \
    "copy.sh extra.sh " "$agree_on"
  assert_eq "the two diff.renames configurations AGREE on identical staged content" \
    "$agree_off" "$agree_on"
else
  fail_discriminating_skip "agreement fixture unpaired on $(git --version 2>/dev/null): diff.renames=false A copy.sh=${agree_off_status:-0}, diff.renames=copies C=${agree_on_status:-0} (expected 1 each) — copy-arm discriminating coverage did not run"
fi

repo20="$(mkrepo)"
(
  cd "$repo20" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho spaced\n' >"old name.sh"
  git add "old name.sh"
  git update-index --chmod=+x -- "old name.sh"
  git commit -qm "seed the spaced rename source"
  git mv "old name.sh" "new name.sh"
  git rm -q --cached "new name.sh"
  git add "new name.sh"
) >/dev/null 2>&1

assert_contains "the spaced fixture really is a rename off a 100755 source" \
  "$(cd "$repo20" && git diff --cached --raw | head -n 1)" ":100755 100644"
assert_eq "a rename destination is reported when BOTH paths contain spaces" \
  "new name.sh" "$(bash "$HELPER" --repo-dir "$repo20" --list 2>/dev/null)"

repo23="$(mkrepo)"
(
  cd "$repo23" || exit 1
  git config core.filemode false
  git config diff.renames copies
  git config core.quotepath true
  write_padded_script "tpl lib.sh"
  git add "tpl lib.sh"
  git commit -qm "seed the spaced non-executable copy source"
  printf 'echo appended\n' >>"tpl lib.sh"
  cp "tpl lib.sh" "tpl copy.sh"
  git add "tpl lib.sh" "tpl copy.sh"
) >/dev/null 2>&1

spaced_copy_status="$(copy_records "$repo23")"
if [[ "$spaced_copy_status" == "1" ]]; then
  assert_eq "a copy destination is reported when BOTH paths contain spaces" \
    "tpl copy.sh" "$(bash "$HELPER" --repo-dir "$repo23" --list 2>/dev/null)"
else
  copy_unpaired_skip "spaced copy fixture" "$spaced_copy_status"
fi

printf '\n%d case(s), %d failure(s), %d optional skip(s), %d discriminating skip(s)\n' \
  "$CASE_NUM" "$FAILED" "$SKIP_CASES" "$DISCRIMINATING_SKIP_CASES"
[[ $FAILED -eq 0 ]] || exit 1
