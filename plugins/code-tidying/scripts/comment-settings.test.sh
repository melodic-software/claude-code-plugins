#!/usr/bin/env bash
# test-scope: plugins/code-tidying/scripts/comment-settings.sh plugins/code-tidying/skills/remove-comments/scripts/settings.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/comment-settings.sh"
ENTRY="$HERE/../skills/remove-comments/scripts/settings.sh"
TEAM="docs/conventions/code-tidying.yaml"
PERSONAL="docs/conventions/code-tidying.local.yaml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() {
  if [[ "$3" == "$2" ]]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n  want: %q\n  got:  %q\n' "$1" "$2" "$3" >&2
    fails=$((fails + 1))
  fi
}

repo_with() {
  local d
  d="$(mktemp -d "$TMP/repo.XXXXXX")"
  git -C "$d" init -q
  mkdir -p "$d/docs/conventions"
  [[ "$1" != - ]] && printf '%s' "$1" >"$d/$TEAM"
  [[ "$2" != - ]] && printf '%s' "$2" >"$d/$PERSONAL"
  printf '%s\n' "$d"
}

TAB=$'\t'
lines_for() { bash "$SUT" "$1" 2>/dev/null | grep "^$2${TAB}"; }

repo="$(repo_with - -)"
check 'no files leaves the posture unset' \
  "comment_posture${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" "$(lines_for "$repo" comment_posture)"
check 'every key gets a line' '8' "$(bash "$SUT" "$repo" | wc -l | tr -d ' ')"
check 'the skill-local entry point prints the same lines' "$(bash "$SUT" "$repo")" "$(bash "$ENTRY" "$repo")"
check 'an unset lint level names the team file only' \
  "comment_lint${TAB}unset${TAB}no valid value in $TEAM" "$(lines_for "$repo" comment_lint)"
check 'an unset allow list prints nothing' '' "$(bash "$SUT" --list comment_lint_allow "$repo")"

for level in off report block; do
  repo="$(repo_with "comment_lint: $level"$'\n' -)"
  check "the lint level $level is read" "comment_lint${TAB}${level}${TAB}$TEAM" "$(lines_for "$repo" comment_lint)"
done

repo="$(repo_with $'comment_lint: warn\n' -)"
check 'a lint level outside off, report and block is invalid' \
  "comment_lint${TAB}invalid${TAB}$TEAM: warn"$'\n'"comment_lint${TAB}unset${TAB}no valid value in $TEAM" \
  "$(lines_for "$repo" comment_lint)"

repo="$(repo_with $'comment_adr_dir: docs/decisions\n' $'comment_adr_dir: docs/mine\n')"
check 'the ADR folder is read from the team file only' \
  "comment_adr_dir${TAB}docs/decisions${TAB}$TEAM" "$(lines_for "$repo" comment_adr_dir)"

for escape in /etc ../outside docs/../..; do
  repo="$(repo_with "comment_adr_dir: $escape"$'\n' -)"
  check "the ADR folder $escape outside the repository is invalid" \
    "comment_adr_dir${TAB}invalid${TAB}$TEAM: $escape"$'\n'"comment_adr_dir${TAB}unset${TAB}no valid value in $TEAM" \
    "$(lines_for "$repo" comment_adr_dir)"
done

repo="$(repo_with $'comment_lint: report\n' $'comment_lint: off\n')"
check 'a personal override cannot change the lint level' \
  "comment_lint${TAB}report${TAB}$TEAM" "$(lines_for "$repo" comment_lint)"

repo="$(repo_with $'comment_lint_allow:\n  - "^test-scope:"\n  - \'^shellcheck \'\n' $'comment_lint_allow:\n  - "^personal"\n')"
check 'the allow list is read from the team file, one item per line' \
  '^test-scope:'$'\n''^shellcheck ' "$(bash "$SUT" --list comment_lint_allow "$repo")"
check 'the allow list is no key line' '' "$(lines_for "$repo" comment_lint_allow)"

repo="$(repo_with $'comment_lint_allow:\n  - a\ncomment_lint_allow:\n  - b\n' -)"
check 'an allow list in a file that does not parse is empty' '' "$(bash "$SUT" --list comment_lint_allow "$repo" 2>/dev/null)"
bash "$SUT" --list comment_posture "$repo" >/dev/null 2>&1
check '--list with a key that is no list is a usage error' '2' "$?"
check '--help prints the usage' '1' "$(bash "$SUT" --help | grep -c '^Usage: comment-settings.sh')"

