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
# Checks that each markdown file opens with an ATX heading; checks every .md file when given none.
set -euo pipefail
if (($# == 0)); then
  mapfile -t files < <(find . -name '*.md' -not -path './node_modules/*' | sort)
  set -- "${files[@]}"
fi
status=0
for f in "$@"; do
  if head -n 1 "$f" | grep -q '^# '; then
    printf 'lint-md: ok %s\n' "$f"
  else
    printf 'lint-md: %s: first line is not an ATX heading\n' "$f" >&2
    status=1
  fi
done
exit "$status"
SH
chmod +x scripts/lint-md.sh
