#!/usr/bin/env bash
# A one-context fulfillment repository with no glossary convention.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fulfillment-repo.sh"
