#!/usr/bin/env bash
set -euo pipefail
git init -q
printf '%s\n' 'export function log(message) {' '  console.log(message); // eslint-disable-line no-console' '}' >log.js
printf '%s\n' 'TRACKER_URL = "https://tracker.example.invalid/projects/billing/issues?state=open&sort=updated"  # noqa: E501 a URL cannot be wrapped' >settings.py
git add log.js settings.py
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
