#!/usr/bin/env bash
set -uo pipefail

PUSH=0 CHECKOUT=""
while (($# > 0)); do
  case "$1" in
  --push)
    PUSH=1
    shift
    ;;
  --dir)
    if (($# < 2)) || [[ -z "$2" || -n "$CHECKOUT" ]]; then
      echo "error: --dir needs one value and is given once" >&2
      exit 1
    fi
    CHECKOUT="$2"
    shift 2
    ;;
  *) break ;;
  esac
done
CHECKOUT="${CHECKOUT:-.}"
if [[ ! -d "$CHECKOUT" ]]; then
  echo "error: --dir $(printf '%q' "$CHECKOUT") is not a directory" >&2
  exit 1
fi

BRANCH="${1:-}"
[[ -n "$BRANCH" ]] || BRANCH="$(git -C "$CHECKOUT" branch --show-current 2>/dev/null | tr -d '\r')"

remote_config() {
  local value
  value=$(git -C "$CHECKOUT" config "$1" 2>/dev/null | tr -d '\r')
  [[ "$value" == "." ]] && value=""
  printf '%s' "$value"
}

REMOTE=""
if [[ $PUSH -eq 1 ]]; then
  REMOTE=$(remote_config "branch.${BRANCH}.pushRemote")
  [[ -n "$REMOTE" ]] || REMOTE=$(remote_config "remote.pushDefault")
fi
[[ -n "$REMOTE" ]] || REMOTE=$(remote_config "branch.${BRANCH}.remote")

if [[ -z "$REMOTE" ]]; then
  mapfile -t REMOTES < <(git -C "$CHECKOUT" remote)
  if [[ ${#REMOTES[@]} -eq 0 ]]; then
    echo "error: cannot resolve a remote for branch '${BRANCH}': no branch.${BRANCH}.remote is set and no remotes are configured." >&2
    exit 1
  elif grep -qx origin < <(printf '%s\n' "${REMOTES[@]}"); then
    REMOTE=origin
  elif [[ ${#REMOTES[@]} -eq 1 ]]; then
    REMOTE="${REMOTES[0]}"
  else
    hint="Set branch.${BRANCH}.remote or add an 'origin' remote to disambiguate."
    [[ $PUSH -eq 1 ]] && hint="Set branch.${BRANCH}.pushRemote or remote.pushDefault (the push destination), or branch.${BRANCH}.remote, or add an 'origin' remote to disambiguate."
    echo "error: cannot resolve a remote for branch '${BRANCH}': no branch.${BRANCH}.remote, no 'origin', and ${#REMOTES[@]} other remotes exist (${REMOTES[*]}). ${hint}" >&2
    exit 1
  fi
fi

echo "$REMOTE"
