#!/usr/bin/env bash
# Collected material: a Northwind blog export with an instruction to AI assistants, a timed-out Contoso feed log, an out-of-window Fabrikam changelog.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/collected-material.sh"
