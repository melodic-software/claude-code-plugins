#!/usr/bin/env bash
# GENERATED from lib/lane-push.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
set -euo pipefail
export LC_ALL=C

refuse() {
  printf 'lane-push: refused: %s\n' "$1" >&2
  exit 2
}

login="" repo="" branch="" pr="" dir="" check=0 have_branch=0
while (($#)); do
  case $1 in
    --login | --repo | --branch | --pr | --dir)
      (($# >= 2)) || refuse usage
      case $1 in
        --login) login=$2 ;;
        --repo) repo=$2 ;;
        --branch) branch=$2 have_branch=1 ;;
        --dir) dir=$2 ;;
        *) pr=$2 ;;
      esac
      shift 2
      ;;
    --check)
      check=1
      shift
      ;;
    *) refuse usage ;;
  esac
done

owner_re='^[A-Za-z0-9][A-Za-z0-9-]{0,38}$'
name_re='^[A-Za-z0-9._-]{1,100}$'
branch_re='^[A-Za-z0-9._/-]{1,255}$'

require_repo() {
  local owner=${1%%/*} name=${1#*/}
  [[ $1 == */* && $owner =~ $owner_re && $name =~ $name_re && $name != . && $name != .. ]] ||
    refuse bad-repo
}

for v in "${!GIT_@}"; do unset "$v"; done
unset SSH_ASKPASS BASH_ENV ENV
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 NETRC=/dev/null

git_bin=$(type -P git) || refuse git-missing
[[ $git_bin == /* ]] || refuse git-path-unsafe
gh_bin=$(type -P gh) || refuse gh-missing
[[ $gh_bin == /* && $gh_bin != *[\'[:cntrl:]]* ]] || refuse gh-path-unsafe

[[ -z $dir ]] || cd -- "$dir" 2>/dev/null || refuse bad-dir
[[ $login =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?$ ]] || refuse bad-login
if ((check)); then
  [[ -z $pr ]] || refuse usage
else
  [[ -n $repo && (-n $pr || $have_branch == 1) && (-z $pr || $have_branch == 0) ]] || refuse usage
fi
[[ -z $repo ]] || require_repo "$repo"
[[ -z $pr ]] || [[ $pr =~ ^[1-9][0-9]{0,9}$ ]] || refuse bad-pr

require_branch() {
  [[ $1 =~ $branch_re && $1 != -* ]] || refuse bad-branch
  "$git_bin" check-ref-format "refs/heads/$1" || refuse bad-branch
}
((! have_branch)) || require_branch "$branch"

check_keys() {
  local keys key section rest sub name
  mapfile -d '' -t keys < <(
    rc=0
    "$git_bin" config "$1" --list --name-only -z 2>/dev/null || rc=$?
    printf 'rc=%s\0' "$rc"
  )
  [[ ${keys[-1]} == rc=0 ]] || refuse config-unreadable
  for key in "${keys[@]:0:${#keys[@]}-1}"; do
    section=${key%%.*} rest=${key#*.} sub=""
    name=$rest
    if [[ $rest == *.* ]]; then sub=${rest%.*} name=${rest##*.}; fi
    case ${section,,} in
      url) refuse local-config-url ;;
      include | includeif) refuse local-config-include ;;
      credential) refuse local-config-credential ;;
      http) refuse local-config-http ;;
      remote)
        if [[ -n $sub ]] && { ! [[ $sub =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] || [[ ${name,,} == vcs ]]; }; then
          refuse local-config-remote
        fi
        ;;
      *) ;;
    esac
  done
}
check_keys --local
if [[ $("$git_bin" config --local --bool --get extensions.worktreeConfig 2>/dev/null) == true ]]; then
  check_keys --worktree
fi

base=$repo
if [[ -n $pr ]]; then
  head=$("$gh_bin" pr view "$pr" -R "github.com/$repo" --json headRepository,headRefName \
    --jq '.headRepository.nameWithOwner, .headRefName') || refuse head-unreadable
  repo=${head%%$'\n'*} branch=${head#*$'\n'}
  [[ $head == *$'\n'* && $branch != *$'\n'* ]] || refuse head-unreadable
  require_repo "$repo"
  require_branch "$branch"
fi

if [[ -n $repo && -n $branch ]]; then
  mapfile -t target < <("$gh_bin" api --hostname github.com "repos/$repo" \
    --jq '.full_name, .default_branch, (.parent.full_name // ""), (.source.full_name // "")' ||
    echo FAILED)
  [[ ${#target[@]} -eq 4 && -n ${target[0]} && ${target[1]} =~ $branch_re ]] ||
    refuse default-branch-unreadable
  if [[ $branch == "${target[1]}" ]]; then
    is_fork=0
    if [[ -n $pr && -n ${target[2]}${target[3]} ]]; then
      canonical_base=$("$gh_bin" api --hostname github.com "repos/$base" --jq .full_name) ||
        refuse default-branch-unreadable
      [[ -n $canonical_base ]] || refuse default-branch-unreadable
      if [[ ${target[2],,} == "${canonical_base,,}" || ${target[3],,} == "${canonical_base,,}" ]]; then
        is_fork=1
      fi
    fi
    ((is_fork)) || refuse default-branch
  fi
fi

acting=$("$gh_bin" api --hostname github.com graphql -f 'query=query{viewer{login}}' \
  --jq .data.viewer.login) || refuse login-unreadable
[[ -n $acting ]] || refuse login-unreadable
[[ ${acting,,} == "${login,,}" ]] || refuse login-mismatch

if ((check)); then
  printf 'lane-push: check passed for %s\n' "$login"
  exit 0
fi

"$git_bin" \
  -c credential.helper= \
  -c "credential.helper=!'$gh_bin' auth git-credential" \
  -c core.sshCommand=false \
  -c core.askPass=false \
  -c core.hooksPath=/dev/null \
  -c protocol.allow=never \
  -c protocol.https.allow=always \
  -c http.extraHeader= \
  -c push.pushOption= \
  push --no-verify --no-signed --no-follow-tags --recurse-submodules=no \
  "https://github.com/$repo.git" "HEAD:refs/heads/$branch" || exit 1
