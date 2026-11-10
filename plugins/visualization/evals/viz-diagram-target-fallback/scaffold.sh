#!/usr/bin/env bash
# A git repository with an untracked, gitignored docs/conventions/visualization.local.yaml setting
# diagram_target: excalidraw, and no team file.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/rendered-views-repo.sh" diagram-target-file
