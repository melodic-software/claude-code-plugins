#!/usr/bin/env bash
# A git repository with a tracked docs/conventions/rendered-views.yaml setting artifact.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/view-settings.sh" team-artifact
