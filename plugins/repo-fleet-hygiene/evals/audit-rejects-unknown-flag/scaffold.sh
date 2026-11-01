#!/usr/bin/env bash
# Two made-up checkouts under ./fleet with local bare remotes, so the bare path argument resolves.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-repos.sh" audit
