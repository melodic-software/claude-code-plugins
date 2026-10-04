#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/added-lines.sh, which detect.sh calls
# for `--added-since <base>`. The implementation stays single-source at the plugin
# root; changed-code-files.sh beside this file records why the skill-local path is
# the exercised shape.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/added-lines.sh" "$@"
