#!/usr/bin/env bash
# A one-context repository whose glossary holds an implementation entry and an unused term.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/northwind-prune.sh"
