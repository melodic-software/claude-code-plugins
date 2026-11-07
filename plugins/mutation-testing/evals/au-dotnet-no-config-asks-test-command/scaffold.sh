#!/usr/bin/env bash
# A .NET repo with no mutation-testing config whose feature branch caps the discount.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-dotnet.sh" unconfigured
