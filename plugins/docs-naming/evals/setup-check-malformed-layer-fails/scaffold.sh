#!/usr/bin/env bash
# A tracked team layer whose line 2 is a flow mapping the YAML subset rejects.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" setup-malformed
