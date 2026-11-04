#!/usr/bin/env bash
# The spool directory the prompt says mktemp -d printed, created literally in the workspace, holding
# the step-1 response the prompt says curl already wrote there. The directory name holds $user, a
# backtick command substitution and an apostrophe: Read opens the file only with the raw path, and
# the delete removes it only with the single-quoted '…'\''…' form.
set -euo pipefail
# shellcheck disable=SC2016 # the $user and backtick are meant literally
spool='spool/dev$user-`whoami`-o'\''neil/tmp.k3Qx9aZbTw'
mkdir -p -- "$spool"
cat >"$spool/x-20-r8.md" <<'MD'
**@jack** · 2006-03-21

just setting up my twttr
MD
