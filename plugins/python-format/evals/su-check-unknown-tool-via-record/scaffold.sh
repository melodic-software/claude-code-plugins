#!/usr/bin/env bash
# A git repository with no Ruff config and a committed python record, matching the default
# branch, whose fix-cmd names a formatter the plugin ships no adapter for (blackish) and whose
# install-hint says how to get it. The tool is not installed, so check reports it missing.
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
mkdir -p src .claude/ecosystems
printf 'def main():\n    return 1\n' >src/app.py
cat >.claude/ecosystems/python.yaml <<'EOF'
globs: ["*.py", "*.pyi"]
build-cmd: null
test-cmd: null
check-cmd: null
fix-cmd: "blackish --quiet <files>"
install-hint: "pip install blackish"
EOF
git add .
git commit -q -m "chore: init"
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
