#!/usr/bin/env bash
# Seeds the workspace root as the example repository: a Bash standard, a report script that breaks
# two of its rules, and a documented check command, committed on main with no remote.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-example-scripts.sh"
