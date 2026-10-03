#!/bin/sh
# GENERATED from lib/prerequisites.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Run prerequisites.mjs from this directory with the same arguments and exit code.
# Without node on PATH, print one fixed line and exit 1, because the checker
# cannot run and node is itself a missing required dependency.
#
#   sh prerequisites.sh check <plugin-root> [--for <scope>]
if command -v node >/dev/null 2>&1; then
  case "$0" in
  */*) here="${0%/*}" ;;
  *) here=. ;;
  esac
  exec node "$here/prerequisites.mjs" "$@"
fi
echo "prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again."
exit 1
