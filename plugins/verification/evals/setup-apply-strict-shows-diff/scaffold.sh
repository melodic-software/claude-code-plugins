#!/usr/bin/env bash
# A committed repository whose docs/conventions/verification.yaml holds proof_level: path.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/settings-repo.sh" proof-path
