#!/bin/sh
# GENERATED from lib/node-or-skip.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Run node with these arguments and its exit code, or exit 0 silently when node
# is not on PATH. An exec-form SessionStart row ("command": "node") fails on
# every new session when node is missing, and harness-ops' node-notice row
# already tells the user, so a SessionStart row that launches through node runs
# this stub in the node-notice row's polyglot shape instead
# (docs/contracts/prerequisites/README.md#hook-notices):
#
#   sh "<root>/lib/node-or-skip.sh" <script> [args...]; ${PPID:+exit}; powershell -NoProfile -ExecutionPolicy Bypass -File "<root>/lib/node-or-skip.ps1" <script> [args...]
#
# stdin passes through to node untouched.
command -v node >/dev/null 2>&1 || exit 0
exec node "$@"
