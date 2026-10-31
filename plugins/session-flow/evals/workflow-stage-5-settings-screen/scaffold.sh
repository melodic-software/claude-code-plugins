#!/usr/bin/env bash
# A written PRD and a locked contract for a new user-facing settings screen, and no design section
# yet, so the next stage on the ladder is 5, Design.
set -euo pipefail

mkdir -p docs/prd
cat >docs/prd/notification-settings.md <<'EOF'
# PRD: notification settings screen

## Problem
Members get every notification by email and cannot turn any of them off, so they mute the sender.

## Users
Workspace members who receive more than ten notifications a day.

## Success metrics
- Muted-sender reports drop by half within a month of launch.
- Sixty percent of active members open the screen in its first two weeks.
EOF

cat >PLAN.md <<'EOF'
# Notification settings screen

## Brief

- Goal: members choose which notifications they get, and on which channel (email, in-app).
- Constraints: reuse the existing settings layout and the app's component library.
- Acceptance criteria: each notification type has an on/off switch per channel; changes save
  without a page reload; the screen works on a phone.
- Assumptions: the notification types are the ones the app sends today.
EOF
