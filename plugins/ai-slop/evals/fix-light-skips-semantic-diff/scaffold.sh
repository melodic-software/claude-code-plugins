#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` for ai-slop. docs/intro.md carries AI-writing tells for the fix flow to
# rewrite; at the standard level a fresh-context semantic-diff subagent would check each rewrite.
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions
printf 'verification: light\n' >docs/conventions/ai-slop.yaml

cat >docs/intro.md <<'MD'
# Introduction

In today's fast-paced world, this tool is a game-changer. It's not just a parser — it's a
testament to robust, seamless, and cutting-edge engineering. Let's delve into the rich tapestry
of its features.

The parser reads a config file and reports every key it does not recognize.
MD

printf '.work/\n' >.gitignore
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add intro doc"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
