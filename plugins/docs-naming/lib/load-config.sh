#!/usr/bin/env bash
# The root resolution and configuration load the docs-naming scripts share.
#
# Source this file. The caller defines die MESSAGE [CODE], so every message
# keeps the caller's prefix.
#
# resolve_git_root sets ROOT to the git toplevel of the working directory when
# ROOT is empty, then dies unless ROOT is a directory inside a git repository.
# load_config sets CONFIG from the file at CONFIG_FILE, or, with CONFIG_FILE
# empty, from the resolver at RESOLVER run for ROOT. cfg FILTER prints the jq
# FILTER's raw result over CONFIG.
#
# Executing this file prints that it must be sourced and exits 2.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'load-config.sh: source this file; it is not a command\n' >&2
  exit 2
fi

resolve_git_root() {
  if [[ -z "$ROOT" ]]; then
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
    [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
  fi
  [[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "'$ROOT' is not a git repository"
}

# shellcheck disable=SC2154  # CONFIG_FILE and RESOLVER are the caller's
load_config() {
  if [[ -n "$CONFIG_FILE" ]]; then
    [[ -r "$CONFIG_FILE" ]] || die "cannot read the configuration at $CONFIG_FILE"
    CONFIG="$(jq -e . "$CONFIG_FILE" 2>/dev/null | tr -d '\r')" || die "the configuration at $CONFIG_FILE is not valid JSON"
  else
    [[ -f "$RESOLVER" ]] || die "resolver missing at $RESOLVER"
    CONFIG="$(bash "$RESOLVER" resolve --root "$ROOT")" || exit 2
  fi
}

cfg() {
  printf '%s' "$CONFIG" | jq -r "$1" 2>/dev/null | tr -d '\r'
}
