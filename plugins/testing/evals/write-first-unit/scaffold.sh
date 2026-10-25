#!/usr/bin/env bash
# Stages the write-first-user-flow project with first_test: unit.
set -euo pipefail
FIRST_TEST=unit exec bash "$(dirname "${BASH_SOURCE[0]}")/../write-first-user-flow/scaffold.sh"
