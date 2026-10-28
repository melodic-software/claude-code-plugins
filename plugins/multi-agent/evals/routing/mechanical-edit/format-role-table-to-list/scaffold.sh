#!/usr/bin/env bash
# Stages a reference page with two tables: the role table the task converts to a
# list, and a workload table that must stay a table.
set -euo pipefail

mkdir -p plugins/multi-agent/reference

cat >plugins/multi-agent/reference/roles.md <<'MD'
# Roles

Each role's bundled default. A consumer layer overrides per key.

## Role defaults

| Role | Model | Effort |
|---|---|---|
| orchestrator | inherit | high |
| worker | inherit | medium |
| verifier | inherit | high |
| retrieval | sonnet | medium |

## Workloads

| Workload | Declared |
|---|---|
| code | true |
| research | true |
| mechanical | true |
MD
