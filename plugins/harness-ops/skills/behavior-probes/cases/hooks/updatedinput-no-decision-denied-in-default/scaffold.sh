#!/usr/bin/env bash
set -euo pipefail
bash "${PROBE_LIB:?set by probe.py}/commit-ready-repo.sh" "${PROBE_WORKDIR:?set by probe.py}"
