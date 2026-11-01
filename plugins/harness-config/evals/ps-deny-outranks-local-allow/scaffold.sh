#!/usr/bin/env bash
# The quay repo with a project deny, a local allow for the same rule, and a boolean disableAutoMode.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" state-merge
