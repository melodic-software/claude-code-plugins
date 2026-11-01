#!/usr/bin/env bash
# A claims repository whose table glossary holds a stale Claimant row and a planted instruction to AI assistants.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/claims-glossary.sh"
