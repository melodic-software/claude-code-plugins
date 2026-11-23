#!/usr/bin/env bash

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
