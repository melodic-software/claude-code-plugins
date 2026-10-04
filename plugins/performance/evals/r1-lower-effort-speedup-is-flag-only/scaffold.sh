#!/usr/bin/env bash
# Stages the resumed history where go-faster reads it through EVAL_GO_FASTER_TRANSCRIPT.
set -euo pipefail

cp "$(dirname "$0")/r1-lower-effort-speedup-is-flag-only.jsonl" go-faster-history.jsonl
