#!/usr/bin/env bash
set -euo pipefail
printf 'PROBE_ENV_MARKER=probe-env-marker\n' >"${PROBE_WORKDIR:?set by probe.py}/.env"
