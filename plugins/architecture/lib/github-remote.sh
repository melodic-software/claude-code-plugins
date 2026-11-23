#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'github-remote.sh: source this file; it is not a command\n' >&2
  exit 2
fi

github_remote_path() {
  local url="${1-}" host rest scheme=0 result=1 had_nocase=0
  url="${url%/}"
  url="${url%.git}"
  if [[ "$url" == *://* ]]; then
    [[ "$url" == [Ff][Ii][Ll][Ee]://* ]] && return 1
    scheme=1
    url="${url#*://}"
  fi
  [[ "${url%%/*}" == *@* ]] && url="${url#*@}"
  host="${url%%[:/]*}"
  rest="${url#"$host"}"
  if [[ $scheme -eq 1 ]]; then
    [[ "$rest" =~ ^:[0-9]*/ ]] && rest="${rest#:*/}"
    [[ "$rest" == :* ]] && return 1
  else
    [[ "$rest" == :* ]] || return 1
    rest="${rest#:}"
  fi
  while [[ "$rest" == /* ]]; do
    rest="${rest#/}"
  done
  shopt -q nocasematch && had_nocase=1
  shopt -s nocasematch
  [[ "$host" == github.com || "$host" == www.github.com ]] && result=0
  [[ $had_nocase -eq 1 ]] || shopt -u nocasematch
  [[ $result -eq 0 && -n "$rest" ]] || return 1
  printf '%s' "$rest"
}

github_repo_name() {
  local path repo
  path="$(github_remote_path "${1-}")" || return 1
  repo="${path#*/}"
  repo="${repo%%/*}"
  [[ -n "$repo" && "$repo" != "$path" ]] || return 1
  printf '%s' "$repo"
}
