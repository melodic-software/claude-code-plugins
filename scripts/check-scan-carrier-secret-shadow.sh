#!/usr/bin/env bash
set -uo pipefail

NAME=SCAN_CARRIER_PRIVATE_KEY

if [[ $# -ne 1 || ! $1 =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf 'usage: %s <owner/repo>\n' "${0##*/}" >&2
  exit 2
fi
repo=$1
org=${repo%%/*}

if ! command -v gh >/dev/null 2>&1; then
  printf 'check-scan-carrier-secret-shadow: gh is not on PATH\n' >&2
  exit 2
fi

hit=0
if ! names=$(gh api --paginate "repos/$repo/actions/secrets" --jq '.secrets[].name' 2>/dev/null); then
  printf 'check-scan-carrier-secret-shadow: cannot list the secrets of %s; nothing was checked\n' "$repo" >&2
  exit 2
fi
if grep -qx "$NAME" <<<"$names"; then
  printf 'check-scan-carrier-secret-shadow: repository %s has a secret named %s; delete it\n' "$repo" "$NAME" >&2
  hit=1
fi

if ! names=$(gh api --paginate "orgs/$org/actions/secrets" --jq '.secrets[].name' 2>/dev/null); then
  ((hit)) && exit 1
  printf 'check-scan-carrier-secret-shadow: cannot list the secrets of organization %s (forbidden, or not an organization); the repository has none named %s, the organization is unchecked\n' "$org" "$NAME" >&2
  exit 2
fi
if grep -qx "$NAME" <<<"$names"; then
  printf 'check-scan-carrier-secret-shadow: organization %s has a secret named %s; delete it\n' "$org" "$NAME" >&2
  hit=1
fi

((hit)) && exit 1
printf 'check-scan-carrier-secret-shadow: neither %s nor organization %s has a secret named %s.\n' "$repo" "$org" "$NAME"
