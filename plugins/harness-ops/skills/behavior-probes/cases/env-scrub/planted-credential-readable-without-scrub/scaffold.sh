#!/usr/bin/env bash
set -euo pipefail
cp "${PROBE_LIB:?set by probe.py}/plant-check.py" "${PROBE_WORKDIR:?set by probe.py}/plant-check.py"
