#!/usr/bin/env bash
# A git repository tracking discipline.yaml with lever_scope: non-trivial under a comment.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/su-repo.sh" existing
