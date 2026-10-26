#!/usr/bin/env bash
# Contract test for scripts/check-comment-hygiene.sh: where it reads the pin and
# the exclusions, which files it scans, and how it reports, against a fixture
# repository and a file:// stand-in for the ci-workflows raw content. The
# stand-in library flags a comment line holding the word BANNED; what the real
# patterns ban is the ci-workflows suite's business.
#
#   bash scripts/check-comment-hygiene.test.sh
#
# The cases hold shell source as literal data on purpose.
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh" || exit 2

SCRIPT="$SELF_DIR/check-comment-hygiene.sh"

if ! command -v curl >/dev/null 2>&1; then
  # silent-skip-ok: the script itself exits 2 without curl, which
  # check-script-contract.test.sh holds; these cases need curl to read file://.
  ok "SKIP every case (curl not installed)"
  test_harness::report
  exit
fi

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/.github/workflows" "$repo/vendor" "$repo/src"
git_init_test_repo "$repo" || exit 2

pin_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
pin_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
action_dir="$tmp/raw/$pin_a/.github/actions/check-comment-markers"
mkdir -p "$action_dir"
export CHECK_COMMENT_HYGIENE_RAW_BASE="file://$tmp/raw"

# workflow <sha> <exclude token>: the fixture's pr-require-checks.yml.
workflow() {
  printf '%s\n' \
    'jobs:' \
    '  lint-repo:' \
    '    steps:' \
    '      - name: Scan comment hygiene' \
    "        uses: melodic-software/ci-workflows/.github/actions/check-comment-markers@$1 # v0.0.1" \
    '        with:' \
    '          exclude: >-' \
    "            $2" \
    '      - name: Next step' \
    '        run: true' >"$repo/.github/workflows/pr-require-checks.yml"
}

printf '%s\n' \
  'name: fixture' \
  'inputs:' \
  '  extensions:' \
  '    description: >-' \
  '      Globs.' \
  '    default: >-' \
  '      *.sh *.py' \
  '      *.ts' \
  '  exclude:' \
  "    default: ''" \
  'runs:' \
  '  using: composite' >"$action_dir/action.yml"

