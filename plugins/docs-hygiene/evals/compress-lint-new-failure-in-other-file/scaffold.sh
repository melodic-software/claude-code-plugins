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

Use sentence case in headings. The onboarding page is the model for tone.
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
# ATX heading. A file listed in docs/refs.lock cites the page named beside it, and fails when
# that page's checksum no longer matches the one it was reviewed against; the failure names the
# citing file, never the cited page.
set -euo pipefail
status=0
while IFS= read -r f; do
  if ! head -n 1 "$f" | grep -q '^# '; then
    printf '%s: first line is not an ATX heading\n' "${f#./}" >&2
    status=1
  fi
done < <(find . -name '*.md' -not -path './node_modules/*' | sort)
while read -r citing cited sum size; do
  if [[ $(cksum <"$cited" | awk '{ print $1 " " $2 }') != "$sum $size" ]]; then
    printf '%s: cited page %s changed since review\n' "$citing" "$cited" >&2
    status=1
  fi
done <docs/refs.lock
((status)) || printf 'lint-md: ok\n'
exit "$status"
SH
chmod +x scripts/lint-md.sh
sum=$(cksum <docs/onboarding.md)
printf 'docs/style.md docs/onboarding.md %s\n' "${sum}" >docs/refs.lock
