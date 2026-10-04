#!/usr/bin/env bash
# Seeds the eval workspace with an in-progress sql-joins topic workspace.
set -euo pipefail

mkdir -p learning/topic
cp -R "$(dirname "${BASH_SOURCE[0]}")/../fixtures/sql-joins" learning/topic/
