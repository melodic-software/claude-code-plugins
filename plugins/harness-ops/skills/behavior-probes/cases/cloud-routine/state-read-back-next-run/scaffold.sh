#!/usr/bin/env bash
# A run id unique to this live run, so the read-back never matches an earlier run's comments.
set -euo pipefail
printf 'probe-%s-%s%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$RANDOM" "$RANDOM" \
  >"${PROBE_WORKDIR:?set by probe.py}/probe-id.txt"
