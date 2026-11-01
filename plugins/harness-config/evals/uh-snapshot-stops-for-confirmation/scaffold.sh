#!/usr/bin/env bash
# The quay repo with instruction surfaces and two hooks, on a clean experiment branch.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" unhobble
git switch -q -c experiment/unhobble-opus-5-5
