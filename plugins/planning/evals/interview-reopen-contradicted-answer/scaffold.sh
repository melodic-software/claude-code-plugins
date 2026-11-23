#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/api-rate-limit docs/platform
cat >docs/platform/redis.md <<'MD'
# Shared Redis

The shared Redis 7 instance holds web sessions only. Application keys of any other kind are not
allowed on it; request a dedicated instance from the platform team.
MD
cat >.work/api-rate-limit/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Open-question register

- Q1 | answered | round 1 | What problem does this solve? | a few partner integrations send bursts that slow the API for everyone
- Q2 | answered | round 1 | Who uses it? | partner developers calling the API with their keys
- Q3 | answered | round 2 | Where are the rate-limit counters stored? | in the existing shared Redis 7 instance
- Q4 | answered | round 2 | What limit applies? | 1,000 requests per minute per API key, as the partner terms promise
- Q5 | answered | round 2 | How are requests counted? | a Redis counter per key per minute window, expiring after the window; depends:: Q3
MD
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git add .
git commit -q -m "docs: platform redis policy"
