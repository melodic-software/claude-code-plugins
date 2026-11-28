#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'usage: collect-patch.sh <40-hex head SHA> <patch file> [<40-hex tree id>]' >&2
  exit 2
}
fail() {
  echo "collect-patch.sh: $1" >&2
  exit 1
}

[[ ($# -eq 2 || $# -eq 3) && -n $2 ]] || usage
head=$1
patch=$2
from=${3:-$head}
[[ $head =~ ^[0-9a-f]{40}$ && $from =~ ^[0-9a-f]{40}$ ]] || usage

rm -f -- "$patch"
work=$(pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/home"
: >"$scratch/config"
clean=(env -i PATH=/usr/bin:/bin HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/home"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$scratch/config" GIT_NO_REPLACE_OBJECTS=1)
"${clean[@]}" git init -q --bare --template= "$scratch/git" || fail 'could not make the scratch repository'
printf '%s\n' "$work/.git/objects" >"$scratch/git/objects/info/alternates"
g=("${clean[@]}" GIT_DIR="$scratch/git" GIT_WORK_TREE="$work" GIT_INDEX_FILE="$scratch/index"
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.untrackedCache=false)

"${g[@]}" cat-file -e "$head^{commit}" 2>/dev/null || fail "the head $head is not a commit here"
[[ $from == "$head" || $("${g[@]}" cat-file -t "$from" 2>/dev/null) == tree ]] || fail "$from is not a tree here"

paths=(':(top)' ':(top,exclude).lane')
stubs=(bunfig.toml package.json .npmrc .yarnrc .yarnrc.yml .gitmodules package-lock.json yarn.lock
  pnpm-lock.yaml .env .env.local .env.development .env.development.local .env.test .env.test.local
  .env.production .env.production.local)
for name in "${stubs[@]}"; do
  "${g[@]}" cat-file -e "$from:$name" 2>/dev/null && continue
  if [[ ! -L $work/$name && -f $work/$name && ! -s $work/$name ]]; then
    paths+=(":(top,exclude,literal)$name")
  elif [[ -L $work/$name || -e $work/$name ]]; then
    echo "collect-patch.sh: $name is not an empty file the head lacks, so no patch is written" >&2
    exit 3
  fi
done

"${g[@]}" read-tree "$from" || fail 'could not read the start tree into a scratch index'
"${g[@]}" add -A -- "${paths[@]}" || fail 'could not stage the working tree in the scratch index'
"${g[@]}" diff --cached --binary --full-index --no-color --no-ext-diff --no-textconv \
  -M100% --no-relative --submodule=short --src-prefix=a/ --dst-prefix=b/ -U3 "$from" -- "${paths[@]}" >"$patch" ||
  fail 'could not write the patch'

if [[ ! -s $patch ]]; then
  rm -f -- "$patch"
  printf 'state=empty\nsha256=\n'
  exit 0
fi
sum=$(sha256sum <"$patch")
printf 'state=written\nsha256=%s\n' "${sum%% *}"
