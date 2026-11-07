#!/usr/bin/env bash
# Seeds a git working tree whose team rendered-views file asks for medium: artifact.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
printf '%s\n' 'medium: artifact' >docs/conventions/rendered-views.yaml
