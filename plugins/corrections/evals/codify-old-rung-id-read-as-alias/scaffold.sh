#!/usr/bin/env bash
# A two-service repository whose CLAUDE.md still names the old `semgrep-rule` rung id and orders
# it first for dangerous calls. Its history holds a shell-string command in both services, each
# fixed in a later commit, so the mistake has occurrences to count.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p services/api/src services/worker .semgrep
cat >CLAUDE.md <<'EOF'
# media-pipeline

Two services share this repository: `services/api` (TypeScript) and `services/worker` (Python).

## Enforcement order

Dangerous-call rules live in `.semgrep/` as `semgrep-rule` checks, one rule covering both
services. For a dangerous call, walk the enforcement ladder in this order: `semgrep-rule`, then
`shared-helper`, then `instruction`.

Run `npm test` and `pytest` before committing.
EOF
cat >.semgrep/no-eval.yaml <<'EOF'
rules:
  - id: no-eval
    languages: [typescript, python]
    severity: ERROR
    message: Do not pass data to eval.
    pattern: eval(...)
EOF
cat >services/api/src/export.ts <<'EOF'
import { exec } from "node:child_process";

export const exportReport = (name: string) => exec(`pdftk reports/${name}.pdf output out/${name}.pdf`);
EOF
cat >services/worker/thumbs.py <<'EOF'
import subprocess


def thumbnail(path: str) -> None:
    subprocess.run(f"convert {path} -resize 128x128 {path}.thumb.png", shell=True, check=True)
EOF
git add .
git commit -q -m "feat: report export and thumbnail worker"

cat >services/api/src/export.ts <<'EOF'
import { execFile } from "node:child_process";

export const exportReport = (name: string) =>
  execFile("pdftk", [`reports/${name}.pdf`, "output", `out/${name}.pdf`]);
EOF
git commit -q -am "fix(api): run pdftk with execFile, not a shell string"

cat >services/worker/thumbs.py <<'EOF'
import subprocess


def thumbnail(path: str) -> None:
    subprocess.run(["convert", path, "-resize", "128x128", f"{path}.thumb.png"], check=True)
EOF
git commit -q -am "fix(worker): call convert with an argument list, not shell=True"

git checkout -q -b fix/Shell-Calls