installed="$(mktemp -d "$TMP/installed.XXXXXX")"
cp "$SUT" "$HERE/../lib/parse-concern-value.sh" "$HERE/../lib/yaml-subset.awk" "$HERE/../lib/resolve-convention-home.sh" "$installed/"
repo="$(repo_with $'comment_lint: block\n' -)"
check 'an installed copy finds its lib beside itself' \
  "comment_lint${TAB}block${TAB}$TEAM" "$(bash "$installed/comment-settings.sh" "$repo" | grep "^comment_lint${TAB}")"

repo="$(repo_with $'comment_posture: necessary\ncomment_edit_scope: files\n' -)"
check 'the team posture is read' "comment_posture${TAB}necessary${TAB}$TEAM" "$(lines_for "$repo" comment_posture)"
check 'the team edit scope is read' "comment_edit_scope${TAB}files${TAB}$TEAM" "$(lines_for "$repo" comment_edit_scope)"

repo="$(repo_with $'comment_posture: necessary\n' $'comment_posture: explanatory\n')"
check 'the personal override beats the team file' \
  "comment_posture${TAB}explanatory${TAB}$PERSONAL" "$(lines_for "$repo" comment_posture)"

repo="$(repo_with $'comment_posture: necessary\n' $'comment_posture: strip\n')"
check 'an invalid personal override is named and the team value stands' \
  "comment_posture${TAB}invalid${TAB}$PERSONAL: strip"$'\n'"comment_posture${TAB}necessary${TAB}$TEAM" \
  "$(lines_for "$repo" comment_posture)"

for legacy in strict balanced conservative aggressive; do
  repo="$(repo_with "comment_posture: $legacy"$'\n' -)"
  check "the old posture $legacy is passed on for SKILL.md to map" \
    "comment_posture${TAB}${legacy}${TAB}$TEAM" "$(lines_for "$repo" comment_posture)"
done

repo="$(repo_with $'class_c_max_lines: 41\n' -)"
check 'a line budget above 40 is invalid' \
  "class_c_max_lines${TAB}invalid${TAB}$TEAM: 41"$'\n'"class_c_max_lines${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
  "$(lines_for "$repo" class_c_max_lines)"

repo="$(repo_with $'class_c_max_lines: 3\nencode_constraints_unattended: true\n' -)"
check 'a line budget of 3 is read' "class_c_max_lines${TAB}3${TAB}$TEAM" "$(lines_for "$repo" class_c_max_lines)"
check 'the encode pre-approval is read' \
  "encode_constraints_unattended${TAB}true${TAB}$TEAM" "$(lines_for "$repo" encode_constraints_unattended)"

repo="$(repo_with $'comment_posture: none\ncomment_posture: necessary\n' -)"
check 'a key set twice is invalid' \
  "comment_posture${TAB}invalid${TAB}$TEAM: set 2 times"$'\n'"comment_posture${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
  "$(lines_for "$repo" comment_posture)"

repo="$(repo_with $'comment_keep_list: default\n' -)"
check 'the shipped keep list is selectable' \
  "comment_keep_list${TAB}default${TAB}$TEAM" "$(lines_for "$repo" comment_keep_list)"

repo="$(repo_with - $'comment_keep_list: docs/comment-keeps.md\n')"
check 'a keep-list path naming no file is invalid' \
  "comment_keep_list${TAB}invalid${TAB}$PERSONAL: docs/comment-keeps.md"$'\n'"comment_keep_list${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
  "$(lines_for "$repo" comment_keep_list)"
printf -- '- a comment naming the vendor limit it works within\n' >"$repo/docs/comment-keeps.md"
check 'a keep-list path naming a repository file is read' \
  "comment_keep_list${TAB}docs/comment-keeps.md${TAB}$PERSONAL" "$(lines_for "$repo" comment_keep_list)"

for escape in /etc/passwd ../outside.md docs/../../outside.md; do
  repo="$(repo_with "comment_keep_list: $escape"$'\n' -)"
  printf 'x\n' >"$repo/../outside.md"
  check "the keep-list path $escape outside the repository is invalid" \
    "comment_keep_list${TAB}invalid${TAB}$TEAM: $escape"$'\n'"comment_keep_list${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
    "$(lines_for "$repo" comment_keep_list)"
done

