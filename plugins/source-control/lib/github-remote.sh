# shellcheck shell=bash

github_repo_of() {
  local url="${1%/}"
  url="${url%.git}"
  case "${url,,}" in
    https://github.com/*) echo "${url:19}" ;;
    ssh://git@github.com/*) echo "${url:21}" ;;
    git@github.com:*) echo "${url:15}" ;;
    *) ;;
  esac
}

remote_of_repo() {
  local r repo
  for r in $(git remote); do
    repo=$(github_repo_of "$(git remote get-url "$r" 2>/dev/null)")
    if [[ -n "$repo" && "${repo,,}" == "${1,,}" ]]; then
      echo "$r"
      return 0
    fi
  done
}
