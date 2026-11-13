#!/usr/bin/env bash
# The shared textkit fixture at verification: light.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/level-textkit.sh" light
