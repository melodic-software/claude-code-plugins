#!/usr/bin/env bash
# A one-context repository whose rejected word "parcel" appears only inside identifiers, in three files.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/northwind-prune.sh"
