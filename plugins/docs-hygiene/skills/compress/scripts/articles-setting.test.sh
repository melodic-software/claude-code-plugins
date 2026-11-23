#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/articles-setting.sh"
REL="docs/conventions/docs-hygiene.yaml"

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
  if [[ "$1" != - ]]; then
    mkdir -p "$d/docs/conventions"
    printf '%s' "$1" >"$d/$REL"
  fi
  printf '%s\n' "$d"
}

TAB=$'\t'
read_in() { bash "$SUT" "$1" 2>/dev/null; }

check 'no file leaves the layer unset' "unset${TAB}no $REL" "$(read_in "$(repo_with -)")"
check 'a file without the key leaves the layer unset' "unset${TAB}compress_articles not set in $REL" \
  "$(read_in "$(repo_with $'# team settings\n')")"
check 'keep is read as keep' 'keep' "$(read_in "$(repo_with $'compress_articles: keep\n')")"
check 'cut is read as cut' 'cut' "$(read_in "$(repo_with $'compress_articles: cut\n')")"
check 'a quoted cut is read as cut' 'cut' "$(read_in "$(repo_with $'compress_articles: "cut"\n')")"
check 'a trailing comment is not part of the value' 'cut' \
  "$(read_in "$(repo_with $'compress_articles: cut  # chosen for agent docs\n')")"
check 'a schema comment line does not hide the key' 'keep' \
  "$(read_in "$(repo_with $'# yaml-language-server: $schema=x\ncompress_articles: keep\n')")"

check 'a value outside the list is invalid' "invalid${TAB}drop" \
  "$(read_in "$(repo_with $'compress_articles: drop\n')")"
check 'Keep in another case is invalid' "invalid${TAB}Keep" \
  "$(read_in "$(repo_with $'compress_articles: Keep\n')")"
check 'an empty value is invalid, not unset' "invalid${TAB}(no value)" \
  "$(read_in "$(repo_with $'compress_articles:\n')")"
check 'null is invalid' "invalid${TAB}null" "$(read_in "$(repo_with $'compress_articles: null\n')")"
check 'an empty quoted string is invalid' "invalid${TAB}\"\"" \
  "$(read_in "$(repo_with $'compress_articles: ""\n')")"
check 'a flow list is invalid' "invalid${TAB}[cut]" "$(read_in "$(repo_with $'compress_articles: [cut]\n')")"
check 'a block map is invalid' "invalid${TAB}(no value)" \
  "$(read_in "$(repo_with $'compress_articles:\n  default: cut\n')")"
check 'a key set twice is invalid' "invalid${TAB}set 2 times" \
  "$(read_in "$(repo_with $'compress_articles: keep\ncompress_articles: cut\n')")"
check 'a key set twice, once quoted, is invalid' "invalid${TAB}set 2 times" \
  "$(read_in "$(repo_with $'compress_articles: keep\n"compress_articles" : cut\n')")"
check 'a file that does not parse is invalid' "invalid${TAB}does not parse" \
  "$(read_in "$(repo_with $'compress_articles: "cut\n')")"
check 'a key the schema does not list leaves a valid value in force' 'cut' \
  "$(read_in "$(repo_with $'compress_articles: cut\nverbosity: high\n')")"
check 'a CRLF file reads its value' 'cut' "$(read_in "$(repo_with $'compress_articles: cut\r\n')")"
check 'a nested key of the same name is not the setting' "unset${TAB}compress_articles not set in $REL" \
  "$(read_in "$(repo_with $'other:\n  compress_articles: cut\n')")"

outside="$(mktemp -d "$TMP/plain.XXXXXX")"
check 'outside a git working tree the layer is unset' "unset${TAB}not in a git working tree" \
  "$(GIT_CEILING_DIRECTORIES="$TMP" read_in "$outside")"
home_repo="$(repo_with $'compress_articles: cut\n')"
check "a repository rooted at \$HOME is skipped" "unset${TAB}repository root is \$HOME or an ancestor of it" \
  "$(HOME="$home_repo" read_in "$home_repo")"
check "a repository rooted above \$HOME is skipped" "unset${TAB}repository root is \$HOME or an ancestor of it" \
  "$(HOME="$home_repo/sub/dir" read_in "$home_repo")"
check 'a sibling path sharing a prefix is not an ancestor' 'cut' \
  "$(HOME="${home_repo}x" read_in "$home_repo")"

hostile="$TMP/\$(touch pwned)"
mkdir -p "$hostile/docs/conventions"
git -C "$hostile" init -q
printf 'compress_articles: cut\n' >"$hostile/$REL"
check "a root path with \$(...) reads normally" 'cut' "$(cd "$TMP" && BASH_COMPAT=51 bash "$SUT" "$hostile" 2>/dev/null)"
check 'nothing in the root path ran' 'absent' "$([[ -e "$TMP/pwned" ]] && echo present || echo absent)"

bash "$SUT" a b >/dev/null 2>&1
check 'two arguments is a usage error' 2 "$?"

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all articles-setting checks passed'
