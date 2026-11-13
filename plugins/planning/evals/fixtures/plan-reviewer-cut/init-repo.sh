#!/usr/bin/env bash
# Run by each plan-reviewer-cut-* scaffold after it writes the project files and the draft plan:
# commits the project on main with verification: standard, pushes it to a local bare origin, and
# moves to a feature branch.
#
#   init-repo.sh <branch>
#
# Each draft's phase headings carry the placeholder [STATUS]; this script sets it to the
# not-started status marker the plan skill expects.
set -euo pipefail

branch="$1"
printf '.work/\n__pycache__/\n' >.gitignore
mkdir -p docs/conventions
printf 'verification: standard\n' >docs/conventions/planning.yaml
for plan in .work/*/PLAN.md; do
  text="$(cat "$plan")"
  printf '%s\n' "${text//'[STATUS]'/[TODO]}" >"$plan"
done
git init -q -b main
git add .
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "chore: import project"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
git checkout -q -b "$branch"
