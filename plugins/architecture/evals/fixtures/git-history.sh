#!/usr/bin/env bash
# Sourced by scaffolds that need a git history: repo_init starts a repository on main, and
# commit_files appends one line to each named file and commits them together, so files passed
# to the same calls change in the same commits.
repo_init() {
  git init -q -b main
  git config user.name eval
  git config user.email eval@example.invalid
}

_history_line=0
commit_files() {
  local message="$1" file
  shift
  for file in "$@"; do
    mkdir -p "$(dirname "${file}")"
    _history_line=$((_history_line + 1))
    printf 'export const v%s = %s;\n' "${_history_line}" "${_history_line}" >>"${file}"
  done
  git add -A
  git commit -q -m "${message}"
}
