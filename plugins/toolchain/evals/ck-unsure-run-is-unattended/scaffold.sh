#!/usr/bin/env bash
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/../ck-unattended-stated-unresolved/scaffold.sh"
