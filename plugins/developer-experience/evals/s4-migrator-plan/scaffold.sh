#!/usr/bin/env bash
# Seeds the converged brackenfold fixture, the plugin arm's starting state for scenario S4.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" brackenfold converged
