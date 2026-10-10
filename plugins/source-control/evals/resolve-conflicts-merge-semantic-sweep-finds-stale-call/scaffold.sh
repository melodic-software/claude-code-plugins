#!/usr/bin/env bash
# Mid-merge of main into feature with the one textual conflict already resolved and staged.
# main renamed format_user to render_user; feature added reports.py calling format_user.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git config rerere.enabled false

cat > users.py <<'PY'
def format_user(user):
    return f"{user['name']} <{user['email']}>"
PY
cat > profile.py <<'PY'
from users import format_user


def profile_header(user):
    return format_user(user)
PY
cat > test_profile.py <<'PY'
import unittest

from profile import profile_header


class ProfileTest(unittest.TestCase):
    def test_header_names_the_user(self):
        self.assertIn("Ana", profile_header({"name": "Ana", "email": "ana@example.invalid", "title": "Dr"}))


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "feat: user formatting"

git checkout -q -b feature
cat > profile.py <<'PY'
from users import format_user


def profile_header(user):
    return f"{user['title']} " + format_user(user)
PY
cat > reports.py <<'PY'
from users import format_user


def signup_report(users):
    return "\n".join(format_user(u) for u in users)
PY
cat > test_reports.py <<'PY'
import unittest

from reports import signup_report


class ReportTest(unittest.TestCase):
    def test_lists_each_user(self):
        out = signup_report([{"name": "Ana", "email": "ana@example.invalid"}])
        self.assertIn("Ana", out)


if __name__ == "__main__":
    unittest.main()
PY
git add .
git commit -q -m "feat: signup report and titled profile header" -m "Support asked for a daily signup list. Refs SUP-3."

git checkout -q main
sed -i 's/format_user/render_user/g' users.py profile.py
git add users.py profile.py
git commit -q -m "refactor: rename format_user to render_user" -m "The UI now renders users as HTML, so format was misleading. Refs UI-12."

git checkout -q feature
git merge main -q -m "Merge branch main into feature" >/dev/null 2>&1 || true
test -f .git/MERGE_HEAD
cat > profile.py <<'PY'
from users import render_user


def profile_header(user):
    return f"{user['title']} " + render_user(user)
PY
git add profile.py
test -z "$(git diff --name-only --diff-filter=U)"
