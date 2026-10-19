#!/usr/bin/env bash
# A Flask file-sharing app where each upload surface (the API, the form template and the CLI)
# states its own copy of the file-count limit. The Brief asks for a 25 MB per-file cap enforced by
# the API, shown in the web form and checked by the CLI. The obvious design follows the existing
# pattern and writes 25 MB into three files; the outcome graded is whether the design gives the cap
# one home that all three read.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p uploads/templates cli .work/upload-cap

cat >uploads/__init__.py <<'PY'
PY

cat >uploads/api.py <<'PY'
from pathlib import Path

from flask import Flask, abort, render_template, request

app = Flask(__name__)

MAX_FILES = 10
ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg"}


@app.get("/upload")
def upload_form():
    return render_template("upload.html")


@app.post("/upload")
def upload():
    files = request.files.getlist("files")
    if len(files) > MAX_FILES:
        abort(400, f"at most {MAX_FILES} files")
    for f in files:
        if Path(f.filename).suffix.lower() not in ALLOWED_EXTENSIONS:
            abort(400, "file type not allowed")
        f.save(Path("/srv/files") / f.filename)
    return {"saved": len(files)}
PY

cat >uploads/templates/upload.html <<'HTML'
<form method="post" enctype="multipart/form-data">
  <input type="file" name="files" multiple>
  <p class="hint">Up to 10 files: PDF, PNG or JPG.</p>
  <button>Upload</button>
</form>
HTML

cat >cli/upload_cmd.py <<'PY'
import sys
from pathlib import Path

import requests

MAX_FILES = 10
ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg"}


def main(paths: list[str]) -> int:
    if len(paths) > MAX_FILES:
        print(f"at most {MAX_FILES} files", file=sys.stderr)
        return 2
    for p in paths:
        if Path(p).suffix.lower() not in ALLOWED_EXTENSIONS:
            print(f"{p}: file type not allowed", file=sys.stderr)
            return 2
    files = [("files", open(p, "rb")) for p in paths]
    requests.post("http://localhost:5000/upload", files=files, timeout=30).raise_for_status()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PY

cat >.work/upload-cap/PLAN.md <<'MD'
# Upload size cap

## Brief

### Goal
No single uploaded file may exceed 25 MB.

### Constraints
- The cap is the same everywhere a user can upload.

### Acceptance criteria
- The API rejects a file over 25 MB with HTTP 413.
- The web upload form's hint tells the user the 25 MB cap before they pick files.
- The CLI refuses a file over 25 MB before sending anything.

### Captured assumptions
- Quality bar: internal
- Intent: second variant = speculative; existing structure: the API, the form template and the CLI each state their own upload limits; upstream: none
MD

git add .
git commit -q -m "feat: uploads with file count and type limits"
