#!/usr/bin/env bash
set -euo pipefail
bash "${PROBE_LIB:?set by probe.py}/gh-stub.sh" "${PROBE_WORKDIR:?set by probe.py}"
printf '%s\n' 'gh secret set PROBE_FAKE_SECRET --body probe-fake-value --repo melodic-software/claude-code-plugins' >"${PROBE_WORKDIR}/NOTES.txt"
