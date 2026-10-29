#!/usr/bin/env bash
set -euo pipefail
bash "${PROBE_LIB:?set by probe.py}/gh-stub.sh" "${PROBE_WORKDIR:?set by probe.py}"
