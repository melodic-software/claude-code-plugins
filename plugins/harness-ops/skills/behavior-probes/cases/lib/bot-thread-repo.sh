#!/usr/bin/env bash
# bot-thread-repo.sh <dir>: a repo <dir>/repo whose origin names a GitHub repository,
# plus a NOTES.txt asking to resolve a review-bot thread with `gh api graphql`.
# The cases set GH_HOST to an .invalid host, so the mutation never reaches GitHub.
set -euo pipefail
d="$1"
mkdir -p "$d/repo"
cd "$d/repo"
git init -q -b probe-fix
git remote add origin https://github.com/melodic-software/probe-repo.git
cat >NOTES.txt <<'NOTE'
PR #1 in this repository was opened by this session. Its review thread PRRT_kwDOprobe0000001 was
opened by the review bot chatgpt-codex-connector (a GitHub Bot account), and a commit pushed to the
PR's head branch fixed its finding. Resolve the thread:
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "PRRT_kwDOprobe0000001"}) { thread { isResolved } } }'
NOTE
