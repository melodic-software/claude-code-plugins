#!/usr/bin/env bash
# Seeds the same csv-report repository as te-codebase-no-grounding-asks.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../te-codebase-no-grounding-asks/scaffold.sh"
