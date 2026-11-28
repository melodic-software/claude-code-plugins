#!/usr/bin/env bash
set -euo pipefail
awk 'BEGIN {
  n = split("amber cobalt delta ember fjord granite harbor indigo juniper kelp lantern meadow", w, " ")
  for (i = 0; i < 4200; i++) {
    printf "row %05d", i
    for (k = 0; k < 6; k++) printf " %s", w[(i * 7 + k * 3) % n + 1]
    printf "\n"
  }
}' >"${PROBE_WORKDIR:?set by probe.py}/filler.txt"
