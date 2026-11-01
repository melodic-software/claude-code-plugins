#!/usr/bin/env bash
# The quay repo with instruction surfaces and two hooks, on an experiment branch with a modified tracked file.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" unhobble
git switch -q -c experiment/unhobble-opus-5-5
printf '# local tweak\n' >>src/quay/app.py
