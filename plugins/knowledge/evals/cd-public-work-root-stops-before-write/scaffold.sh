#!/usr/bin/env bash
# Make the working directory its own git toplevel (the eval home above it is a
# repository) with a github.com remote. With gh absent or signed out, as in the
# eval sandbox, the visibility check prints "unknown" for it, which the skill
# handles exactly as "public": stop before any write.
set -euo pipefail

git init -q
git remote add origin https://github.com/acme/open-tools.git
