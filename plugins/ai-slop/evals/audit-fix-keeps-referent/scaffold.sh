#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs
cat > docs/opening.md <<'MD'
# Opening shift

Ovens go on at 5:30 and reach `220C` before the first trays go in.

Wholesale drivers pull up at the back door at 6:15 to add next-day bread (paperwork friction kills standing orders; the standing-order clipboard lives where the drivers already stop).

On Tuesdays the supplier leaves the flour delivery invoice on the back-door shelf, and the manager signs it before the sacks go into the store room.

Closing staff wipe the standing-order clipboard after the last driver leaves.
MD
