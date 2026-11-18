#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/rendered-views-repo.sh" diagram-target-excalidraw-file
