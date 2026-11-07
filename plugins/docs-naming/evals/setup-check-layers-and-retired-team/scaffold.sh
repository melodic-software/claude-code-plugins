#!/usr/bin/env bash
# An old .claude/docs-hygiene.json team file with a file_names block and no team YAML.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" setup-retired-team
