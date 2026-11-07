#!/usr/bin/env bash
# A committed team file with a comment addressed to the agent.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ux-team-repo.sh" embedded-comment
