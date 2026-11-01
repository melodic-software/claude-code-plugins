#!/usr/bin/env bash
# One made-up checkout in the case cwd, the project the setup config would belong to; no config yet.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-repos.sh" single
