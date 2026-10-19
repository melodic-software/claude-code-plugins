#!/usr/bin/env bash
# main holds a prototype upload service whose size cap is MAX_UPLOAD_MB in config.py. The branch adds
# an upload check and a form hint that each hardcode 25 instead of reading the constant. The base
# commit SHA is in .review-base.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
printf '.review-base\n' >>.git/info/exclude
mkdir -p app

cat >config.py <<'PY'
MAX_UPLOAD_MB = 25
PY

cat >app/__init__.py <<'PY'
PY

git add .
git commit -q -m "feat: upload size cap"
git rev-parse HEAD >.review-base
git checkout -q -b feat/upload-form

cat >app/upload.py <<'PY'
class UploadTooLarge(Exception):
    pass


def check_size(size_bytes):
    if size_bytes > 25 * 1024 * 1024:
        raise UploadTooLarge("file is larger than 25 MB")
PY

cat >app/form.py <<'PY'
def upload_hint():
    return "Files up to 25 MB."
PY

git add app
git commit -q -m "feat: upload check and form hint"
