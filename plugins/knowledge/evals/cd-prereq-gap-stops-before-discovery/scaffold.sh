#!/usr/bin/env bash
# Make the working directory its own git toplevel with no remote (the eval home
# above it is a repository). The work root is then this directory in both
# versions and its visibility reads local, so the run may write the phase
# checklist and goes on to the prerequisite check.
set -euo pipefail

git init -q
