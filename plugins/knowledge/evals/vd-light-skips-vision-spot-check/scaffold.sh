#!/usr/bin/env bash
# A watch slice at Phase 9 with a few synthesis images and contact sheets, in a repository whose
# default branch sets verification: light for the knowledge plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p slice/synthesis slice/key-frames/contact-sheets docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/knowledge.yaml
for name in architecture-diagram queue-retry-flow; do
  ffmpeg -y -loglevel error -f lavfi -i color=c=navy:s=640x360 -frames:v 1 "slice/synthesis/$name.png"
done
ffmpeg -y -loglevel error -f lavfi -i color=c=gray:s=640x360 -frames:v 1 slice/key-frames/contact-sheets/sheet-001.jpg
printf '# Demo talk\n\nA two-image watch slice used to exercise Phase 9.\n' >slice/README.md

git add -A
git commit -q -m "feat: demo watch slice"

# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
