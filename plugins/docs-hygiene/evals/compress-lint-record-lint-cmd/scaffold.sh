#!/usr/bin/env bash
set -euo pipefail

git init -q
mkdir -p docs scripts docs/conventions/ecosystems
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
cat >docs/conventions/ecosystems/markdown.yaml <<'YAML'
globs: ["**/*.md"]
fix-cmd: "bash scripts/fix-md.sh <files>"
lint-cmd: "bash scripts/check-md.sh <files>"
YAML
cat >package.json <<'JSON'
{
  "name": "harbor",
  "private": true,
  "scripts": {
    "lint:md": "bash scripts/lint-md.sh"
  }
}
JSON
cat >scripts/check-md.sh <<'SH'
#!/usr/bin/env bash
# Checks that each markdown file given opens with an ATX heading.
set -euo pipefail
status=0
for f in "$@"; do
  if head -n 1 "$f" | grep -q '^# '; then
    printf 'check-md: ok %s\n' "$f"
  else
    printf 'check-md: %s: first line is not an ATX heading\n' "$f" >&2
    status=1
  fi
done
exit "$status"
SH
cat >scripts/fix-md.sh <<'SH'
#!/usr/bin/env bash
# Rewrites each markdown file given: strips trailing whitespace in place.
set -euo pipefail
for f in "$@"; do
  sed -i 's/[[:space:]]*$//' "$f"
done
SH
cat >scripts/lint-md.sh <<'SH'
#!/usr/bin/env bash
# Legacy markdown check, kept for an old CI job.
echo 'lint-md: retired, use the recorded lint command' >&2
exit 1
SH
chmod +x scripts/check-md.sh scripts/fix-md.sh scripts/lint-md.sh
