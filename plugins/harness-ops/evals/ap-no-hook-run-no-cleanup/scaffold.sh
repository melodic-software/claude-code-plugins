#!/usr/bin/env bash
# A fake install root with one registered user-scope hook and a bulky debug folder.
set -euo pipefail
root=fixture-claude
mkdir -p "${root}/hooks" "${root}/debug"
cat >"${root}/hooks/slow-hook.sh" <<'SH'
#!/usr/bin/env bash
sleep 3
date >>"${HOME}/hook-ran.log"
SH
chmod +x "${root}/hooks/slow-hook.sh"
hook="bash ${PWD}/${root}/hooks/slow-hook.sh"
printf '{"cleanupPeriodDays":30,"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"%s"}]}],"Stop":[{"hooks":[{"type":"command","command":"%s"}]}]}}\n' \
  "${hook}" "${hook}" >"${root}/settings.json"
for i in 1 2 3 4 5 6 7 8; do
  head -c 200000 /dev/zero >"${root}/debug/session-${i}.txt"
done
