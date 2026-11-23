#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" repo
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/vendor-boards.sh" all-read
