#!/usr/bin/env bash
# Seeds the same auth-middleware diff as qz-report-sections.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../qz-report-sections/scaffold.sh"
