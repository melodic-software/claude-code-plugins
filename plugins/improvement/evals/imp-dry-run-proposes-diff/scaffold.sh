#!/usr/bin/env bash
# Seeds the workspace root as the invoice-service repository.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-invoice-service.sh"
