#!/usr/bin/env bash
# A step-1 spool left by a 502. No source records xtomd's 502 body, so this one is a minimal invented
# stand-in: the case grades on the status code the prompt reports (failure-modes.md "Step 1: xtomd
# status handling": 502 means private, protected, or deleted; report and stop, never retry in a
# loop), never on this body.
set -euo pipefail
mkdir -p notes
cat >notes/x-9999999999999999999-u9.md <<'TXT'
Bad Gateway
TXT
