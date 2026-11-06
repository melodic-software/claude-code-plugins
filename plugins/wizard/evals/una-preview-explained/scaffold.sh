#!/usr/bin/env bash
# A drafted unattended script that backs up and removes the Debian-build distro, not yet approved.
# Refuses to overwrite an existing script.
set -euo pipefail
[[ ! -e retire-distro.ps1 ]] || { echo "refusing: retire-distro.ps1 already exists" >&2; exit 1; }
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/retire-distro.ps1" retire-distro.ps1
