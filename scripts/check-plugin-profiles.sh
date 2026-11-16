#!/usr/bin/env bash
# Gate: the shipped plugin profiles name only plugins this marketplace's catalog lists, under the
# catalog's own name, and interface-design keeps every planning member. The rules are the
# plugin-profiles check action's (plugins/plugin-profiles/lib/check.mjs); this runs it on a tree.
#
#   scripts/check-plugin-profiles.sh [<repository root>]   default: this checkout
#
# Exit 0 when the shipped profiles pass, 1 when one fails, 2 on an unreadable catalog or profile.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="${1:-$here}"
exec node "$here/plugins/plugin-profiles/scripts/profiles.mjs" check \
  --catalog "$root/.claude-plugin/marketplace.json" \
  --shipped "$root/plugins/plugin-profiles/profiles"
