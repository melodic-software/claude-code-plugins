#!/usr/bin/env bash
# Seeds the eval workspace with a sql-joins topic workspace whose records meet every success criterion.
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
mkdir -p learning/topic
cp -R "$fixtures/sql-joins" learning/topic/
cp "$fixtures"/sql-joins-later-records/*.md learning/topic/sql-joins/learning-records/
