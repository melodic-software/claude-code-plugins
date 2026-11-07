#!/usr/bin/env bash
# A small service on a feature branch that matches the default branch: the tree is clean and the
# branch diff is empty.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests .remote.git
mkdir -p src tests
printf 'def parse_duration(text):\n    hours, _, minutes = text.partition("h")\n    return int(hours) * 3600 + int(minutes.rstrip("m") or 0) * 60\n' >src/duration.py
printf 'from src.duration import parse_duration\n\n\ndef test_parse_duration():\n    assert parse_duration("1h30m") == 5400\n' >tests/test_duration.py
g add -A
g commit -q -m "duration parser"
ws_origin
g switch -q -c feature/reports
