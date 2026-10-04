#!/usr/bin/env bash
# Stages the resumed history where go-faster reads it through EVAL_GO_FASTER_TRANSCRIPT.
set -euo pipefail

cp "$(dirname "$0")/ac1-seeded-test-wait.jsonl" go-faster-history.jsonl
