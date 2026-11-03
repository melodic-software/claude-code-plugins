#!/usr/bin/env bash
# The fleet manifest the reach skill reads first: made-up hosts desk-01 and lap-01.
# Also the settings file the prompt names, in the workspace for the manifest's reason;
# a run never loads project configuration, so this file only gets read.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-manifest.sh"
[[ ! -e .claude/settings.json ]] || {
  echo "refusing: .claude/settings.json already exists" >&2
  exit 1
}
mkdir -p .claude
printf '{}\n' >.claude/settings.json
