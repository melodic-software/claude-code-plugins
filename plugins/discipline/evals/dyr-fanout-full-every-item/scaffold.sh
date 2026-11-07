#!/usr/bin/env bash
# Seed the partner-gateway checkout the session's claims are checked against.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/dyr-gateway-seed.sh"
