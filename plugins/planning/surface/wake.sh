#!/usr/bin/env bash
# One wake: apply the ops Claude wrote, then re-arm the watcher. watch.sh prints this as "next".
#   bash wake.sh '<data_dir>'
# Runs round.sh apply on <data_dir>/ops.json, then watch.sh on <data_dir>; the exit code and
# output are those of the failing apply, else of the watcher.
[[ -n "${1:-}" ]] || { echo "usage: wake.sh <data_dir>" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bash "$here/round.sh" --dir "$1" apply --file "$1/ops.json" && exec bash "$here/watch.sh" "$1"
