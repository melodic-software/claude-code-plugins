#!/usr/bin/env bash
# A fixture skill and a 16-query probe set. skill_dir is the absolute SKILL.md path,
# so it resolves whether or not the staged plugin sits inside a git repository.
set -euo pipefail
mkdir -p skills/release-notes probes
cat >skills/release-notes/SKILL.md <<'EOF'
---
name: release-notes
description: "Draft release notes from merged pull requests, grouped by change type. Use when: 'write release notes', 'draft the changelog for this release', 'summarize what shipped'."
disable-model-invocation: false
---

## Steps

1. List the merged pull requests since the last tag.
2. Group them under Added, Changed and Fixed.
EOF
cat >probes/release-notes.json <<EOF
{
  "skill": "fixture:release-notes",
  "plugin": "fixture",
  "skill_dir": "$PWD/skills/release-notes/SKILL.md",
  "competitors": [],
  "queries": [
    {"id": "pos-train-01", "split": "train", "expect_trigger": true, "request": "write up what changed since v1.4 for the announcement"},
    {"id": "pos-train-02", "split": "train", "expect_trigger": true, "request": "draft the changelog entry for this version"},
    {"id": "pos-train-03", "split": "train", "expect_trigger": true, "request": "which merged pull requests go in the notes, grouped"},
    {"id": "pos-train-04", "split": "train", "expect_trigger": true, "request": "summarize what shipped in the sprint"},
    {"id": "neg-train-01", "split": "train", "expect_trigger": false, "request": "fix the failing unit test in the parser"},
    {"id": "neg-train-02", "split": "train", "expect_trigger": false, "request": "rename this variable to something clearer"},
    {"id": "neg-train-03", "split": "train", "expect_trigger": false, "request": "why is the build slow on CI"},
    {"id": "neg-train-04", "split": "train", "expect_trigger": false, "request": "draft a description for my merged pull request"},
    {"id": "pos-val-01", "split": "validation", "expect_trigger": true, "request": "prepare notes for the release going out Friday"},
    {"id": "pos-val-02", "split": "validation", "expect_trigger": true, "request": "anything new for customers this month"},
    {"id": "pos-val-03", "split": "validation", "expect_trigger": true, "request": "what shipped since the last tag, as release notes"},
    {"id": "pos-val-04", "split": "validation", "expect_trigger": true, "request": "turn these pull requests into a changelog"},
    {"id": "neg-val-01", "split": "validation", "expect_trigger": false, "request": "set up the database migration"},
    {"id": "neg-val-02", "split": "validation", "expect_trigger": false, "request": "review this diff for security bugs"},
    {"id": "neg-val-03", "split": "validation", "expect_trigger": false, "request": "how do I squash my commits"},
    {"id": "neg-val-04", "split": "validation", "expect_trigger": false, "request": "format the markdown tables in the docs"}
  ]
}
EOF
