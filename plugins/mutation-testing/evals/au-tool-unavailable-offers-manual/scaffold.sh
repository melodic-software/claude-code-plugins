#!/usr/bin/env bash
# A .NET repo whose config names tool: stryker-net.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-dotnet.sh" stryker
