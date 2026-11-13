#!/usr/bin/env bash
set -euo pipefail
printf 'PROBE_ENV_MARKER=probe-env-example-marker\n' >"${PROBE_WORKDIR:?set by probe.py}/.env.example"
