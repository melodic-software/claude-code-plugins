#!/usr/bin/env bash
# A one-context repository with an existing glossary at docs/glossary.md.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/northwind-glossary.sh"
