#!/usr/bin/env bash
# Writes the probe page, two playwright-cli configs and the step list into the
# workspace, and serves site/ on 127.0.0.1 for the localhost step.
set -euo pipefail
shopt -s nullglob

case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws="$PWD"
# A free port per run, so each run's server is its own and concurrent or
# later runs never depend on another run's server lifetime.
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"

# A scaffold gets no EVAL_* variable, and a Bash allow rule does not match past
# a PLAYWRIGHT_BROWSERS_PATH= prefix, so the Chromium that
# .github/workflows/eval-browser-dispatch.yml installs under /opt/pw is pinned
# here by path. A missing install leaves a path that fails loudly at open.
chrome=/opt/pw/chromium-not-found
for candidate in /opt/pw/chromium-*/chrome-linux*/chrome; do
  chrome="$candidate"
done

mkdir -p probe
cat >probe/index.html <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>browser-probe-file-page</title></head>
<body><h1>Browser probe</h1><p>Loaded from the run's workspace.</p></body></html>
HTML

cat >probe/pinned.json <<JSON
{
  "browser": { "browserName": "chromium", "launchOptions": { "executablePath": "$chrome" } },
  "allowUnrestrictedFileAccess": true
}
JSON

cat >probe/default.json <<'JSON'
{ "allowUnrestrictedFileAccess": true }
JSON

steps=()
for session in pinned default; do
  steps+=(
    "playwright-cli -s=$session open --config=$ws/probe/$session.json file://$ws/probe/index.html"
    "playwright-cli -s=$session screenshot --filename=$ws/$session-shot.png"
    "playwright-cli -s=$session goto http://127.0.0.1:$port/"
    "playwright-cli -s=$session goto https://example.com/"
    "playwright-cli -s=$session goto file://$case_dir/peek/canary.html"
  )
done
printf '%s\n' \
  "playwright-cli --version" \
  "${steps[@]}" \
  "playwright-cli -s=pinned close" \
  "playwright-cli -s=default close" \
  "READ $case_dir/peek/canary.txt" >probe/commands.txt

# Outside the sandbox, detached and time-boxed.
setsid nohup timeout 1800 python3 -m http.server "$port" --bind 127.0.0.1 \
  --directory "$case_dir/site" >/dev/null 2>&1 </dev/null &
