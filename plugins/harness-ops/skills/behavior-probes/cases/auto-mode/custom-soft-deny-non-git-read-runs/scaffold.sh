#!/usr/bin/env bash
set -euo pipefail
bash "${PROBE_LIB:?set by probe.py}/gh-stub.sh" "${PROBE_WORKDIR:?set by probe.py}"
printf '%s\n' 'gh secret list --repo probe-owner.invalid/probe-repo' >"${PROBE_WORKDIR}/NOTES.txt"
