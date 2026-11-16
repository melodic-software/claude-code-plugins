#!/usr/bin/env bash
# Repository telemetry sink: runs the session-telemetry reference sink in this
# process. `source`, not `exec`, so no extra process starts; the sourced file
# resolves its own helpers from its own path.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.
# shellcheck source=../../plugins/session-telemetry/hooks/hook-telemetry-sink.sh
source "$HOOK_DIR/../../plugins/session-telemetry/hooks/hook-telemetry-sink.sh"
