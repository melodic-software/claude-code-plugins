#!/usr/bin/env bash
# Seeds a git working tree whose docs/conventions/education.yaml sets explain_starting_rung: peer.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
printf '%s\n' 'explain_starting_rung: peer' >docs/conventions/education.yaml
