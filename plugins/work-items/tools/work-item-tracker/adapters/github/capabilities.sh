#!/usr/bin/env bash
# capabilities — emit the adapter manifest (CONTRACT.md "Capabilities manifest").
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: capabilities  (emits the adapter capabilities manifest as JSON)" "$@"

[[ $# -eq 0 ]] || wit_usage_error "capabilities takes no arguments"
jq -c . "$WIT_GH_ADAPTER_DIR/capabilities.json"
