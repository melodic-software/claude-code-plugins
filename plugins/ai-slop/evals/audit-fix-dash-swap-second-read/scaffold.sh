#!/usr/bin/env bash
# Seeds an upgrade note with five "claim, em dash, elaboration" lines whose easy fix is a colon swap.
set -euo pipefail

mkdir -p docs
cat > docs/upgrade.md <<'MD'
# Upgrading the job runner to 3.0

The scheduler changed the most — it now hands each job to the least busy worker, so a queue of
500 jobs drains in about four minutes instead of eleven.

Retries got stricter — a failed job waits 30 seconds, then 60, then 120, and is marked dead
after the third retry.

Shutdown is safer — the new `--drain` flag stops accepting jobs and exits once the running ones
finish, so an operator can restart a node without losing work.

## Breaking changes

- One setting was renamed — `RUNNER_POOL` is now `RUNNER_WORKERS`, which defaults to 8.
- Large payloads now fail loudly — a job payload over 1 MB is rejected instead of truncated.

Taken together, these changes mark a pivotal step in the runner's evolving landscape.
MD
