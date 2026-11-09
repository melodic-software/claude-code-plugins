#!/usr/bin/env bash
# The continue case's PR, with its head on a fork: the verdict is still continue, and only an update could push.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../pull-request-reassess-continue/scaffold.sh" --fork contributor
