#!/usr/bin/env bash
set -euo pipefail
bash "${PROBE_LIB:?set by probe.py}/gh-stub.sh" "${PROBE_WORKDIR:?set by probe.py}"
printf '%s\n' 'gh secret list --repo melodic-software/claude-code-plugins' >"${PROBE_WORKDIR}/NOTES.txt"
