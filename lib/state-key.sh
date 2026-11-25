#!/usr/bin/env bash
# ${CLAUDE_PLUGIN_DATA} is keyed to the plugin identifier only; this adds the project segment:
# https://code.claude.com/docs/en/plugins-reference#environment-variables
#
# Exit:
#   0  a successful derivation: every input reaches some rung
#   2  a bad argument, an unusable --root, or a PATH with neither sha256sum nor shasum

set -uo pipefail

CDPATH=

usage() {
  cat <<'EOF'
state-key.sh — per-project state key for ${CLAUDE_PLUGIN_DATA} writes.

Prints <repo-identity>/<worktree-discriminator> for a directory, so a report
persisted under the plugin data directory belongs to one project rather than to
the machine.

Usage:
  state-key.sh [--root <path>] [--explain] [--help]

  --root <path>  derive for that directory instead of the current one
  --explain      write the rung taken and its inputs to stderr

Exit: 0 on a derivation; 2 on a bad argument, an unusable --root, or no hash tool.
EOF
}

ROOT_ARG=""
EXPLAIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --root)
    if [[ $# -lt 2 ]]; then
      echo "ERROR: --root needs a path" >&2
      exit 2
    fi
    ROOT_ARG="$2"
    shift 2
    ;;
  --explain)
    EXPLAIN=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -n "$ROOT_ARG" ]]; then
  if [[ ! -d "$ROOT_ARG" ]]; then
    echo "ERROR: --root is not a directory: $ROOT_ARG" >&2
    exit 2
  fi
  cd "$ROOT_ARG" || exit 2
fi
cd -P . || exit 2

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256; }
else
  echo "ERROR: no sha256sum or shasum on PATH — cannot derive a state key" >&2
  exit 2
fi

hash_prefix() { printf '%s' "$2" | sha256 | cut -c1-"$1"; }

remote_name=$(git remote 2>/dev/null | tr -d '\r' | head -1)
remote=""
if [[ -n "$remote_name" ]]; then
  remote=$(git config --get "remote.${remote_name}.url" 2>/dev/null | tr -d '\r')
fi
root=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')

rung=""
if [[ -n "$remote" ]]; then
  identity=$(printf '%s' "$remote" |
    sed -e 's#^[a-z+]*://##' -e 's#^[^@/]*@##' -e 's#:#/#' -e 's#\.git$##' |
    tr '[:upper:]' '[:lower:]')
  if grep -qE '^[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)*$' <<<"$identity"; then
    rung="remote"
  else
    identity="remote/$(hash_prefix 12 "$remote")"
    rung="remote-hashed"
  fi
elif [[ -n "$root" ]]; then
  identity="local/$(hash_prefix 12 "$root")"
  rung="local"
else
  identity="nonrepo/$(hash_prefix 12 "$PWD")"
  rung="nonrepo"
fi

discriminator=$(hash_prefix 8 "${root:-$PWD}")

if [[ $EXPLAIN -eq 1 ]]; then
  {
    echo "rung:          $rung"
    echo "remote:        ${remote:-<none>}"
    echo "repo root:     ${root:-<not a git repository>}"
    echo "cwd:           $PWD"
    echo "identity:      $identity"
    echo "discriminator: $discriminator"
  } >&2
fi

printf '%s/%s\n' "$identity" "$discriminator"
