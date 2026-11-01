#!/usr/bin/env bash
# A partial xtomd spool left by a transfer that curl aborted with exit 63: valid Markdown, cut off mid-post.
set -euo pipefail
mkdir -p notes
cat >notes/x-3456789012345678901-q7.md <<'MD'
**@fakehandle** · 2026-10-28

# Brackenridge harbor survey: what we found

The survey team finished the second pass over the eastern breakwater last week. Three of the
eleven caissons show
MD
