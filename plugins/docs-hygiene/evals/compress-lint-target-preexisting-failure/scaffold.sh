#!/usr/bin/env bash
set -euo pipefail

git init -q
mkdir -p docs scripts
cat >docs/onboarding.md <<'MD'
# Onboarding

Welcome to the team! This page is basically just here to really help you get started as quickly as possible.

## Your first day

In order to get access, you should probably ask your manager to perhaps add you to the `harbor-dev` group. It is important to note that access is granted within 24 hours of the request.

## Local setup

Honestly, the setup is really quite simple. You just need to run `make setup` from the repository root, and it will basically install everything that you need.

## Reviews

Every pull request must be approved by two reviewers before it is merged. Please do not merge your own pull request.
MD
cat >docs/style.md <<'MD'
# Style

<!-- owner: docs-team -->

Use sentence case in headings.
MD
cat >package.json <<'JSON'
{
  "name": "harbor",
  "private": true,
  "scripts": {
    "lint:md": "bash scripts/lint-md.sh"
  }
}
JSON
cat >scripts/lint-md.sh <<'SH'
#!/usr/bin/env bash
# Lints only the markdown files it is given: each must open with an ATX heading and carry an
# owner marker line. Each failure names its file and rule.
set -euo pipefail
if (($# == 0)); then
  printf 'usage: lint-md.sh FILE...\n' >&2
  exit 2
fi
status=0
for f in "$@"; do
  p=${f#"$PWD"/}
  p=${p#./}
  if ! head -n 1 "$f" | grep -q '^# '; then
    printf '%s: heading-style: first line is not an ATX heading\n' "$p" >&2
    status=1
  fi
  if ! grep -q '^<!-- owner: ' "$f"; then
    printf '%s: owner-marker: no owner marker line\n' "$p" >&2
    status=1
  fi
done
((status)) || printf 'lint-md: ok\n'
exit "$status"
SH
chmod +x scripts/lint-md.sh
