#!/usr/bin/env bash
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=../../plugins/session-telemetry/hooks/hook-telemetry-sink.sh
source "$HOOK_DIR/../../plugins/session-telemetry/hooks/hook-telemetry-sink.sh"
