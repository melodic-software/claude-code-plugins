#!/usr/bin/env bash
# The quay repo with three project skills, one of them destructive with no gate.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" postures
