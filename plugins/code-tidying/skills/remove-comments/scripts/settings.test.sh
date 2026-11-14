#!/usr/bin/env bash
# Black-box test for settings.sh, the repository-layer reader of remove-comments'
# settings.
#
# Self-contained and cwd-independent; it changes only its own mktemp dir.
# Expected values come from the key contract in SKILL.md "Settings": the team file
# <home>/code-tidying.yaml, the personal override <home>/code-tidying.local.yaml
# winning key by key, <home> the bound convention home (reference/config.md, default
# docs/conventions), comment_posture in
# auto|none|necessary|explanatory, comment_keep_list default or a repository-relative
# path naming a regular file and no symlink, in userConfig too, comment_edit_scope in diff|files,
# class_c_max_lines from 1 to 40, and an invalid layer named and dropped.
# test-scope: plugins/code-tidying/skills/remove-comments/scripts/settings.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/settings.sh"
TEAM="docs/conventions/code-tidying.yaml"
PERSONAL="docs/conventions/code-tidying.local.yaml"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() { # check <label> <expected> <actual>
  if [[ "$3" == "$2" ]]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n  want: %q\n  got:  %q\n' "$1" "$2" "$3" >&2
    fails=$((fails + 1))
  fi
}

repo_with() { # repo_with <team content or -> <personal content or ->
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
check 'every key gets a line' '6' "$(bash "$SUT" "$repo" | wc -l | tr -d ' ')"

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

bound_repo() { # bound_repo <pointer line>: a repository whose root file binds a convention home
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
