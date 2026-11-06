#!/usr/bin/env bash
# An empty workspace: the case only checks that nothing is in the way of films/harbor.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/scaffold-guard.sh" films
