#!/usr/bin/env bash
# Comment markers in lib/ and src/, an upstream citation, a markdown task list and a test that asserts on the marker text.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/work-items-a-repo.sh" comment-markers
