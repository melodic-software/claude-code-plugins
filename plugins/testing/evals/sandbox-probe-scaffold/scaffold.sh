#!/usr/bin/env bash
# Writes one file, so the only difference from sandbox-probe-plain is that a
# scaffold ran.
set -euo pipefail
printf 'probe\n' >probe.txt
