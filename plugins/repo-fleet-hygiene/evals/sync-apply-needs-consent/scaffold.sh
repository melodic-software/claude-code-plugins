#!/usr/bin/env bash
# Two made-up checkouts under ./fleet with local bare remotes: alpha clean on a feature branch,
# beta on main one commit behind its remote.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fleet-repos.sh" sync
