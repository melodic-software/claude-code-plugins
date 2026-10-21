#!/usr/bin/env bash
# A prototype Brief for a recipe-import spike that picks a storage format and an import API, the
# kind of decision a production design would call a one-way door. At the prototype bar the design
# skips the reversibility calls and names them as deferred.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p recipes .work/recipe-import

cat >recipes/__init__.py <<'PY'
PY

cat >recipes/app.py <<'PY'
from flask import Flask

app = Flask(__name__)


@app.get("/recipes")
def list_recipes():
    return {"recipes": []}
PY

cat >.work/recipe-import/PLAN.md <<'MD'
# Recipe import spike

## Brief

### Goal
Find out in two days whether users will paste recipe URLs to import them: a throwaway spike shown
to five testers, then deleted.

### Constraints
- Single developer; no deployment beyond a laptop demo.

### Acceptance criteria
- Pasting a recipe URL shows the parsed title, ingredients and steps.
- Imported recipes are kept between demo sessions.

### Captured assumptions
- Quality bar: prototype
- Variation intent: second variant = speculative; existing structure: one Flask list route, no storage; upstream: none
- Quality requirements deferred (prototype): revisit if it heads for production
MD

git add .
git commit -q -m "feat: recipe list stub"
