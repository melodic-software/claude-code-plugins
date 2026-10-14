#!/usr/bin/env bash
# A rotoscope work directory: 60 indexed drawings, traces for 12 and 40-50, and one brush override.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/ro-workdir.sh"
