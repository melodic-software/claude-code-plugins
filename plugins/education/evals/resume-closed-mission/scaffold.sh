#!/usr/bin/env bash
# Seeds the eval workspace with a sql-joins topic workspace whose mission the learner has closed.
set -euo pipefail

workspaces="$(dirname "${BASH_SOURCE[0]}")/../workspaces"
mkdir -p learning/topic
cp -R "$workspaces/sql-joins" learning/topic/
cp "$workspaces"/sql-joins-later-records/*.md learning/topic/sql-joins/learning-records/
mission=learning/topic/sql-joins/MISSION.md
{
  head -n 1 "$workspaces/sql-joins/MISSION.md"
  printf '\nStatus: closed\n'
  tail -n +2 "$workspaces/sql-joins/MISSION.md"
} >"$mission"
