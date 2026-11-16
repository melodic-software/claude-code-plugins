#!/usr/bin/env bash
# Seeds the BOM importer repository the diagnosis-only case uses.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../diagnosis-only-stops-at-confirmed-hypothesis/scaffold.sh"
