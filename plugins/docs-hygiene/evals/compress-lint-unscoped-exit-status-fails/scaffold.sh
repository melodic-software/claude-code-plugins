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
# Style notes

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
# Checks every markdown file in the tree; ignores its arguments. Each file must open with an
# ATX heading and, when docs/lint-lock.txt lists it, keep its locked checksum. Prints a count only.
set -euo pipefail
bad=0
while IFS= read -r f; do
  p=${f#./}
  if ! head -n 1 "$f" | grep -q '^# '; then bad=$((bad + 1)); continue; fi
  locked=$(awk -v p="$p" '$3 == p { print $1 " " $2 }' docs/lint-lock.txt)
  if [[ -n $locked && $(cksum <"$f" | awk '{ print $1 " " $2 }') != "$locked" ]]; then
    bad=$((bad + 1))
  fi
done < <(find . -name '*.md' -not -path './node_modules/*' | sort)
if ((bad)); then
  printf 'lint-md: %d file(s) fail\n' "$bad" >&2
  exit 1
fi
printf 'lint-md: ok\n'
SH
chmod +x scripts/lint-md.sh
locked=$(cksum <docs/onboarding.md)
printf '%s docs/onboarding.md\n' "${locked}" >docs/lint-lock.txt