repo="$(repo_with $'comment_keep_list: docs/keeps.md\n' -)"
printf 'x\n' >"$TMP/outside.md"
ln -s "$TMP/outside.md" "$repo/docs/keeps.md"
check 'a keep-list path that is a symlink is invalid' \
  "comment_keep_list${TAB}invalid${TAB}$TEAM: docs/keeps.md"$'\n'"comment_keep_list${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
  "$(lines_for "$repo" comment_keep_list)"

repo="$(repo_with $'comment_keep_list: linked/keeps.md\n' -)"
mkdir -p "$TMP/outside-dir"
printf 'x\n' >"$TMP/outside-dir/keeps.md"
ln -s "$TMP/outside-dir" "$repo/linked"
check 'a keep-list path through a symlinked directory is invalid' \
  "comment_keep_list${TAB}invalid${TAB}$TEAM: linked/keeps.md"$'\n'"comment_keep_list${TAB}unset${TAB}no valid value in $TEAM or $PERSONAL" \
  "$(lines_for "$repo" comment_keep_list)"

keep_list_in() { (cd "$1" && bash "$SUT" --keep-list "$2" 2>/dev/null); }
repo="$(repo_with - -)"
printf -- '- a unit annotation\n' >"$repo/docs/comment-keeps.md"
check 'a userConfig keep-list path naming a repository file is read' \
  "comment_keep_list${TAB}docs/comment-keeps.md${TAB}userConfig" "$(keep_list_in "$repo/docs" docs/comment-keeps.md)"
check 'a userConfig keep-list path outside the repository is invalid' \
  "comment_keep_list${TAB}invalid${TAB}userConfig: ../outside.md" "$(keep_list_in "$repo" ../outside.md)"
ln -s "$TMP/outside.md" "$repo/docs/linked.md"
check 'a userConfig keep-list path that is a symlink is invalid' \
  "comment_keep_list${TAB}invalid${TAB}userConfig: docs/linked.md" "$(keep_list_in "$repo" docs/linked.md)"
check 'a userConfig keep-list check outside a git working tree is invalid' \
  "comment_keep_list${TAB}invalid${TAB}userConfig: docs/comment-keeps.md (not in a git working tree)" \
  "$(keep_list_in "$(mktemp -d "$TMP/plain.XXXXXX")" docs/comment-keeps.md)"
bash "$SUT" --keep-list >/dev/null 2>&1
check '--keep-list without a value is a usage error' '2' "$?"

bound_repo() {
  local d
  d="$(mktemp -d "$TMP/bound.XXXXXX")"
  git -C "$d" init -q
  mkdir -p "$d/config/team"
  printf '<!-- BEGIN GENERATED: convention-home -->\n%s\n<!-- END GENERATED: convention-home -->\n' "$1" >"$d/AGENTS.md"
  printf 'comment_posture: necessary\ncomment_edit_scope: files\n' >"$d/config/team/code-tidying.yaml"
  printf 'comment_edit_scope: diff\n' >"$d/config/team/code-tidying.local.yaml"
  printf '%s\n' "$d"
}

repo="$(bound_repo "Team conventions live in \`config/team\`.")"
check 'a bound home supplies the team layer' \
  "comment_posture${TAB}necessary${TAB}config/team/code-tidying.yaml" "$(lines_for "$repo" comment_posture)"
check 'a bound home supplies the personal override' \
  "comment_edit_scope${TAB}diff${TAB}config/team/code-tidying.local.yaml" "$(lines_for "$repo" comment_edit_scope)"

repo="$(bound_repo "Team conventions live in \`config/missing\`.")"
check 'a broken pointer leaves the layers out' \
  "comment_posture${TAB}unset${TAB}the convention-home pointer is broken" "$(lines_for "$repo" comment_posture)"

repo="$(repo_with $'comment_posture: necessary\n' -)"
printf '<!-- BEGIN GENERATED: convention-home -->\ndeclined\n<!-- END GENERATED: convention-home -->\n' >"$repo/AGENTS.md"
check 'a declined home reads docs/conventions' \
  "comment_posture${TAB}necessary${TAB}$TEAM" "$(lines_for "$repo" comment_posture)"

outside="$(mktemp -d "$TMP/plain.XXXXXX")"
check 'outside a git working tree the layers do not apply' \
  "comment_posture${TAB}unset${TAB}not in a git working tree" "$(lines_for "$outside" comment_posture)"

if ((fails > 0)); then
  printf '%d check(s) failed\n' "$fails" >&2
  exit 1
fi
echo "all checks passed"
