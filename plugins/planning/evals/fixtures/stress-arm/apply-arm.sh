#!/usr/bin/env bash
# Run by each st-* case's scaffold, in the eval workspace: writes the arm's plan_stress_test
# setting where /planning:plan resolves it and commits the seeded project.
set -euo pipefail

mkdir -p docs/conventions
cp "$(dirname "${BASH_SOURCE[0]}")/planning.yaml" docs/conventions/planning.yaml
git add .
git commit -q -m "chore: import project"
