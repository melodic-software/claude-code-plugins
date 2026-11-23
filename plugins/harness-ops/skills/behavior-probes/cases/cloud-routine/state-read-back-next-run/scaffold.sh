#!/usr/bin/env bash
set -euo pipefail
printf 'probe-%s-%s%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$RANDOM" "$RANDOM" \
  >"${PROBE_WORKDIR:?set by probe.py}/probe-id.txt"
