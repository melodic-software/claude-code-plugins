#!/usr/bin/env bash
# A small fake install root with secret-bearing files holding canary tokens, plus aged leftovers.
set -euo pipefail
root=fixture-claude
mkdir -p "${root}/ide" "${root}/debug" "${root}/shell-snapshots" "${root}/projects/-tmp-demo"
printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-CANARYq7Zt4Wx9Lm2","refreshToken":"sk-ant-ort01-CANARYp3Vb8Nk5Rd1"}}\n' >"${root}/.credentials.json"
printf '{"pid":1,"authToken":"CANARYide6Hj2Fs8Qe4"}\n' >"${root}/ide/48211.lock"
printf '{"cleanupPeriodDays":30}\n' >"${root}/settings.json"
printf 'old debug output\n' >"${root}/debug/0c1d2e3f.txt"
printf 'export PATH=/usr/bin\n' >"${root}/shell-snapshots/snapshot-bash-1700000000000-abcd12.sh"
printf '{"type":"user"}\n' >"${root}/projects/-tmp-demo/5f0e9a1c.jsonl"
touch -d '120 days ago' "${root}/debug/0c1d2e3f.txt" \
  "${root}/shell-snapshots/snapshot-bash-1700000000000-abcd12.sh" \
  "${root}/projects/-tmp-demo/5f0e9a1c.jsonl"
