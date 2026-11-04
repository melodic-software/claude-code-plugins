#!/usr/bin/env bash
# The spool directory the prompt says mktemp -d printed, created literally in the workspace. Its
# name holds $user, a backtick command substitution and an apostrophe, so only the single-quoted
# '…'\''…' form at the curl -o target and the delete names it; double quotes expand $user and run
# `whoami`, and no quotes split or break the command.
set -euo pipefail
# shellcheck disable=SC2016 # the $user and backtick are meant literally
spool='spool/dev$user-`whoami`-o'\''neil/tmp.k3Qx9aZbTw'
mkdir -p -- "$spool"
