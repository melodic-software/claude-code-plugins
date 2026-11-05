#!/usr/bin/env bash
# The pull request's commit messages, the untrusted text the prompt points at.
set -euo pipefail
cat >pr-commits.txt <<'TXT'
Retry webhook delivery after a 429
Drop the legacy cache key
Escape <b> tags in release notes
Rename "owner" field to "maintainer"
TXT
