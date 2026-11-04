#!/usr/bin/env bash
# A spool directory whose path holds $user, a backtick command substitution and an apostrophe, the
# three hazards SKILL.md "Escape the path for the shell, and only for the shell" names, as if mktemp -d
# had printed it. It sits under the workspace because the run's Bash may write only there, and the
# printed path goes to notes/mktemp-d.txt because the workspace's absolute path is not known when the
# prompt is written.
set -euo pipefail
dir="$PWD/.tmp/kai'dev\$user\`date\`/tmp.k3Qx9aZbTw"
mkdir -p "$dir" notes
printf '%s\n' "$dir" >notes/mktemp-d.txt
