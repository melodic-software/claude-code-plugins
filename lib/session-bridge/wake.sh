#!/usr/bin/env bash
[[ -n "${1:-}" ]] || { echo "usage: wake.sh <data_dir>" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
control=$(sed -n 's/^CONTROL=//p' "$here/session-bridge.conf" 2>/dev/null | tr -d '\r')
[[ "$control" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "no valid CONTROL in $here/session-bridge.conf" >&2; exit 2; }
after=$(sed -n 's/^AFTER_APPLY=//p' "$here/session-bridge.conf" 2>/dev/null | tr -d '\r')
bash "$here/$control" --dir "$1" apply --file "$1/ops.json" || exit $?
if [[ "$after" =~ ^[a-z][a-z-]*$ ]]; then bash "$here/$control" --dir "$1" "$after" >&2 || true; fi
exec bash "$here/watch.sh" "$1"
