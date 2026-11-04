#!/usr/bin/env bash
# A step-1 spool left by a 307 that curl, without -L, did not follow: exit 0 and a short text/plain
# "Temporary Redirect" body (failure-modes.md "Step 1: xtomd status handling": the same shape with a
# 307 carries a text/plain "Temporary Redirect" body). The redirect target is invented.
set -euo pipefail
mkdir -p notes
cat >notes/x-7777777777777777777-r7.md <<'TXT'
Temporary Redirect. Redirecting to https://edge-b.xtomd.com/api/markdown
TXT
