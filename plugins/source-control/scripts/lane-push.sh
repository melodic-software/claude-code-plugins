#!/usr/bin/env bash
# GENERATED from lib/lane-push.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# The only way an unattended lane pushes. It builds the push itself rather
# than trusting the checkout's remotes, environment or global config to point
# where the lane meant, so the push lands on github.com over https and
# authenticates with the same gh token whose login it checked.
#
#   lane-push.sh --login <identity> --repo <owner/repo> --branch <name>
#   lane-push.sh --login <identity> --repo <owner/repo> --pr <number>
#   lane-push.sh --login <identity> --check [--repo <owner/repo>] [--branch <name>]
#   (each form also takes --dir <checkout>)
#
# --repo with --branch pushes HEAD to that repository's branch. --repo with
# --pr reads the pull request there and pushes HEAD to its head repository and
# branch, a fork's included. --check runs every refusal but the push. It pushes
# the HEAD of --dir, else of the current directory.
#
# What it does:
#   - Builds the URL as https://github.com/<owner>/<repo>.git; never a remote
#     name, a branch's pushRemote or a caller URL. Owner, repository, branch,
#     login and number must match strict character allowlists, and the branch
#     must pass `git check-ref-format`.
#   - Resolves git and gh on PATH before entering --dir and refuses either
#     unless absolute, so a relative PATH entry cannot reach into the checkout.
#   - Drops every GIT_* variable the caller set, plus SSH_ASKPASS, BASH_ENV and
#     ENV, then sets GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1,
#     GIT_TERMINAL_PROMPT=0 and NETRC=/dev/null. git sets CURLOPT_NETRC and
#     asks a helper only when it has no username, so a netrc entry would
#     authenticate first; libcurl reads the file NETRC names before
#     $HOME/.netrc and, when HOME is empty or unset, the passwd home
#     (curl lib/netrc.c), so emptying HOME would not stop it. HOME is left
#     alone, so gh finds its config and keyring for both the login read and
#     the helper. git(1) ENVIRONMENT VARIABLES and git-config(1)
#     ENVIRONMENT list what git reads from the environment; every name there,
#     GIT_CONFIG_COUNT/KEY_<n>/VALUE_<n>, GIT_SSH_COMMAND, GIT_ASKPASS,
#     GIT_PROXY_COMMAND, GIT_EXEC_PATH, GIT_ALLOW_PROTOCOL and GIT_TRACE*
#     included, starts with GIT_ except SSH_ASKPASS (git-config(1)
#     core.askPass). GIT_CONFIG_PARAMETERS, which carries -c to child
#     processes, is undocumented and starts with GIT_ too.
#   - Refuses when the repository-local or worktree config holds a key that
#     survives the global and system scrub and can change where or as whom an
#     https push goes: url.*, include.*, includeIf.*, credential.*, http.*,
#     remote.*.vcs, or a remote.<name>.* whose name is not a plain remote name
#     (git looks a pushed URL up as a remote name).
#   - Pushes with these -c options (git-config(1); -c outranks every file):
#     credential.helper= resets the helper list (gitcredentials(7)), then
#     credential.helper=!'<gh>' auth git-credential adds gh by absolute path;
#     core.sshCommand=false; core.askPass=false so a helper miss cannot fall
#     back to another program; core.hooksPath=/dev/null; protocol.allow=never
#     with protocol.https.allow=always; http.extraHeader= and
#     push.pushOption= clear those lists. The flags --no-verify, --no-signed,
#     --no-follow-tags and --recurse-submodules=no keep the push to the one
#     ref (git-push(1)).
#   - Reads the acting login (GraphQL viewer, github.com) with the same gh in
#     the same environment the helper runs in, and refuses unless it is the
#     identity, compared case-insensitively.
#   - Refuses the target repository's default branch (read with gh on
#     github.com), named by --branch or as a PR's head, unless the target is a
#     fork of the base (its parent or network source), whose default branch
#     can be a fork PR's head. Repository names compare as GitHub
#     canonicalizes them, so a renamed repository's old name changes nothing.
#   - Pushes HEAD:refs/heads/<branch>, fast-forward only; it never forces.
#
# Not closed here: whoever can replace the gh or git binary, edit this
# script, or write the checkout's .git directory already runs code as the lane.
# A libcurl older than the release that reads NETRC ignores it. libcurl still
# honors proxy and CA variables (https_proxy, ALL_PROXY, SSL_CERT_FILE): they
# can redirect or intercept the push but supply no GitHub credential. The
# script mediates only lanes that call it; a lane that runs git push itself is
# held only by the credentials its host gives it (loop-lane convention).
#
# Exit: 0 pushed (or --check passed); 1 the push ran and failed; 2 refused,
# nothing pushed, with `lane-push: refused: <code>` on stderr. Codes: usage,
# bad-dir, bad-login, bad-repo, bad-branch, bad-pr, gh-missing, gh-path-unsafe,
# git-missing, git-path-unsafe, config-unreadable, local-config-url,
# local-config-include, local-config-credential, local-config-http,
# local-config-remote, head-unreadable, default-branch,
# default-branch-unreadable, login-unreadable, login-mismatch.
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

# Resolved before --dir is entered, so a relative PATH entry cannot reach into
# the checkout, and held to absolute paths.
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

# check_keys <scope>: refuse on any key of that config scope the scrub cannot
# reach. The listing's exit status rides in as the last record.
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

# A lane never pushes a repository's default branch, except a fork of the base
# repository (parent or network source), whose default branch can be a fork
# PR's head. Names are compared as GitHub canonicalizes them, so a renamed
# repository's old name changes nothing.
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
