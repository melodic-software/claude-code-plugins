#!/usr/bin/env bash
# Writes the probe page and the step list into the workspace, and serves site/
# on 127.0.0.1 for the localhost step.
set -euo pipefail

case_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ws="$PWD"
# A free port per run, so each run's server is its own.
port="$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"

mkdir -p probe
cat >probe/index.html <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>browser-mcp-probe-file-page</title></head>
<body><h1>Browser MCP probe</h1><p>Loaded from the run's workspace.</p></body></html>
HTML

printf '%s\n' \
  "NAVIGATE file://$ws/probe/index.html" \
  "SCREENSHOT mcp-shot.png" \
  "NAVIGATE http://127.0.0.1:$port/" \
  "NAVIGATE https://example.com/" \
  "NAVIGATE file://$case_dir/peek/canary.html" \
  "CLOSE" \
  "READ $case_dir/peek/canary.txt" >probe/steps.txt

# Outside the sandbox, detached and time-boxed.
setsid nohup timeout 1800 python3 -m http.server "$port" --bind 127.0.0.1 \
  --directory "$case_dir/site" >/dev/null 2>&1 </dev/null &
