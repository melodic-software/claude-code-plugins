#!/usr/bin/env bash
# Stages the same project as k36-cart-total.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/../k36-cart-total/scaffold.sh"
