#!/usr/bin/env bash
# Seeds the eval workspace with a sql-joins topic workspace whose records meet every success criterion.
set -euo pipefail

workspaces="$(dirname "${BASH_SOURCE[0]}")/../workspaces"
mkdir -p learning/topic
cp -R "$workspaces/sql-joins" learning/topic/
cp "$workspaces"/sql-joins-later-records/*.md learning/topic/sql-joins/learning-records/
