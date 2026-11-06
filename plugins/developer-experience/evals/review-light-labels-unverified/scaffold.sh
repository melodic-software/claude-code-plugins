#!/usr/bin/env bash
# A small command-line tool to review in a repository whose default branch sets
# verification: light for the developer-experience plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/developer-experience.yaml
mkdir -p bin
cat >bin/greet <<'SH'
#!/usr/bin/env bash
echo "hello $1"
SH
chmod +x bin/greet

git add -A
git commit -q -m "chore: seed eval fixture"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
