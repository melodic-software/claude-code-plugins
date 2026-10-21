#!/usr/bin/env bash
# A support-ticket app with a ticket model and no import path. The prompt locks a Brief and states
# the user's reason and direction in their own words, so the Brief's Goal carries them on its
# Intent and Vision lines, and the unstated tiebreak reads `none stated`.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/tickets

cat >src/tickets/model.py <<'PY'
from dataclasses import dataclass


@dataclass
class Ticket:
    name: str
    phone: str
    issue: str
    needs_review: bool = False
PY

cat >README.md <<'MD'
# Support desk

Internal ticketing for the support team. Tickets are created by hand from the web form.
MD

git add .
git commit -q -m "feat: ticket model"
