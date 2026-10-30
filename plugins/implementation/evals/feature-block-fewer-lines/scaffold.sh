#!/usr/bin/env bash
# Seeds a sandbox repository where phase 1's feature block, active_emails, is written but not yet
# committed. Its tests pass, but the block carries an empty else branch and an accumulator loop
# a comprehension replaces. The tests pin `is True` and `is not None`, so a shrink that loosens
# either check turns them red.
set -euo pipefail

git init -q
git checkout -q -b feat/active-emails
mkdir -p users tests .work/active-emails

: >users/__init__.py

cat >users/module.py <<'PY'
def display_name(user):
    return user.get("name", "").strip()
PY

cat >.work/active-emails/PLAN.md <<'MD'
# Active emails

## Brief

### Goal
The user module exposes the normalized emails of active users.

### Acceptance criteria
1. `active_emails(users)` returns the stripped, lower-cased email of every user whose `active` is `True`.
2. A user with no email is skipped.

## Plan

### Phase 1: active_emails
- `users/module.py`: add `active_emails(users)`.
- `tests/test_active_emails.py`: cover active, inactive, missing email, and normalization.
- **Sanity Check:** `python3 -m unittest discover tests` exits 0.

Approval: approved by the user in session.
MD

git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "feat: user display name"

cat >>users/module.py <<'PY'


def active_emails(users):
    result = []
    for user in users:
        if user.get("active") is True:
            email = user.get("email")
            if email is not None:
                normalized = email.strip().lower()
                result.append(normalized)
            else:
                pass
    return result
PY

cat >tests/test_active_emails.py <<'PY'
import unittest

from users.module import active_emails


class ActiveEmails(unittest.TestCase):
    def test_normalizes_active_emails(self):
        users = [{"active": True, "email": "  Ann@Example.COM "}]
        self.assertEqual(active_emails(users), ["ann@example.com"])

    def test_skips_inactive_and_truthy_non_true(self):
        users = [
            {"active": False, "email": "a@example.com"},
            {"active": 1, "email": "b@example.com"},
            {"email": "c@example.com"},
        ]
        self.assertEqual(active_emails(users), [])

    def test_skips_missing_email_keeps_empty_email(self):
        users = [
            {"active": True},
            {"active": True, "email": None},
            {"active": True, "email": "  "},
        ]
        self.assertEqual(active_emails(users), [""])


if __name__ == "__main__":
    unittest.main()
PY
