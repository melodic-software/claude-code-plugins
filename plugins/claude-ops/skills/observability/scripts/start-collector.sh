#!/usr/bin/env bash
# Public facade — the skill's external contract surface for hooks/CI (per
# skill/encapsulation.md "scripts/ facade as a legal external-citation surface").
# Delegates to the private otel/ backend body; otel/ stays skill-internal.
set -euo pipefail
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_SCRIPT_DIR/../otel/$(basename "$0")" "$@"
