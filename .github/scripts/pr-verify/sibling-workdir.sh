#!/usr/bin/env bash
# The driven session's working directory in pr-verify-capture.yml's sibling
# sandbox, run in the background by sibling-init.sh from its root-owned copy:
#
#   sibling-workdir.sh <ready-dir> <head> <workdir> <result> [<wait-seconds>]
#
# It waits until <ready-dir> exists, which the workflow makes once the head
# checkout has filled <head>, then clones <head> into the empty <workdir>,
# sharing the head's object store, and copies the head's remote-tracking refs
# so the default branch resolves there. A skill driven in <workdir> then has
# the pull request's files and whole history and can write beside them; the
# directory is on the sandbox's own tmpfs, so nothing outside reads it back.
# <result> gets {status, head}: ready with the commit checked out, failed with
# <workdir> emptied again, or timeout. It is written whole, by rename.
set -uo pipefail

ready=$1
head=$2
work=$3
result=$4
wait_s=${5:-1500}

report() {
  jq -n -c --arg status "$1" --arg head "${2-}" '{status: $status, head: $head}' >"$result.tmp" && mv -f -- "$result.tmp" "$result"
}

for ((i = 0; i < wait_s; i++)); do
  [[ -d $ready ]] && break
  sleep 1
done
if ! [[ -d $ready ]]; then
  report timeout
  exit 0
fi

if git clone --quiet --shared -- "$head" "$work" &&
  git -C "$work" fetch --quiet origin '+refs/remotes/origin/*:refs/remotes/origin/*'; then
  got=$(git -C "$work" rev-parse --verify HEAD 2>/dev/null)
  want=$(git -C "$head" rev-parse --verify HEAD 2>/dev/null)
  if [[ -n $got && $got == "$want" ]]; then
    report ready "$got"
    exit 0
  fi
fi
find "$work" -mindepth 1 -delete 2>/dev/null
report failed