cat >"$action_dir/comment-hygiene-patterns.sh" <<'LIB'
chp::scan_text() {
  local content="$1" n=0 line found=0
  while IFS= read -r line; do
    n=$((n + 1))
    if [[ "$line" =~ ^[[:space:]]*(//|#) && "$line" == *BANNED* ]]; then
      printf '%s:marker:BANNED\n' "$n"
      found=1
    fi
  done <<<"$content"
  return "$found"
}
LIB

workflow "$pin_a" ':(exclude)vendor/**'
printf 'echo ok\n' >"$repo/src/clean.sh"
printf 'echo one\n# BANNED here\n' >"$repo/src/bad.sh"
printf 'x = 1\n# BANNED too\n' >"$repo/src/bad.py"
printf '# BANNED heading\n' >"$repo/src/notes.md"
printf '# BANNED vendored\n' >"$repo/vendor/lib.sh"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
git_test_config "$repo" branch -q base

# run <env...> -- <args...>: runs the script in the fixture; sets RC, OUT, ERR.
run() {
  local -a envs=()
  while [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  RC=0
  OUT="$(cd "$repo" && env ${envs[@]+"${envs[@]}"} bash "$SCRIPT" "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then ok "$name"; else bad "$name" "rc=$RC out=$OUT err=$ERR"; fi
}

run -- base src/clean.sh
check "a clean code file passes with the statement on stdout" \
  '[[ $RC == 0 && $OUT == *"clean over 1 files (ci-workflows aaaaaaaaaaaa)"* && -z $ERR ]]'

run -- base src/clean.sh src/bad.sh src/bad.py
check "a banned comment fails with each file:line on stderr" \
  '[[ $RC == 1 && $ERR == *"src/bad.sh:2:marker:BANNED"* && $ERR == *"src/bad.py:2:marker:BANNED"* && $ERR == *"violations in 2 of 3 files"* && -z $OUT ]]'

run -- base src/notes.md
check "a file outside the action's extensions is not scanned" \
  '[[ $RC == 0 && $OUT == *"none of the 1 files is a code file"* ]]'

run -- base vendor/lib.sh
check "a file the step's exclude input removes is not scanned" \
  '[[ $RC == 0 && $OUT == *"none of the 1 files is a code file"* ]]'

run -- base src/missing.sh
check "a named file that does not exist exits 2, never a silent pass" \
  '[[ $RC == 2 && $ERR == *"no such file in "*": src/missing.sh"* && -z $OUT ]]'

ln -s bad.sh "$repo/src/link.sh" 2>/dev/null
if [[ -L "$repo/src/link.sh" ]]; then
  run -- base src/link.sh
  check "a symlink is not scanned, as git grep skips it in CI" \
    '[[ $RC == 0 && $OUT == *"none of the 1 files"* ]]'
else
  # silent-skip-ok: Git Bash's ln -s copies the file, so there is no symlink to skip.
  ok "SKIP the symlink case (ln -s made no symlink here)"
fi
rm -f "$repo/src/link.sh"

RC=0
OUT="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$SCRIPT" base src/bad.sh 2>"$tmp/err")" || RC=$?
ERR="$(cat "$tmp/err")"
check "CHECK_DATA_ROOT names the tree whose files are read" \
  '[[ $RC == 1 && $ERR == *"src/bad.sh:2:marker:BANNED"* ]]'

# A branch that moves the pin: the pin is read from <pin-rev>, the exclusions
# from HEAD.
workflow "$pin_b" ':(exclude)src/bad.sh'
git_test_config "$repo" commit -q -am "move the pin"
run -- base src/bad.sh src/bad.py
check "the pin comes from <pin-rev>, not from a branch that changed it" \
  '[[ $RC == 1 && $ERR == *"src/bad.py:2:marker:BANNED"* ]]'
check "the exclusions come from HEAD's workflow" '[[ $ERR != *"src/bad.sh:"* ]]'
run -- HEAD src/bad.py
check "a failed fetch exits 2 with the reason as its last line" \
  '[[ $RC == 2 && $(tail -n 1 <<<"$ERR") == *"fetch of .github/actions/check-comment-markers/action.yml at ci-workflows bbbbbbbbbbbb failed"* ]]'

workflow "$pin_a" ':(exclude)src'
git_test_config "$repo" commit -q -am "exclude a directory"
run -- base src/bad.py
check "an exclusion naming a directory removes what lies under it" \
  '[[ $RC == 0 && $OUT == *"none of the 1 files"* ]]'

# The exclude input written before the uses line, and a comment naming the
# action above the step, still find the step's own exclusions.
printf '%s\n' \
  'jobs:' \
  '  lint-repo:' \
  '    steps:' \
  '      - name: Other step' \
  '        run: echo melodic-software/ci-workflows/.github/actions/check-comment-markers@x' \
  '      - name: Scan comment hygiene' \
  "        with:" \
  "          exclude: ':(exclude)src/bad.py'" \
  "        uses: melodic-software/ci-workflows/.github/actions/check-comment-markers@$pin_a" \
  '      - name: Next step' \
  '        run: true' >"$repo/.github/workflows/pr-require-checks.yml"
git_test_config "$repo" commit -q -am "exclude before uses"
run -- base src/bad.py src/bad.sh
check "an inline exclude input before the uses line is read" \
  '[[ $RC == 1 && $ERR == *"src/bad.sh:2:marker:BANNED"* && $ERR != *"src/bad.py:"* ]]'

workflow "$pin_a" ':!src/**'
git_test_config "$repo" commit -q -am "other pathspec magic"
run -- base src/bad.py
check "a pathspec form it does not read exits 2 rather than scanning too much" \
  '[[ $RC == 2 && $ERR == *"unsupported pathspec"* ]]'

printf 'jobs: {}\n' >"$repo/.github/workflows/pr-require-checks.yml"
git_test_config "$repo" commit -q -am "no pin"
run -- HEAD src/bad.py
check "no pinned uses line exits 2" '[[ $RC == 2 && $ERR == *"no check-comment-markers uses line"* ]]'
git_test_config "$repo" reset -q --hard base

printf 'name: fixture\n' >"$tmp/action.yml"
cp "$action_dir/action.yml" "$tmp/action.yml.keep"
cp "$tmp/action.yml" "$action_dir/action.yml"
run -- base src/bad.py
check "an action.yml with no extensions default exits 2" '[[ $RC == 2 && $ERR == *"no extensions default"* ]]'
cp "$tmp/action.yml.keep" "$action_dir/action.yml"

cp "$action_dir/comment-hygiene-patterns.sh" "$tmp/lib.keep"
printf 'true\n' >"$action_dir/comment-hygiene-patterns.sh"
run -- base src/bad.py
check "a library with no chp::scan_text exits 2" '[[ $RC == 2 && $ERR == *"defines no chp::scan_text"* ]]'
cp "$tmp/lib.keep" "$action_dir/comment-hygiene-patterns.sh"

run -- base
check "no files is a pass" '[[ $RC == 0 && $OUT == *"none of the 0 files"* ]]'
run --
check "no pin-rev is a usage error" '[[ $RC == 2 && $ERR == *"usage:"* ]]'
run -- no-such-rev src/bad.py
check "an unreadable pin-rev exits 2" '[[ $RC == 2 && $ERR == *"cannot read .github/workflows/pr-require-checks.yml at no-such-rev"* ]]'

test_harness::report
