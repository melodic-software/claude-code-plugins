#!/usr/bin/env bash
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" class-c.sh notes/dc-notes.md
git -c user.name=eval -c user.email=eval@example.invalid commit --amend -q -m "add fixtures" -m "Uses a 5 second timeout to stay under the load balancer's 6 second idle cutoff."
