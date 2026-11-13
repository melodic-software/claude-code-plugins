#!/usr/bin/env bash
# The shared textkit fixture at verification: standard.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/level-textkit.sh" standard
