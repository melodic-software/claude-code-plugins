#!/usr/bin/env bash
# git revert of the remember-me commit stopped on auth/session.py: a later security fix added a
# line beside the one being reverted.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

mkdir -p auth
: > auth/__init__.py
cat > auth/session.py <<'PY'
SESSION_TTL_HOURS = 12


def cookie_options():
    return {"httponly": True}
PY
cat > test_session.py <<'PY'
import unittest

from auth.session import SESSION_TTL_HOURS, cookie_options


class SessionTest(unittest.TestCase):
    def test_cookie_is_httponly(self):
        self.assertTrue(cookie_options()["httponly"])

    def test_default_ttl(self):
        self.assertEqual(SESSION_TTL_HOURS, 12)


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "feat(auth): session cookie"

sed -i 's/^SESSION_TTL_HOURS = 12$/SESSION_TTL_HOURS = 12\nREMEMBER_ME_TTL_HOURS = 720/' auth/session.py
git add auth/session.py
git commit -q -m "feat(auth): 30-day sessions for remember-me" -m "Users asked to stay signed in on their own devices. Refs AUTH-77."
REMEMBER=$(git rev-parse HEAD)

sed -i 's/^REMEMBER_ME_TTL_HOURS = 720$/REMEMBER_ME_TTL_HOURS = 720\nSESSION_COOKIE_NAME = "sid"/' auth/session.py
sed -i 's/return {"httponly": True}/return {"httponly": True, "secure": True}/' auth/session.py
cat >> test_session.py <<'PY'


class SecureCookieTest(unittest.TestCase):
    def test_cookie_is_secure(self):
        self.assertTrue(cookie_options()["secure"])
PY
git add auth/session.py test_session.py
git commit -q -m "fix(auth): mark the session cookie secure and name it" -m "The cookie went over plain HTTP on the staging redirect. Refs SEC-31."

git revert --no-edit "$REMEMBER" >/dev/null 2>&1 || true
test -f .git/REVERT_HEAD
grep -qx auth/session.py < <(git diff --name-only --diff-filter=U)
