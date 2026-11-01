#!/usr/bin/env bash
# A drafted unattended script that backs up and removes the Debian-build distro.
set -euo pipefail
cp "$(dirname "${BASH_SOURCE[0]}")/../fixtures/retire-distro.ps1" retire-distro.ps1
