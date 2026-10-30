#!/usr/bin/env bash
# Seeds the same workspace as already-built-disconnected-scan, so the pair differs only in prompt.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../already-built-disconnected-scan/scaffold.sh"
