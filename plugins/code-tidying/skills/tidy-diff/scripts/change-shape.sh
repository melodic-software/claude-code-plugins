#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/change-shape.py, the token proof
# each comment deletion carries. The implementation stays single-source at the
# plugin root; ../../dissolve-comments/scripts/change-shape.sh records why the
# skill-local path is the shape a grant names.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/../../../scripts/change-shape.py" "$@"
