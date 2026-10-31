#!/usr/bin/env bash
# Tracked markdown in docs/, a vendor/ tree and a linguist-vendored third_party/ tree.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/vendored-repo.sh"
