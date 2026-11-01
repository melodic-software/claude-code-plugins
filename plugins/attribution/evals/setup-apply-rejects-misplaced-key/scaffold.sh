#!/usr/bin/env bash
# A team layer docs/conventions/attribution.yaml setting excluded_paths and stamp_expiry_days 90.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/setup-repo.sh"
