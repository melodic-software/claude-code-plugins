#!/usr/bin/env bash
# Seeds the bare tarnquill fixture into the workspace: no conventions file, no pointer line.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" tarnquill bare
