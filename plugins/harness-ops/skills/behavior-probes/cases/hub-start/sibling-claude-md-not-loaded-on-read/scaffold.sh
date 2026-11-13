#!/usr/bin/env bash
set -euo pipefail
w="${PROBE_WORKDIR:?set by probe.py}"
bash "${PROBE_LIB:?set by probe.py}/hub-layout.sh" "$w"
bash "$PROBE_LIB/instructions-probe.sh" "$w"
