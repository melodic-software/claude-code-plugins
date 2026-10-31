#!/usr/bin/env bash
# A repository whose tracked team layer docs/conventions/attribution.yaml sets an exclusion and a
# 90-day stamp window. No convention-home pointer, so the detectors read docs/conventions.
set -euo pipefail
git init -q -b main .
mkdir -p docs/conventions drafts
cat >docs/guide.md <<'MD'
# Contributor guide

Open a branch per change and run the test suite before asking for review.
MD
cat >drafts/ideas.md <<'MD'
# Ideas

Unreviewed notes.
MD
cat >docs/conventions/attribution.yaml <<'YAML'
excluded_paths:
  - "drafts/**"
stamp_expiry_days: 90
YAML
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
