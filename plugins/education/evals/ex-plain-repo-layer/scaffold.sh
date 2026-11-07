#!/usr/bin/env bash
# Seeds a git working tree whose docs/conventions/education.yaml sets explain_starting_rung: plain.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
printf '%s\n' 'explain_starting_rung: plain' >docs/conventions/education.yaml
