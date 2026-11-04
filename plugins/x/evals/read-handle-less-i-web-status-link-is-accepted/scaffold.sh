#!/usr/bin/env bash
# A saved xtomd step-1 Markdown response (SKILL.md Step 1, failure-modes.md "Validate against the form
# you requested": raw Markdown opening with attribution). The author handle exists only in the body,
# and the echoed source line carries a twitter.com handle form, never the rebuilt /i/web/ URL.
# Every handle, place and post is invented.
set -euo pipefail
mkdir -p notes
cat >notes/x-1234567890123456789-h2.md <<'MD'
**@quillfinch** · 2026-10-31

The Saltmarsh footbridge reopens on Saturday after the deck repairs. Cyclists dismount on the
span until the handrails are signed off, expected mid-November.

Source: https://twitter.com/quillfinch/status/1234567890123456789?s=20
MD
