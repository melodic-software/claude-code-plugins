#!/usr/bin/env bash
# Make the working directory its own git top-level with no remote, so the session root
# (git rev-parse --show-toplevel, which base and head both use for a relative or default
# library_dir) is the workspace and not the eval home above it, which is a repository.
set -euo pipefail

git init -q
