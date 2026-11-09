#!/usr/bin/env bash
# PR 512 has an empty body, closes nothing and carries a title that states no goal, on the landed-change repository.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/gh-forge/reassess-landed-pr.sh" 512 "chore: update retry config"
