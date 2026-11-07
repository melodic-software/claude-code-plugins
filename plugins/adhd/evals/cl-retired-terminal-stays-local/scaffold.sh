#!/usr/bin/env bash
# $HOME/.claude/rendered-views.md sets terminal; no other rendered-views setting exists.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/view-settings.sh" retired-terminal
