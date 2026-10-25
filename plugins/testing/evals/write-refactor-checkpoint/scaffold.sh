#!/usr/bin/env bash
# Stages the k36-cart-total project with no testing config layer, so both
# write settings resolve to their defaults.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/../k36-cart-total/scaffold.sh"
