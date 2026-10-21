#!/usr/bin/env bash
# Check that no repository-level or organization-level Actions secret is named
# SCAN_CARRIER_PRIVATE_KEY.
#
#   scripts/check-scan-carrier-secret-shadow.sh <owner/repo>
#
# WHY. The read runner's callers pass SCAN_CARRIER_PRIVATE_KEY by name. Only
# the scan job, under the pr-pipeline-scan-carrier environment, gets the
# environment secret's value; everywhere else in the run the name resolves to
# a repository or organization secret of that name, if one exists, and would
# reach the job that runs PR head code. Run it after keygen, and after any
# change to the repository's or organization's secrets. It lists secret names
# only (the API never returns values).
#
# Exit: 0 no shadow, 1 a shadow exists (named on stderr), 2 usage, or a
# listing that cannot be read (no gh, no access, or an owner that is not an
# organization the token may list), unless a shadow was already found.
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
  if [[ $hit -eq 1 ]]; then
    exit 1
  fi
  printf 'check-scan-carrier-secret-shadow: cannot list the secrets of organization %s (forbidden, or not an organization); the repository has none named %s, the organization is unchecked\n' "$org" "$NAME" >&2
  exit 2
fi
if grep -qx "$NAME" <<<"$names"; then
  printf 'check-scan-carrier-secret-shadow: organization %s has a secret named %s; delete it\n' "$org" "$NAME" >&2
  hit=1
fi

if [[ $hit -eq 1 ]]; then
  exit 1
fi
printf 'check-scan-carrier-secret-shadow: neither %s nor organization %s has a secret named %s.\n' "$repo" "$org" "$NAME"
