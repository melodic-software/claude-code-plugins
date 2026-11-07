#!/usr/bin/env bash
# A committed repository whose docs/conventions/verification.yaml holds live_workers: 2.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/settings-repo.sh" workers-2
