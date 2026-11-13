#!/usr/bin/env bash
set -euo pipefail
w="${PROBE_WORKDIR:?set by probe.py}"
bash "${PROBE_LIB:?set by probe.py}/hub-layout.sh" "$w"
acme="$w/repos/github.com/acme"
printf 'Maintenance step: in %s, replace "status: one" with "status: two".\n' \
  "$acme/hub/README.md" >"$acme/hub/NOTES.txt"
