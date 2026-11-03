#!/usr/bin/env bash
# Seeds the workspace, then applies this arm's plan_stress_test setting.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/seed.sh"
bash "$here/../fixtures/stress-arm/apply-arm.sh"
