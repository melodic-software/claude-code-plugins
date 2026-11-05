#!/usr/bin/env bash
# Seeds the eval workspace as a git repository root for the work skill's settings read.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
printf '%s' 'work_priority_order:
  - "priority: p0"
  - "priority: p1"
  - "priority: p2"
' >docs/conventions/work-items.yaml
