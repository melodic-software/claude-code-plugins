#!/usr/bin/env bash
# Make the working directory its own git top-level with no remote, so the
# record directory reads `local` and the run is not redirected before the
# clone. The eval home above it is a repository.
set -euo pipefail

git init -q
