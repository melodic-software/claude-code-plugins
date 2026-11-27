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
Style notes

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
cat >.lintmdrc.json <<'JSON'
{
  "rules": ["first-line-heading"],
  "fix": true
}
JSON
cat >scripts/lint-md.sh <<'SH'
#!/usr/bin/env bash
# Checks that each markdown file opens with an ATX heading. Checks every .md file when given none.
# Reads .lintmdrc.json; when it sets "fix": true, rewrites a failing file so its first line becomes a heading.
set -euo pipefail
fix=0
if grep -Eq '"fix"[[:space:]]*:[[:space:]]*true' .lintmdrc.json; then
  fix=1
fi
if (($# == 0)); then
  while IFS= read -r f; do set -- "$@" "$f"; done < <(find . -name '*.md' -not -path './node_modules/*' | sort)
fi
status=0
for f in "$@"; do
  p=${f#./}
  if head -n 1 "$f" | grep -q '^# '; then
    printf 'lint-md: ok %s\n' "$p"
  elif ((fix)); then
    tmp=$(mktemp)
    { printf '# '; cat "$f"; } >"$tmp"
    mv "$tmp" "$f"
    printf 'lint-md: fixed %s\n' "$p"
  else
    printf 'lint-md: %s: first line is not an ATX heading\n' "$p" >&2
    status=1
  fi
done
exit "$status"
SH
chmod +x scripts/lint-md.sh
