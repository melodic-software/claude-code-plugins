#!/usr/bin/env bash
# A small retry scheduler whose repository sets an invalid explore_output value in
# docs/conventions/discovery.yaml.
set -euo pipefail

git init -q -b main .
mkdir -p src/retry tests docs/conventions
printf 'explore_output: storyboard\n' >docs/conventions/discovery.yaml
printf '%s\n' \
  'from .backoff import delay_for' \
  '' \
  '' \
  'def schedule(job, attempt, now):' \
  '    if attempt >= job["max_attempts"]:' \
  '        return None' \
  '    return now + delay_for(attempt)' >src/retry/scheduler.py
printf '%s\n' \
  'BASE_SECONDS = 2' \
  '' \
  '' \
  'def delay_for(attempt):' \
  '    return BASE_SECONDS * (2 ** attempt)' >src/retry/backoff.py
printf '%s\n' \
  'from src.retry.scheduler import schedule' \
  '' \
  '' \
  'def test_gives_up_after_max_attempts():' \
  '    assert schedule({"max_attempts": 3}, 3, 0) is None' >tests/test_scheduler.py
git add docs src tests
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "feat: retry scheduler"
