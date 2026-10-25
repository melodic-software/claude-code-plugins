#!/usr/bin/env bash
# GENERATED from lib/session-bridge/wake.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# One wake: apply the ops Claude wrote, then re-arm the watcher. watch.sh prints this as "next".
#   bash wake.sh '<data_dir>'
# Runs the app's control script (CONTROL in session-bridge.conf beside this script) as
# `CONTROL --dir <data_dir> apply --file <data_dir>/ops.json`, then watch.sh on <data_dir>; the
# exit code and output are those of the failing apply, else of the watcher. When the conf names
# AFTER_APPLY (a control subcommand such as `ledger-check`), it runs as `CONTROL --dir <data_dir>
# <subcommand>` between the two, its output on stderr; its exit code does not stop the re-arm.
[[ -n "${1:-}" ]] || { echo "usage: wake.sh <data_dir>" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
control=$(sed -n 's/^CONTROL=//p' "$here/session-bridge.conf" 2>/dev/null | tr -d '\r')
[[ "$control" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "no valid CONTROL in $here/session-bridge.conf" >&2; exit 2; }
after=$(sed -n 's/^AFTER_APPLY=//p' "$here/session-bridge.conf" 2>/dev/null | tr -d '\r')
bash "$here/$control" --dir "$1" apply --file "$1/ops.json" || exit $?
if [[ "$after" =~ ^[a-z][a-z-]*$ ]]; then bash "$here/$control" --dir "$1" "$after" >&2 || true; fi
exec bash "$here/watch.sh" "$1"
